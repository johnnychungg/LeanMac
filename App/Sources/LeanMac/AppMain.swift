// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import AppKit
import Darwin
import LeanDesignSystem
import LeanDomain
import LeanFeatures
import LeanPlatform

private func displayReconfigCallback(
    display: CGDirectDisplayID,
    flags: CGDisplayChangeSummaryFlags,
    userInfo: UnsafeMutableRawPointer?
) {
    DispatchQueue.main.async {
        MainActor.assumeIsolated {
            DisplayManager.shared.refreshDisplays()
        }
    }
}

// MARK: - App Delegate

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    var mainMenuBarButton: NSStatusBarButton? { statusItem?.button }
    private var popover: NSPopover!
    private var cleanerReleaseWork: DispatchWorkItem?
    private let container: AppContainer

    init(container: AppContainer) {
        self.container = container
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Single instance: two copies would fight over the event tap, the SMC and the status item.
        if let bundleID = Bundle.main.bundleIdentifier {
            let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
            if !others.isEmpty {
                appLog("Another LeanMac instance is already running; exiting.")
                // exit() rather than terminate(): the termination hook would release the charge limit
                // that the instance already running is enforcing.
                exit(0)
            }
        }
        container.notifications.onActivate = { [weak self] in self?.showPopoverFromNotification() }
        container.notifications.setup()
        // Menu bar only app (no Dock icon)
        NSApp.setActivationPolicy(.accessory)
        AppearanceManager.shared.apply()

        // Initialize Popover
        let pop = NSPopover()
        pop.contentSize = NSSize(width: 380, height: 570)
        pop.behavior = .transient
        pop.delegate = self
        // Hide the little arrow that points at the menu bar icon. It is a private NSPopover property, so ask first:
        // if a future macOS drops it, the arrow simply stays.
        if pop.responds(to: NSSelectorFromString("setShouldHideAnchor:")) { pop.setValue(true, forKey: "shouldHideAnchor") }
        self.popover = pop
        AppearanceManager.shared.popover = pop
        AppearanceManager.shared.apply()

        // Initialize Status Item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = LeanLogo.menuBarImage()
            button.image?.accessibilityDescription = "LeanMac"
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            button.action = #selector(togglePopover)
            button.target = self
        }

        DebugTools.runIfRequested(openPopover: { [weak self] in self?.togglePopover() })

        // Menu bar live telemetry (temperature + CPU / RAM / GPU %)
        ThermalManager.shared.onMenuBarUpdate = { [weak self] _ in
            self?.refreshMenuBarStatusItem()
        }
        SystemMonitorManager.shared.onStatsUpdate = { [weak self] in
            self?.refreshMenuBarStatusItem()
        }
        refreshMenuBarStatusItem()

        // One update check shortly after launch (at most once a day); there is no repeating timer.
        DispatchQueue.main.asyncAfter(deadline: .now() + 45) { UpdateManager.shared.checkIfDue() }

        // Recover the Accessibility permission automatically if an update just invalidated it
        AccessibilityRecovery.handleLaunch()

        // Start Global Key Interceptor (F1/F2, AltTab, Snapping, Clipboard)
        KeyInterceptor.shared.start()

        // Eagerly initialize Managers
        BatteryManager.shared.restoreBluetoothIfNeeded()
        LegacyMigrations.run()
        BatteryManager.shared.releaseAdapterOnLaunch()
        _ = FinderCutPasteManager.shared
        _ = PermissionsManager.shared
        _ = SystemMonitorManager.shared
        _ = ScreenshotManager.shared

        // Register for display reconfiguration
        CGDisplayRegisterReconfigurationCallback(displayReconfigCallback, nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Synchronously restore the SMC charge switches on quit (release CHTE/CH0B but keep the CHLT ceiling when protection is on)
        BatteryManager.shared.restoreOnTerminateSync()
        // Only hand an external display's gamma table back to ColorSync if LeanMac really adjusted the gamma before
        DisplayManager.shared.restoreHardwareGammaIfNeeded()
    }

    private func refreshMenuBarStatusItem() {
        guard let button = statusItem?.button else { return }
        var parts: [String] = []
        if let tempText = ThermalManager.shared.menuBarDisplayText {
            parts.append(tempText)
        }
        if let statsText = SystemMonitorManager.shared.formattedMenuBarSummary() {
            parts.append(statsText)
        }
        if parts.isEmpty {
            button.title = ""
            button.imagePosition = .imageOnly
        } else {
            button.title = " " + parts.joined(separator: " · ")
            button.imagePosition = .imageLeading
        }
    }

    func showPopoverFromNotification() {
        if !popover.isShown { togglePopover() }
    }

    @objc func togglePopover() {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            // Update displays before showing
            DisplayManager.shared.refreshDisplays()
            // Build the UI on open and tear it down on close: no view tree/SwiftUI cache is kept while the popover is hidden
            cleanerReleaseWork?.cancel()
            popover.contentViewController = NSHostingController(
                rootView: MainView(displayManager: DisplayManager.shared)
                    .background(Color(nsColor: .windowBackgroundColor))
            )
            AppearanceManager.shared.apply()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    // Coordinates every energy-sensitive manager with the popover open/close lifecycle.
    func popoverDidShow(_ notification: Notification) {
        BatteryManager.shared.setPopoverVisible(true)
        PermissionsManager.shared.setPopoverVisible(true)
        ThermalManager.shared.setPopoverVisible(true)
        SystemMonitorManager.shared.setPopoverVisible(true)
        DisplayManager.shared.checkAccessibility()
        UpdateManager.shared.checkIfDue()
    }

    func popoverDidClose(_ notification: Notification) {
        BatteryManager.shared.setPopoverVisible(false)
        PermissionsManager.shared.setPopoverVisible(false)
        ThermalManager.shared.setPopoverVisible(false)
        SystemMonitorManager.shared.setPopoverVisible(false)
        popover.contentViewController = nil
        malloc_zone_pressure_relief(nil, 0)

        // After 60 seconds closed, release the Cleaner's scan data (large lists)
        cleanerReleaseWork?.cancel()
        let work = DispatchWorkItem { SystemCleanerManager.shared.releaseData() }
        cleanerReleaseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 60, execute: work)
    }
}

// MARK: - App Main

@main
@MainActor
enum LeanMacMain {
    // The container installs the real services (shell, notifications…) before anything else runs.
    static let container = AppContainer()
    static let delegate = AppDelegate(container: container)

    static func main() {
        let app = NSApplication.shared
        app.delegate = delegate
        app.run()
    }
}
