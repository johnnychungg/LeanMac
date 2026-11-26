// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import Darwin
import LeanDomain
import LeanFeatures

/// Developer measurement helpers, active only when an environment variable asks for them
/// (for example `LEANMAC_AUTOOPEN=1 LEANMAC_AUTOSCAN=1 build/LeanMac.app/Contents/MacOS/LeanMac`).
/// They never run in normal use.
@MainActor
enum DebugTools {
    static func runIfRequested(openPopover: @escaping () -> Void) {
        // Memory measurement: LEANMAC_AUTOOPEN=1 opens the popover after 2 seconds.
        if ProcessInfo.processInfo.environment["LEANMAC_AUTOOPEN"] != nil {
            if let t = ProcessInfo.processInfo.environment["LEANMAC_SECTION"], let n = Int(t) { SystemCleanerManager.shared.selectedSection = n }
            if ProcessInfo.processInfo.environment["LEANMAC_SETTINGS"] != nil { UIState.shared.settingsOpen = true }
            if let t = ProcessInfo.processInfo.environment["LEANMAC_HWSUB"], let n = Int(t) { UIState.shared.hardwareSub = n }
            if let t = ProcessInfo.processInfo.environment["LEANMAC_TAB"], let n = Int(t) { UIState.shared.selectedMainTab = n }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { openPopover() }
        }

        if ProcessInfo.processInfo.environment["LEANMAC_AUTOSCAN"] != nil {
            func fp(_ tag: String) {
                var info = task_vm_info_data_t()
                var c = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
                _ = withUnsafeMutablePointer(to: &info) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(c)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &c) } }
                appLog("📏 \(tag): footprint \(info.phys_footprint >> 20) MB, peak \(info.ledger_phys_footprint_peak >> 20) MB")
            }
            fp("start")
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { fp("before junk"); SystemCleanerManager.shared.scanJunk() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 9) { fp("after junk"); SystemCleanerManager.shared.scanInstalledApps() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 16) { fp("after apps"); SystemCleanerManager.shared.scanLargeFiles() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 24) { fp("after large") }
        }
    }
}
