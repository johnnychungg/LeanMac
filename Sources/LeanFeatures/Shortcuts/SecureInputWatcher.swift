// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import Combine

/// Finds the app that holds macOS "Secure Event Input". While one does (usually a browser or terminal that
/// forgot to release it after a password field), macOS hides every keystroke from all event taps, so no
/// keyboard shortcut of any utility can work until that app lets go or quits.
@MainActor
final class SecureInputWatcher: ObservableObject {
    static let shared = SecureInputWatcher()

    struct Holder: Equatable {
        let pid: pid_t
        let name: String
    }

    @Published private(set) var holder: Holder?
    private var timer: Timer?

    func start() {
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        let new = Self.currentHolder()
        if new != holder { holder = new }
    }

    func quitHolder() {
        guard let holder, let app = NSRunningApplication(processIdentifier: holder.pid) else { return }
        app.terminate()
    }

    private static func currentHolder() -> Holder? {
        guard let dict = CGSessionCopyCurrentDictionary() as? [String: Any],
              let pid = dict["kCGSSessionSecureInputPID"] as? Int, pid > 0,
              pid_t(pid) != ProcessInfo.processInfo.processIdentifier else { return nil }
        let app = NSRunningApplication(processIdentifier: pid_t(pid))
        return Holder(pid: pid_t(pid), name: app?.localizedName ?? "pid \(pid)")
    }
}
