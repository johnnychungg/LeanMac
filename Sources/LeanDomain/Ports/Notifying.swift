// SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// Posts a user notification. Implemented by `LeanPlatform` with UserNotifications.
public protocol Notifying: Sendable {
    func send(title: String, body: String, sound: Bool)
}

/// Injection point for `Notifying` (same transitional pattern as `Shell`). The default does nothing.
public enum Notifier {
    private final class Box: @unchecked Sendable {
        package let lock = NSLock()
        package var sender: Notifying = NoopNotifier()
    }
    private static let box = Box()

    public static var sender: Notifying {
        get { box.lock.lock(); defer { box.lock.unlock() }; return box.sender }
        set { box.lock.lock(); defer { box.lock.unlock() }; box.sender = newValue }
    }

    public static func send(title: String, body: String, sound: Bool = true) {
        sender.send(title: title, body: body, sound: sound)
    }
}

struct NoopNotifier: Notifying {
    func send(title: String, body: String, sound: Bool) {}
}
