// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import ApplicationServices
import LeanDomain

/// Recovers the Accessibility permission by itself after the app is updated.
///
/// Why: an ad-hoc signed build has a Designated Requirement that is only the `cdhash`,
/// so every update looks like a different app to macOS, which invalidates the granted permission. The old entry
/// stays in System Settings (looking enabled) but has no effect;
/// users normally have to remove the app from the list and add it again.
///
/// Fix: when the permission is missing, reset the old TCC entry (if any) **once per
/// version** and then show the system prompt. The user only has to flip the switch, not
/// remove/add it by hand.
@MainActor
package enum AccessibilityRecovery {
    private static let lastResetVersionKey = "ax_recovery_version"

    package static func handleLaunch() {
        if AXIsProcessTrusted() { return }

        let defaults = UserDefaults.standard
        let version = (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0")
        guard defaults.string(forKey: lastResetVersionKey) != version else { return }

        resetAccessibilityPermission()
        defaults.set(version, forKey: lastResetVersionKey)

        // Wait until TCC finished the reset before asking again, so the prompt is not swallowed.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
    }

    private static func resetAccessibilityPermission() {
        guard let bundleID = Bundle.main.bundleIdentifier, !bundleID.isEmpty else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", "Accessibility", bundleID]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            appLog("🔐 AccessibilityRecovery: reset Accessibility permission for \(bundleID) (exit code \(process.terminationStatus))")
        } catch {
            appLog("⚠️ AccessibilityRecovery: could not reset permission: \(error.localizedDescription)")
        }
    }
}
