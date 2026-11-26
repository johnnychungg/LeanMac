// SPDX-License-Identifier: GPL-3.0-only
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, version 3 of the License.
// See the LICENSE file in the repository root for the full text.

import Foundation
import LeanDomain
import AppKit
import IOKit
import Darwin

/// Tracks CPU %, RAM % and GPU % (when the device supports it) with plain Mach and IOKit calls (no shell/Process).
/// The polling timer only runs while at least one menu bar option is on, to keep idle CPU at 0%.
@MainActor
public final class SystemMonitorManager: ObservableObject {
    public static let shared = SystemMonitorManager()

    private enum Keys {
        package static let legacyCPURAM = "show_menubar_cpu_ram"
        package static let showCPU = "show_menubar_cpu"
        package static let showRAM = "show_menubar_ram"
        package static let showGPU = "show_menubar_gpu"
    }

    /// Caches the host port and the kernel page size once:
    /// Every `mach_host_self()` call adds a Mach send right, so not caching it would leak ports.
    private static let machHostPort: mach_port_t = mach_host_self()
    private static let hostPageSizeBytes: UInt64 = {
        var size: vm_size_t = 0
        if host_page_size(machHostPort, &size) == KERN_SUCCESS, size > 0 {
            return UInt64(size)
        }
        return UInt64(vm_kernel_page_size)
    }()

    @Published public var showCPUMenuBar: Bool {
        didSet {
            UserDefaults.standard.set(showCPUMenuBar, forKey: Keys.showCPU)
            syncPollingState()
        }
    }

    @Published public var showRAMMenuBar: Bool {
        didSet {
            UserDefaults.standard.set(showRAMMenuBar, forKey: Keys.showRAM)
            syncPollingState()
        }
    }

    @Published public var showGPUMenuBar: Bool {
        didSet {
            UserDefaults.standard.set(showGPUMenuBar, forKey: Keys.showGPU)
            syncPollingState()
        }
    }

    @Published public private(set) var cpuUsagePercent: Double = 0.0
    @Published public private(set) var ramUsagePercent: Double = 0.0
    @Published public private(set) var memoryStats: MemoryStats? = nil
    @Published public private(set) var netDownBps: Double = 0
    @Published public private(set) var netUpBps: Double = 0
    @Published public var showNetMenuBar: Bool = UserDefaults.standard.bool(forKey: "show_menubar_net") {
        didSet { UserDefaults.standard.set(showNetMenuBar, forKey: "show_menubar_net"); syncPollingState() }
    }
    private var prevNet: [String: (rx: UInt32, tx: UInt32)] = [:]
    private var prevNetDate: Date?
    @Published public private(set) var memoryPressure: MemoryPressure = .normal
    @Published public private(set) var gpuUsagePercent: Double = 0.0
    @Published public private(set) var hasGPU: Bool = false

    public var onStatsUpdate: (() -> Void)?

    private struct CoreTicks {
        package let user: UInt32
        package let sys: UInt32
        package let idle: UInt32
        package let nice: UInt32
    }

    private var prevCoreTicks: [CoreTicks]?
    private var pollTimer: Timer?
    /// Display/system is asleep (lid closed, sleep): do not sample, so the CPU is not woken for nothing.
    private var displaysAsleep = false
    private var sleepObservers: [NSObjectProtocol] = []
    private var initialDeltaWork: DispatchWorkItem?
    private var wakeObserver: NSObjectProtocol?
    private var popoverVisible = false
    private var previewCount = 0

    /// True while a screen of the app needs live numbers (independent of what is pinned to the menu bar).
    private var isPreviewing: Bool { popoverVisible && previewCount > 0 }

    public func setPopoverVisible(_ visible: Bool) {
        popoverVisible = visible
        syncPollingState()
    }

    /// The Thermals screen calls this when it appears/disappears so real CPU/RAM/GPU values are always shown.
    public func beginPreview() { previewCount += 1; syncPollingState() }
    public func endPreview() { previewCount = max(0, previewCount - 1); syncPollingState() }

