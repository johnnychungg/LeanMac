// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import IOKit.ps
import LeanDomain

/// Wakes the app instantly when the power source changes, so it needs no polling while on battery.
/// Keep the observer alive for as long as notifications are wanted.
public final class IOPSObserver: PowerSourceObserving {
    private var source: CFRunLoopSource?
    private var handler: (@MainActor () -> Void)?

    public init() {}

    deinit {
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
    }

    public func start(onChange: @escaping @MainActor () -> Void) {
        guard source == nil else { return }
        handler = onChange
        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOPowerSourceCallbackType = { context in
            guard let context else { return }
            let observer = Unmanaged<IOPSObserver>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in observer.handler?() }
        }
        if let created = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() {
            source = created
            CFRunLoopAddSource(CFRunLoopGetMain(), created, .commonModes)
        }
    }
}
