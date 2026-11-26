// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import LeanDomain

/// Apple's own firmware charge ceiling ("PowerUI", macOS 15+ and recent firmware), reached through the
/// private `PowerUI.framework`. Everything is optional: if the framework or a selector is missing the
/// client simply reports `isSupported == false`.
@MainActor
public final class PowerUICeilingClient: ChargeCeilingControlling {
    private var clientInstance: NSObject?
    public private(set) var isSupported: Bool = false

    public init() {
        guard let bundle = Bundle(path: "/System/Library/PrivateFrameworks/PowerUI.framework"), bundle.load() else {
            return
        }
        guard let cls = NSClassFromString("PowerUISmartChargeClient") as? NSObject.Type else {
            return
        }
        let selInit = NSSelectorFromString("initWithClientName:")
        guard cls.instancesRespond(to: selInit) else { return }

        // alloc + initWithClientName: without a double init.
        let selAlloc = NSSelectorFromString("alloc")
        guard cls.responds(to: selAlloc) else { return }
        typealias AllocFn = @convention(c) (AnyClass, Selector) -> AnyObject
        let allocFn = unsafeBitCast(cls.method(for: selAlloc), to: AllocFn.self)
        let uninit = allocFn(cls, selAlloc)

        typealias InitFn = @convention(c) (AnyObject, Selector, NSString) -> AnyObject
        let initFn = unsafeBitCast(cls.instanceMethod(for: selInit), to: InitFn.self)
        let client = initFn(uninit, selInit, "LeanMac" as NSString) as? NSObject
        self.clientInstance = client

        let selSupported = NSSelectorFromString("isMCLSupported")
        if let client = client, client.responds(to: selSupported) {
            typealias BoolFn = @convention(c) (AnyObject, Selector) -> Bool
            let fn = unsafeBitCast(client.method(for: selSupported), to: BoolFn.self)
            self.isSupported = fn(client, selSupported)
        }
    }

    public func setLimit(_ limit: Int) -> Bool {
        guard isSupported, let client = clientInstance else { return false }
        // PowerUI only supports 80, 85, 90, 95, 100 and rejects anything below 80 with error code 4.
        guard limit >= 80 else { return false }

        let selSet = NSSelectorFromString("setMCLLimit:error:")
        guard client.responds(to: selSet) else { return false }
        typealias SetFn = @convention(c) (AnyObject, Selector, UInt8, UnsafeMutableRawPointer?) -> Bool
        // NULL error pointer avoids any ARC double-free on the error object.
        let targetLimit = UInt8(min(max(limit, 80), 100))
        let ok = unsafeBitCast(client.method(for: selSet), to: SetFn.self)(client, selSet, targetLimit, nil)

        if ok {
            appLog("PowerUI: setMCLLimit(\(targetLimit)) succeeded")
        } else {
            appLog("PowerUI: setMCLLimit(\(targetLimit)) rejected by the system")
        }
        return ok
    }

    public func disable() -> Bool {
        guard isSupported, let client = clientInstance else { return false }
        let selDisable = NSSelectorFromString("disableMCL:")
        guard client.responds(to: selDisable) else { return false }
        typealias DisableFn = @convention(c) (AnyObject, Selector, UnsafeMutableRawPointer?) -> Bool
        let ok = unsafeBitCast(client.method(for: selDisable), to: DisableFn.self)(client, selDisable, nil)
        appLog(ok ? "PowerUI: disableMCL succeeded (charging restored)" : "PowerUI: disableMCL failed")
        return ok
    }

    public func isCurrentlyEnabled() -> Bool {
        guard isSupported, let client = clientInstance else { return false }
        let selEnabled = NSSelectorFromString("isMCLCurrentlyEnabled:")
        guard client.responds(to: selEnabled) else { return false }
        typealias BoolErrFn = @convention(c) (AnyObject, Selector, UnsafeMutableRawPointer?) -> UInt64
        return unsafeBitCast(client.method(for: selEnabled), to: BoolErrFn.self)(client, selEnabled, nil) != 0
    }

    public func currentLimit() -> Int {
        guard isSupported, let client = clientInstance else { return 100 }
        let selGet = NSSelectorFromString("getMCLLimitWithError:")
        guard client.responds(to: selGet) else { return 100 }
        typealias UcharErrFn = @convention(c) (AnyObject, Selector, UnsafeMutableRawPointer?) -> UInt8
        return Int(unsafeBitCast(client.method(for: selGet), to: UcharErrFn.self)(client, selGet, nil))
    }
}
