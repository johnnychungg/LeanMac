// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import LeanDomain
import LeanDesignSystem

// MARK: - Hardware tab

struct HardwareTabView: View {
    @ObservedObject var batteryManager: BatteryManager
    @ObservedObject var thermalManager: ThermalManager
    @ObservedObject var displayManager: DisplayManager
    @ObservedObject private var ui = UIState.shared

    private func heading(_ text: String) -> some View {
        Text(text).font(.system(size: 12, weight: .medium)).foregroundStyle(Pal.ink3)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
    }

    var body: some View {
        TabScaffold(
            subItems: [tr("Battery"), tr("Displays"), tr("Monitor")],
            selection: $ui.hardwareSub
        ) {
            switch ui.hardwareSub {
            case 1: DisplaysSection(displayManager: displayManager)
            case 2: ThermalView(thermalManager: thermalManager)
            default:
                SMCPowerView(batteryManager: batteryManager)
                heading("Sleep Guard")
                SleepGuardView(batteryManager: batteryManager)
                heading(tr("Battery calibration"))
                CalibrationView(batteryManager: batteryManager)
            }
        }
    }
}

// MARK: - Display

struct DisplaysSection: View {
    @ObservedObject var displayManager: DisplayManager

    var body: some View {
        if displayManager.monitors.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "display.trianglebadge.exclamationmark").font(.system(size: 22)).foregroundStyle(Pal.ink3)
                Text(tr("No displays found")).font(.system(size: 13)).foregroundStyle(Pal.ink2)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 24)
        } else {
            JToggleRow(
                icon: "keyboard",
                title: tr("F1 / F2 adjust display under cursor"),
                isOn: Binding(get: { displayManager.isCursorBased }, set: { displayManager.isCursorBased = $0 })
            )
            .jCard()
            ForEach(displayManager.monitors) { monitor in
                DisplayCard(monitor: monitor, displayManager: displayManager)
            }
        }
    }
}

// MARK: - SMC power

struct SMCPowerView: View {
    @ObservedObject var batteryManager: BatteryManager

    private var isLocked: Bool {
        batteryManager.isProtectionEnabled && batteryManager.isBypassActive && batteryManager.isPluggedIn
    }

    private var statusTitle: String {
        if isLocked { return tr("Charge locked at \(batteryManager.chargeLimit)%") }
        if batteryManager.isCharging { return tr("Charging") }
        if batteryManager.isPluggedIn { return tr("Plugged in") }
        return tr("On battery")
    }

    private var statusDetail: String {
        if isLocked { return tr("Running directly from AC") }
        if batteryManager.isCharging { return tr("Charging the battery") }
        if batteryManager.isPluggedIn { return tr("Not charging") }
        return batteryManager.timeRemaining > 0 && batteryManager.timeRemaining < 6000
            ? tr("About \(batteryManager.timeRemaining / 60)h\(batteryManager.timeRemaining % 60)m left")
            : tr("Unplugged")
    }

