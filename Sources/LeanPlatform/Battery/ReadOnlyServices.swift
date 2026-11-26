// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import LeanDomain

// Contributor mode (`LEANMAC_DEV=1`): the app reads the hardware but never writes to it. No helper is
// needed, no SMC key is touched, Bluetooth is left alone and the system charge ceiling is not changed.

/// Pretends the helper is not installed and records what it was asked to do.
public final class ReadOnlyHelperGateway: HelperGateway, @unchecked Sendable {
    public init() {}
    public var isBinaryPresent: Bool { false }

    public func run(_ command: HelperCommand) -> (output: String, exitCode: Int32) {
        appLog("[dev mode] skipped helper command: \(command.arguments)")
        return ("read-only mode", 1)
    }
}

public struct ReadOnlyHelperInstaller: HelperInstalling {
    public init() {}
    public func install(using gateway: HelperGateway) -> Int {
        appLog("[dev mode] helper installation is disabled")
        return 0
    }
}

@MainActor
public final class ReadOnlyChargeCeiling: ChargeCeilingControlling {
    public init() {}
    public var isSupported: Bool { false }
    public func setLimit(_ limit: Int) -> Bool { false }
    public func disable() -> Bool { false }
    public func isCurrentlyEnabled() -> Bool { false }
    public func currentLimit() -> Int { 100 }
}

public final class ReadOnlyBluetooth: BluetoothControlling {
    public init() {}
    public var isAvailable: Bool { false }
    public var isPowerOn: Bool {
        get { true }
        set { appLog("[dev mode] skipped Bluetooth power change") }
    }
}
