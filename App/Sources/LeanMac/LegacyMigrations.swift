// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import LeanFeatures

/// One-time clean-ups of data written by older versions. Safe to run on every launch.
@MainActor
enum LegacyMigrations {
    static func run() {
        removeLegacyClipboardData()
        // Pinning metrics to the menu bar was removed: switch old pins off so no stray text remains there.
        if !UserDefaults.standard.bool(forKey: "menubar_pins_removed") {
            let m = SystemMonitorManager.shared
            m.showCPUMenuBar = false; m.showRAMMenuBar = false; m.showGPUMenuBar = false; m.showNetMenuBar = false
            ThermalManager.shared.showMenuBarMetrics = false
            UserDefaults.standard.set(true, forKey: "menubar_pins_removed")
        }
    }

    /// Old versions stored clipboard history as plaintext; the feature is gone, so delete what is left.
    private static func removeLegacyClipboardData() {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let dir = base.appendingPathComponent("LeanMac", isDirectory: true)
        try? FileManager.default.removeItem(at: dir.appendingPathComponent("clipboard.json"))
        try? FileManager.default.removeItem(at: dir.appendingPathComponent("ClipboardImages", isDirectory: true))
    }
}