    private init() {
        // The old version used one switch for CPU+RAM: when the new key is missing, inherit the old value for both.
        let defaults = UserDefaults.standard
        let legacy = defaults.bool(forKey: Keys.legacyCPURAM)
        self.showCPUMenuBar = defaults.object(forKey: Keys.showCPU) != nil ? defaults.bool(forKey: Keys.showCPU) : legacy
        self.showRAMMenuBar = defaults.object(forKey: Keys.showRAM) != nil ? defaults.bool(forKey: Keys.showRAM) : legacy
        self.showGPUMenuBar = UserDefaults.standard.bool(forKey: Keys.showGPU)

        if let initialGPU = Self.readGPUUtilization() {
            self.hasGPU = true
            self.gpuUsagePercent = initialGPU
        } else {
            self.hasGPU = false
        }

        // Reset the CPU baseline right after wake from sleep to avoid a garbage delta
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleSystemWake()
            }
        }

        let nc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.screensDidSleepNotification, NSWorkspace.willSleepNotification] {
            sleepObservers.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.displaysAsleep = true; self?.syncPollingState() }
            })
        }
        sleepObservers.append(nc.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.displaysAsleep else { return }
                self.displaysAsleep = false
                self.prevCoreTicks = nil
                self.syncPollingState()
            }
        })

        syncPollingState()
    }

    deinit {
        pollTimer?.invalidate()
        initialDeltaWork?.cancel()
        if let observer = wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    /// Summary string shown in the menu bar for the options that are on.
    public func formattedMenuBarSummary() -> String? {
        var parts: [String] = []
        if showCPUMenuBar {
            parts.append("CPU \(Int(cpuUsagePercent.rounded()))%")
        }
        if showRAMMenuBar {
            parts.append("RAM \(Int(ramUsagePercent.rounded()))%")
        }
        if showGPUMenuBar && hasGPU {
            let gpu = Int(gpuUsagePercent.rounded())
            parts.append("GPU \(gpu)%")
        }
        if showNetMenuBar {
            parts.append("↓\(NetRate.format(netDownBps, compact: true)) ↑\(NetRate.format(netUpBps, compact: true))")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Takes one immediate sample for the preview UI or right after a toggle is switched on.
    public func refreshNow() {
        sampleMetrics()
    }

    private func handleSystemWake() {
        prevCoreTicks = nil
        if showCPUMenuBar || showRAMMenuBar || showGPUMenuBar || isPreviewing {
            syncPollingState()
        }
    }

    private func syncPollingState() {
        initialDeltaWork?.cancel()
        initialDeltaWork = nil

        let shouldPoll = !displaysAsleep && (showCPUMenuBar || showRAMMenuBar || showGPUMenuBar || showNetMenuBar || isPreviewing)
        guard shouldPoll else {
            pollTimer?.invalidate()
            pollTimer = nil
            prevCoreTicks = nil
            onStatsUpdate?()
            return
        }

        let needsInitialCPUDelta = (showCPUMenuBar || isPreviewing) && (prevCoreTicks == nil)
        sampleMetrics()

        if needsInitialCPUDelta {
            let work = DispatchWorkItem { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self, self.showCPUMenuBar || self.isPreviewing else { return }
                    self.sampleMetrics()
                }
            }
            initialDeltaWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
        }

        if pollTimer == nil {
            let timer = Timer(timeInterval: 2.5, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.sampleMetrics()
                }
            }
            timer.tolerance = 0.4
            RunLoop.main.add(timer, forMode: .common)
            pollTimer = timer
        }
    }

    private func sampleMetrics() {
        if showCPUMenuBar || isPreviewing {
            if let cores = Self.readCoreTicks() {
                if let prev = prevCoreTicks, prev.count == cores.count {
                    self.cpuUsagePercent = Self.computeCPUDelta(from: prev, to: cores)
                }
                prevCoreTicks = cores
            }
        }
        if showRAMMenuBar || isPreviewing {
            if let m = Self.readMemoryStats() {
                self.memoryStats = m
                self.ramUsagePercent = m.usedPercent
            }
            self.memoryPressure = Self.readMemoryPressure()
        }

        if showNetMenuBar || isPreviewing {
            sampleNetwork()
        } else {
            prevNet.removeAll(); prevNetDate = nil
        }

        if showGPUMenuBar || isPreviewing || !hasGPU {
            if let gpu = Self.readGPUUtilization() {
                self.hasGPU = true
                self.gpuUsagePercent = gpu
            }
        }

        onStatsUpdate?()
    }

    // MARK: - Low-Level Mach & IOKit Samplers

    private static func readCoreTicks() -> [CoreTicks]? {
        var numCPUs: natural_t = 0
        var cpuInfo: processor_info_array_t?
        var numCpuInfo: mach_msg_type_number_t = 0

        let result = host_processor_info(
            machHostPort,
            PROCESSOR_CPU_LOAD_INFO,
            &numCPUs,
            &cpuInfo,
            &numCpuInfo
        )
        guard result == KERN_SUCCESS, let info = cpuInfo else { return nil }

        defer {
            let byteSize = vm_size_t(numCpuInfo) * vm_size_t(MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)), byteSize)
        }

        guard numCPUs > 0 else { return nil }

        var resultCores: [CoreTicks] = []
        resultCores.reserveCapacity(Int(numCPUs))
        info.withMemoryRebound(to: processor_cpu_load_info_data_t.self, capacity: Int(numCPUs)) { loads in
            for i in 0..<Int(numCPUs) {
                let t = loads[i].cpu_ticks
                resultCores.append(CoreTicks(
                    user: UInt32(t.0),
                    sys: UInt32(t.1),
                    idle: UInt32(t.2),
                    nice: UInt32(t.3)
                ))
            }
        }
        return resultCores
    }

    /// Wrapping subtraction (`&-`) per core on `UInt32` avoids a 100% CPU spike when a counter wraps past 2^32 ticks after a long uptime.
    private static func computeCPUDelta(from prev: [CoreTicks], to curr: [CoreTicks]) -> Double {
        var totalActive: UInt64 = 0
        var totalTicks: UInt64 = 0

        for i in 0..<curr.count {
            let userDiff = UInt64(curr[i].user &- prev[i].user)
            let sysDiff = UInt64(curr[i].sys &- prev[i].sys)
            let idleDiff = UInt64(curr[i].idle &- prev[i].idle)
            let niceDiff = UInt64(curr[i].nice &- prev[i].nice)

            let active = userDiff &+ sysDiff &+ niceDiff
            totalActive &+= active
            totalTicks &+= active &+ idleDiff
        }

        guard totalTicks > 0 else { return 0.0 }
        return min(max(Double(totalActive) / Double(totalTicks) * 100.0, 0.0), 100.0)
    }

    /// Reads RAM with the Activity Monitor formula (the maths lives in LeanDomain's MemoryStats).
    private static func readMemoryStats() -> MemoryStats? {
        let totalBytes = ProcessInfo.processInfo.physicalMemory
        guard totalBytes > 0, hostPageSizeBytes > 0 else { return nil }

        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(machHostPort, HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }
        return MemoryStats(internalPages: UInt64(stats.internal_page_count), purgeablePages: UInt64(stats.purgeable_count),
                           wiredPages: UInt64(stats.wire_count), compressedPages: UInt64(stats.compressor_page_count),
                           pageSize: hostPageSizeBytes, totalBytes: totalBytes)
    }

    private func sampleNetwork() {
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0, let first = ifap else { return }
        defer { freeifaddrs(ifap) }
        var current: [String: (rx: UInt32, tx: UInt32)] = [:]
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let ifa = ptr {
            defer { ptr = ifa.pointee.ifa_next }
            guard let addr = ifa.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK),
                  let data = ifa.pointee.ifa_data else { continue }
            let name = String(cString: ifa.pointee.ifa_name)
            guard name.hasPrefix("en") || name.hasPrefix("pdp_ip") else { continue }
            let d = data.assumingMemoryBound(to: if_data.self).pointee
            current[name] = (d.ifi_ibytes, d.ifi_obytes)
        }
        let now = Date()
        if let prevDate = prevNetDate {
            let dt = now.timeIntervalSince(prevDate)
            if dt > 0.2 {
                var rx: UInt64 = 0, tx: UInt64 = 0
                for (name, cur) in current {
                    if let p = prevNet[name] {
                        rx &+= NetRate.delta(prev: p.rx, cur: cur.rx)
                        tx &+= NetRate.delta(prev: p.tx, cur: cur.tx)
                    }
                }
                netDownBps = Double(rx) / dt
                netUpBps = Double(tx) / dt
            }
        }
        prevNet = current
        prevNetDate = now
    }

    private static func readMemoryPressure() -> MemoryPressure {
        var level: Int32 = 1
        var size = MemoryLayout<Int32>.size
        sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0)
        return MemoryPressure(sysctlLevel: Int(level))
    }

    private static func readGPUUtilization() -> Double? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IOAccelerator"),
            &iterator
        ) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        let gpuKeys = ["Device Utilization %", "GPU Activity(%)", "Renderer Utilization %", "GPU Activity"]
        var bestUtil: Double?

        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            var props: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let dict = props?.takeRetainedValue() as? [String: Any] else {
                continue
            }

            if let agc = dict["AGCInfo"] as? [String: Any],
               (agc["poweredOffByAGC"] as? NSNumber)?.intValue == 1 {
                continue
            }

            guard let perf = dict["PerformanceStatistics"] as? [String: Any] else {
                continue
            }

            for key in gpuKeys {
                if let value = (perf[key] as? NSNumber)?.doubleValue {
                    let clamped = min(max(value, 0.0), 100.0)
                    bestUtil = max(bestUtil ?? 0.0, clamped)
                    break
                }
            }
        }
        return bestUtil
    }
}
