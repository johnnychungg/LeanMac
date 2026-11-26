// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import AppKit
import UserNotifications
import LeanDomain

/// Native LeanMac notifications (shows the app icon; clicking one does not open Script Editor).
@MainActor
public final class NotificationManager: NSObject, UNUserNotificationCenterDelegate, Notifying, @unchecked Sendable {
    private var requested = false
    /// Called when the user clicks a notification. The app sets it to open the popover.
    public var onActivate: (@MainActor () -> Void)?

    public override init() { super.init() }

    public func setup() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        requestAuthorizationIfNeeded()
    }

    private func requestAuthorizationIfNeeded() {
        guard !requested else { return }
        requested = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error { appLog("Notification auth error: \(error.localizedDescription)") }
            else { appLog("Notification permission granted: \(granted)") }
        }
    }

    nonisolated public func send(title: String, body: String, sound: Bool) {
        Task { @MainActor in self.post(title: title, body: body, sound: sound) }
    }

    private func post(title: String, body: String, sound: Bool) {
        requestAuthorizationIfNeeded()
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if sound { content.sound = .default }
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req) { error in
            if let error { appLog("Notification error: \(error.localizedDescription)") }
        }
    }

    // Show the banner even while the app is "active" (a menu bar app is active whenever the popover is open).
    nonisolated public func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                                   withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    // Clicking a notification opens the LeanMac popover.
    nonisolated public func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                                   withCompletionHandler completionHandler: @escaping () -> Void) {
        Task { @MainActor in self.onActivate?() }
        completionHandler()
    }
}
