// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import AppKit
import CoreGraphics
import CoreBluetooth
import ApplicationServices
import Combine

// MARK: - Permission Item Model

public struct PermissionDetailItem: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let icon: String
    public let tag: String
    public let isRequired: Bool
    public let isGranted: Bool
    public let reason: String
    public let settingsURLString: String
}

// MARK: - Permissions Manager (Centralized TCC & System Permissions Hub)

@MainActor
public class PermissionsManager: ObservableObject {
    public static let shared = PermissionsManager()

    @Published public var hasAccessibility: Bool = false
    @Published public var hasScreenCapture: Bool = false
    @Published public var hasSMCHelper: Bool = false
    @Published public var hasBluetooth: Bool = false

    @Published public var isExpanded: Bool = false
    @Published public var isProbing: Bool = false

    private var pollTimer: Timer?
    private var isFirstCheck = true
    private var isPopoverVisible = false
    private var activeObserver: NSObjectProtocol?

    public var allGranted: Bool {
        hasAccessibility && hasScreenCapture && hasSMCHelper
    }

    public var requiredGranted: Bool {
        hasAccessibility
    }

    public var missingCount: Int {
        var count = 0
        if !hasAccessibility { count += 1 }
        if !hasScreenCapture { count += 1 }
        if !hasSMCHelper { count += 1 }
        return count
    }

    private init() {
        refreshStatus()
        // Auto-expand if accessibility is missing so new users see it immediately
        if !hasAccessibility {
            self.isExpanded = true
        }

        // Only check when the user returns from System Settings or opens the popover (zero wakeups in the background).
        activeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshStatus()
            }
        }
    }

    deinit {
        pollTimer?.invalidate()
        if let observer = activeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    public func setPopoverVisible(_ visible: Bool) {
        isPopoverVisible = visible
        if visible {
            refreshStatus()
            if pollTimer == nil {
                let t = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.refreshStatus()
                    }
                }
                t.tolerance = 0.4
                RunLoop.main.add(t, forMode: .common)
                pollTimer = t
            }
        } else {
            pollTimer?.invalidate()
            pollTimer = nil
        }
    }

    // MARK: - Live Permission Checks

    public func refreshStatus() {
        // 1. Accessibility
        let axTrusted = AXIsProcessTrusted()
        if self.hasAccessibility != axTrusted {
            self.hasAccessibility = axTrusted
        }

        // 2. Screen Capture
        let screenTrusted = CGPreflightScreenCaptureAccess()
        if self.hasScreenCapture != screenTrusted {
            self.hasScreenCapture = screenTrusted
        }

        // 3. SMC helper (80% charge lock)
        let smcInstalled = BatteryManager.shared.isHelperInstalled
        if self.hasSMCHelper != smcInstalled {
            self.hasSMCHelper = smcInstalled
        }

        // 4. Bluetooth (Sleep Guard)
        if #available(macOS 10.15, *) {
            let btStatus = CBCentralManager.authorization
            let btTrusted = (btStatus == .allowedAlways)
            if self.hasBluetooth != btTrusted {
                self.hasBluetooth = btTrusted
            }
        } else {
            self.hasBluetooth = true
        }

        // Auto-collapse when user has granted all required permissions for the first time
        if isFirstCheck {
            isFirstCheck = false
            if requiredGranted {
                self.isExpanded = false
            }
        }
    }

    // MARK: - Deep probe (really test every permission)

    public func runDeepProbe() {
        guard !isProbing else { return }
        self.isProbing = true
        BatteryManager.shared.checkHelperStatus { [weak self] _ in
            self?.refreshStatus()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                self?.isProbing = false
            }
        }
    }

    // MARK: - Actions

    public func openAccessibilitySettings() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    public func openScreenCaptureSettings() {
        CGRequestScreenCaptureAccess()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    public func installSMCHelper() {
        BatteryManager.shared.installHelper { [weak self] success in
            self?.refreshStatus()
        }
    }

    /// Keep a reference so the Bluetooth permission dialog is not dismissed immediately.
    private var bluetoothProbe: CBCentralManager?

    public func openBluetoothSettings() {
        // Never asked yet: create a CBCentralManager so macOS shows the permission dialog and lists LeanMac under Bluetooth.
        if CBCentralManager.authorization == .notDetermined {
            bluetoothProbe = CBCentralManager(delegate: nil, queue: nil, options: [CBCentralManagerOptionShowPowerAlertKey: false])
            return
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth") {
            NSWorkspace.shared.open(url)
        }
    }
}