    var body: some View {
        if !batteryManager.isHelperInstalled {
            let old = batteryManager.helperVersion > 0 && batteryManager.helperVersion != PrivilegedHelper.requiredVersion
            JBanner(
                icon: "exclamationmark.shield",
                text: old ? tr("SMC Helper update required (v\(PrivilegedHelper.requiredVersion))")
                          : tr("SMC Helper not installed"),
                actionTitle: batteryManager.isInstallingHelper ? tr("Installing…") : (old ? tr("Update") : tr("Install")),
                action: batteryManager.isInstallingHelper ? nil : { batteryManager.installHelper() }
            )
        }

        // Pin
        HStack(spacing: 14) {
            ZStack {
                Circle().stroke(Pal.lineStrong.opacity(0.5), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: CGFloat(min(max(batteryManager.currentLevel, 0), 100)) / 100)
                    .stroke(Pal.accent, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(batteryManager.currentLevel)%")
                    .font(.system(size: 22, weight: .medium)).foregroundStyle(Pal.ink)
            }
            .frame(width: 88, height: 88)

            VStack(alignment: .leading, spacing: 3) {
                Text(statusTitle).font(.system(size: 14, weight: .medium)).foregroundStyle(Pal.ink)
                Text(statusDetail).font(.system(size: 12)).foregroundStyle(Pal.ink2)
                HStack(spacing: 6) {
                    if batteryManager.adapterWatts > 0 && batteryManager.isPluggedIn {
                        JStatusChip(text: "\(batteryManager.adapterWatts)W", icon: "powerplug")
                    }
                    JStatusChip(text: String(format: "%.1fW", abs(batteryManager.wattage)), icon: "waveform.path.ecg")
                }
                .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .jCard()

        HStack(spacing: 6) {
            JTile(label: tr("Health"), value: "\(batteryManager.healthPercent)%")
            JTile(label: tr("Cycles"), value: "\(batteryManager.cycleCount)")
            JTile(label: tr("Temp"), value: batteryManager.temperature > 0 ? String(format: "%.0f°C", batteryManager.temperature) : "–")
            JTile(label: tr("Adapter"), value: batteryManager.adapterWatts > 0 ? "\(batteryManager.adapterWatts)W" : "–")
        }

        ChargeLockCard(batteryManager: batteryManager)

        // Warnings
        VStack(spacing: 0) {
            JToggleRow(icon: "thermometer.sun", title: tr("Alert when battery over 38°C"),
                       isOn: Binding(get: { batteryManager.isTempAlertEnabled }, set: { batteryManager.isTempAlertEnabled = $0 }))
                .padding(.vertical, 8)
            JDivider()
            JToggleRow(icon: "bell.badge", title: tr("Warn under 20% with external display"),
                       isOn: Binding(get: { batteryManager.isSmartAlertsEnabled }, set: { batteryManager.isSmartAlertsEnabled = $0 }))
                .padding(.vertical, 8)
        }
        .padding(.horizontal, 12).padding(.vertical, 2)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Pal.card))

        Text(tr("Turn off “Optimized Battery Charging” in System Settings so macOS doesn't charge to 100%."))
            .font(.system(size: 12)).foregroundStyle(Pal.ink3)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Charge lock card (used in Overview and the Battery tab)

struct ChargeLockCard: View {
    @ObservedObject var batteryManager: BatteryManager

    private var limitIndex: Int { [70, 80, 90].firstIndex(of: batteryManager.chargeLimit) ?? 1 }

    var body: some View {
        VStack(spacing: 10) {
            JToggleRow(
                icon: "lock",
                title: tr("Charge limit"),
                subtitle: tr("Bypass battery, no wear"),
                isOn: Binding(
                    get: { batteryManager.isProtectionEnabled },
                    set: { newVal in
                        if newVal && !batteryManager.isHelperInstalled {
                            batteryManager.isProtectionEnabled = true
                            batteryManager.installHelper { ok in if !ok { batteryManager.isProtectionEnabled = false } }
                        } else {
                            batteryManager.isProtectionEnabled = newVal
                        }
                    }
                )
            )
            if batteryManager.isProtectionEnabled {
                JSegmented(items: ["70%", "80%", "90%"], selection: Binding(
                    get: { limitIndex },
                    set: { idx in
                        let val = [70, 80, 90][idx]
                        if val < 80 && !batteryManager.isHelperInstalled {
                            batteryManager.installHelper { ok in if ok { batteryManager.chargeLimit = val } }
                        } else {
                            batteryManager.chargeLimit = val
                        }
                    }
                ))
            }
            Button { batteryManager.isTopUpActive.toggle() } label: {
                HStack(spacing: 6) {
                    Image(systemName: batteryManager.isTopUpActive ? "xmark.circle" : "bolt.fill")
                    Text(batteryManager.isTopUpActive ? tr("Cancel 100%, re-lock") : tr("Temporary 100% top-up"))
                }
            }
            .buttonStyle(JButtonStyle(kind: .ghost))
        }
        .jCard()
    }
}

// MARK: - Sleep Guard

struct SleepGuardView: View {
    @ObservedObject var batteryManager: BatteryManager
    @ObservedObject var permissions: PermissionsManager = PermissionsManager.shared

    var body: some View {
        VStack(spacing: 0) {
            JToggleRow(icon: "moon.stars", title: tr("Sleep Guard on lid close"),
                       subtitle: tr("Prevents Dark Wake and background heat"),
                       isOn: Binding(get: { batteryManager.isSleepGuardEnabled }, set: { batteryManager.isSleepGuardEnabled = $0 }),
                       trailing: AnyView(JInfoButton(text: tr("Always automatic on lid close/Sleep: LeanMac stops background timers, pauses CPU/RAM/GPU sampling and releases App Nap so it never wakes the Mac; the charge limit is still locked before sleep."))))
                .padding(.vertical, 8)
            if batteryManager.isSleepGuardEnabled {
                JDivider()
                JToggleRow(icon: "wave.3.right", title: tr("Turn off Bluetooth on lid close"),
                           subtitle: tr("Restored on wake"),
                           isOn: Binding(get: { batteryManager.sleepGuardTurnOffBluetooth }, set: { batteryManager.sleepGuardTurnOffBluetooth = $0 }))
                    .padding(.vertical, 8)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 2)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Pal.card))

        if batteryManager.isSleepGuardEnabled && batteryManager.sleepGuardTurnOffBluetooth && !permissions.hasBluetooth {
            JBanner(icon: "exclamationmark.triangle", text: tr("Bluetooth permission missing"),
                    actionTitle: tr("Grant")) { permissions.openBluetoothSettings() }
        }

        if !batteryManager.lastSleepReport.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(tr("Last sleep")).font(.system(size: 13, weight: .medium)).foregroundStyle(Pal.ink)
                Text(batteryManager.lastSleepReport).font(.system(size: 12)).foregroundStyle(Pal.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .jCard()
        }
    }
}

// MARK: - Calibration

struct CalibrationView: View {
    @ObservedObject var batteryManager: BatteryManager

    private func fmt(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "dd/MM/yyyy"; return f.string(from: d)
    }

    var body: some View {
        VStack(spacing: 0) {
            JToggleRow(icon: "calendar.badge.clock", title: tr("Auto-calibrate periodically"),
                       isOn: Binding(get: { batteryManager.isAutoCalibrationEnabled }, set: { batteryManager.isAutoCalibrationEnabled = $0 }))
                .padding(.vertical, 8)
        }
        .padding(.horizontal, 12).padding(.vertical, 2)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Pal.card))

        if batteryManager.isAutoCalibrationEnabled {
            VStack(alignment: .leading, spacing: 10) {
                Text(tr("Interval")).font(.system(size: 13, weight: .medium)).foregroundStyle(Pal.ink)
                HStack(spacing: 6) {
                    ForEach([30, 45, 60], id: \.self) { d in
                        JChip(text: tr("\(d) days"), selected: batteryManager.calibrationIntervalDays == d) {
                            batteryManager.calibrationIntervalDays = d
                        }
                    }
                }
                HStack(spacing: 6) {
                    JTile(label: tr("Next"), value: fmt(batteryManager.nextScheduledCalibrationDate))
                    JTile(label: tr("Left"), value: tr("\(batteryManager.daysRemainingUntilCalibration)d"))
                    JTile(label: tr("Last"), value: batteryManager.lastCalibrationDate.map(fmt) ?? "–")
                }
                Text(tr("When due: drain to 20% or lower, plug in, LeanMac charges to 100%, rests 15 min then re-locks."))
                    .font(.system(size: 12)).foregroundStyle(Pal.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .jCard()
        }

        if batteryManager.calibrationState == .idle {
            Button { batteryManager.startCalibration() } label: {
                HStack(spacing: 6) { Image(systemName: "play.fill"); Text(tr("Calibrate now")) }
            }
            .buttonStyle(JButtonStyle())
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(batteryManager.calibrationMessage).font(.system(size: 13, weight: .medium)).foregroundStyle(Pal.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button { batteryManager.cancelCalibration() } label: {
                    Text(tr("Cancel, back to \(batteryManager.chargeLimit)% lock"))
                }
                .buttonStyle(JButtonStyle(kind: .ghost))
            }
            .jCard()
        }
    }
}

// MARK: - System monitoring (CPU / RAM / GPU / Battery / SSD / Network)


/// One metric card: icon + name, pin-to-menu-bar buttons on the right, content below.
private enum MonLevel {
    case normal, warn, danger
    var color: Color { self == .normal ? Pal.ink : (self == .warn ? Pal.warn : Pal.danger) }
    static func percent(_ v: Double) -> MonLevel { v >= 90 ? .danger : (v >= 70 ? .warn : .normal) }
    static func temp(_ v: Double) -> MonLevel {
        v >= ThermalManager.hotThreshold ? .danger : (v >= ThermalManager.warmThreshold ? .warn : .normal)
    }
    func worse(_ o: MonLevel) -> MonLevel { (self == .danger || o == .danger) ? .danger : ((self == .warn || o == .warn) ? .warn : .normal) }
}

/// One row: icon | name | % | temperature (or capacity). No gauge, no extra buttons.
private struct MonRow: View {
    let icon: String
    let title: String
    let value: String
    var valueLevel: MonLevel = .normal
    var secondary: String = ""
    var secondaryLevel: MonLevel = .normal

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 13)).foregroundStyle(Pal.accent).frame(width: 18)
            Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(Pal.ink)
            Spacer(minLength: 4)
            Text(value).font(.system(size: 14, weight: .semibold)).monospacedDigit()
                .foregroundStyle(valueLevel.color)
                .frame(width: 48, alignment: .trailing)
            Text(secondary).font(.system(size: 12)).monospacedDigit()
                .foregroundStyle(secondaryLevel == .normal ? Pal.ink3 : secondaryLevel.color)
                .frame(width: 92, alignment: .trailing)
        }
        .frame(height: 34)
        .padding(.horizontal, 12)
    }
}

struct ThermalView: View {
    @ObservedObject var thermalManager: ThermalManager
    @ObservedObject var monitor: SystemMonitorManager = SystemMonitorManager.shared
    @ObservedObject var battery: BatteryManager = BatteryManager.shared

    private func t(_ v: Double) -> String { v > 0 ? String(format: "%.0f°C", v) : "–" }
    private func pct(_ v: Double) -> String { "\(Int(v.rounded()))%" }

    private var levelKind: JStatusChip.Kind {
        switch thermalManager.thermalLevel {
        case .cool: return .ok
        case .warm, .hot: return .warn
        }
    }

    private var diskInfo: (used: Double, total: Double)? {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        guard let v = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]),
              let total = v.volumeTotalCapacity, let free = v.volumeAvailableCapacityForImportantUsage, total > 0 else { return nil }
        let tt = Double(total), f = Double(free)
        return (tt - f, tt)
    }

    var body: some View {
        Color.clear.frame(height: 0)
            .onAppear { monitor.beginPreview() }
            .onDisappear { monitor.endPreview() }

        // Machine overview (one line)
        HStack(spacing: 8) {
            Image(systemName: "laptopcomputer").font(.system(size: 13)).foregroundStyle(Pal.accent)
            Text(thermalManager.machineModelName).font(.system(size: 13, weight: .medium)).foregroundStyle(Pal.ink).lineLimit(1)
            Spacer()
            JStatusChip(text: thermalManager.isThrottling ? tr("Throttled") : tr("Normal"),
                        kind: thermalManager.isThrottling ? .warn : levelKind)
            Button { thermalManager.refreshMetrics() } label: {
                Image(systemName: "arrow.clockwise").font(.system(size: 12)).foregroundStyle(Pal.ink3)
            }
            .buttonStyle(.plain)
            .help(tr("Refresh"))
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Pal.card))

        // Six metrics in one card
        VStack(spacing: 0) {
            MonRow(icon: "cpu", title: "CPU", value: pct(monitor.cpuUsagePercent), valueLevel: MonLevel.percent(monitor.cpuUsagePercent),
                   secondary: t(thermalManager.cpuAvgTemp), secondaryLevel: MonLevel.temp(thermalManager.cpuAvgTemp))
            JDivider().padding(.leading, 38)
            MonRow(icon: "memorychip", title: "RAM", value: pct(monitor.ramUsagePercent),
                   valueLevel: monitor.memoryPressure == .critical ? .danger : (monitor.memoryPressure == .warning ? .warn : .normal),
                   secondary: monitor.memoryStats?.summary ?? "")
            JDivider().padding(.leading, 38)
            MonRow(icon: "display", title: "GPU", value: monitor.hasGPU ? pct(monitor.gpuUsagePercent) : "–",
                   valueLevel: MonLevel.percent(monitor.gpuUsagePercent),
                   secondary: t(thermalManager.gpuAvgTemp), secondaryLevel: MonLevel.temp(thermalManager.gpuAvgTemp))
            JDivider().padding(.leading, 38)
            MonRow(icon: battery.isCharging ? "battery.100.bolt" : "battery.100", title: tr("Battery"), value: "\(battery.currentLevel)%",
                   valueLevel: battery.currentLevel <= 10 ? .danger : (battery.currentLevel <= 20 ? .warn : .normal),
                   secondary: t(thermalManager.batteryTemp), secondaryLevel: MonLevel.temp(thermalManager.batteryTemp))
            if let d = diskInfo {
                JDivider().padding(.leading, 38)
                MonRow(icon: "internaldrive", title: "SSD", value: pct(d.used / d.total * 100),
                       valueLevel: d.used / d.total > 0.9 ? .warn : .normal,
                       secondary: String(format: "%.0f / %.0f GB", d.used / 1e9, d.total / 1e9))
            }
            JDivider().padding(.leading, 38)
            HStack(spacing: 8) {
                Image(systemName: "arrow.up.arrow.down").font(.system(size: 13)).foregroundStyle(Pal.accent).frame(width: 18)
                Text(tr("Net")).font(.system(size: 13, weight: .medium)).foregroundStyle(Pal.ink)
                Spacer(minLength: 4)
                Text("↓ \(NetRate.format(monitor.netDownBps))   ↑ \(NetRate.format(monitor.netUpBps))")
                    .font(.system(size: 12)).monospacedDigit().foregroundStyle(Pal.ink)
            }
            .frame(height: 34)
            .padding(.horizontal, 12)
        }
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Pal.card))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

        // Hot spots and sensor details
        if thermalManager.hotspotTemp > 0 {
            HStack {
                Text(tr("Hottest spot")).font(.system(size: 12)).foregroundStyle(Pal.ink2)
                Spacer()
                Text(t(thermalManager.hotspotTemp)).font(.system(size: 12, weight: .medium)).foregroundStyle(Pal.ink)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Pal.card))
        }

        if !thermalManager.detailedSensors.isEmpty {
            VStack(spacing: 0) {
                Button { withAnimation(.easeOut(duration: 0.15)) { thermalManager.isDetailExpanded.toggle() } } label: {
                    HStack {
                        Text(tr("\(thermalManager.detailedSensors.count) sensor details"))
                            .font(.system(size: 13, weight: .medium)).foregroundStyle(Pal.ink)
                        Spacer()
                        Image(systemName: thermalManager.isDetailExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .medium)).foregroundStyle(Pal.ink3)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if thermalManager.isDetailExpanded {
                    VStack(spacing: 0) {
                        ForEach(thermalManager.detailedSensors) { s in
                            JDivider().padding(.top, 6)
                            HStack {
                                Text(s.displayName).font(.system(size: 12)).foregroundStyle(Pal.ink2).lineLimit(1)
                                Spacer()
                                Text(String(format: "%.1f°C", s.temp)).font(.system(size: 12, weight: .medium)).foregroundStyle(Pal.ink)
                            }
                            .padding(.top, 6)
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .jCard()
        }
    }
}
