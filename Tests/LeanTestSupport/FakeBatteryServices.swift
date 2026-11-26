// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import LeanDomain

/// Fakes for every battery port, so tests need no battery, no SMC and no privileged helper.

public final class FakeBatteryReader: BatteryReading, @unchecked Sendable {
    private let lock = NSLock()
    private var _result: BatteryReadResult
    public init(_ result: BatteryReadResult = .unavailable) { _result = result }
    public var result: BatteryReadResult {
        get { lock.lock(); defer { lock.unlock() }; return _result }
        set { lock.lock(); defer { lock.unlock() }; _result = newValue }
    }
    public func read() -> BatteryReadResult { result }
}

public final class FakeSMC: SMCReading, @unchecked Sendable {
    private let lock = NSLock()
    private var keys: [String: [UInt8]]
    public init(_ keys: [String: [UInt8]] = [:]) { self.keys = keys }
    public func set(_ key: String, _ bytes: [UInt8]) { lock.lock(); keys[key] = bytes; lock.unlock() }
    public func readKeyBytes(_ key: String) -> [UInt8]? { lock.lock(); defer { lock.unlock() }; return keys[key] }
}

public final class FakeHelperGateway: HelperGateway, @unchecked Sendable {
    private let lock = NSLock()
    private var _commands: [HelperCommand] = []
    public let isBinaryPresent: Bool
    public var reply: @Sendable (HelperCommand) -> (output: String, exitCode: Int32)

    public init(isBinaryPresent: Bool = true,
                reply: @escaping @Sendable (HelperCommand) -> (output: String, exitCode: Int32) = { command in
                    command == .version ? ("HELPER_VERSION:\(PrivilegedHelper.requiredVersion)", 0) : ("OK", 0)
                }) {
        self.isBinaryPresent = isBinaryPresent
        self.reply = reply
    }

    public var commands: [HelperCommand] { lock.lock(); defer { lock.unlock() }; return _commands }

    public func run(_ command: HelperCommand) -> (output: String, exitCode: Int32) {
        lock.lock(); _commands.append(command); lock.unlock()
        return reply(command)
    }
}

public struct FakeHelperInstaller: HelperInstalling {
    public let version: Int
    public init(version: Int = PrivilegedHelper.requiredVersion) { self.version = version }
    public func install(using gateway: HelperGateway) -> Int { version }
}

public final class FakeBluetooth: BluetoothControlling, @unchecked Sendable {
    public var isAvailable = true
    public var isPowerOn = true
    public init() {}
}

@MainActor
public final class FakeChargeCeiling: ChargeCeilingControlling {
    public var isSupported = false
    public private(set) var limits: [Int] = []
    private var enabled = false
    private var limit = 100
    public init() {}
    public func setLimit(_ limit: Int) -> Bool { guard isSupported else { return false }; limits.append(limit); self.limit = limit; enabled = true; return true }
    public func disable() -> Bool { enabled = false; limit = 100; return true }
    public func isCurrentlyEnabled() -> Bool { enabled }
    public func currentLimit() -> Int { limit }
}

public final class FakePowerSourceObserver: PowerSourceObserving {
    public private(set) var onChange: (@MainActor () -> Void)?
    public init() {}
    public func start(onChange: @escaping @MainActor () -> Void) { self.onChange = onChange }
}

extension BatteryServices {
    /// A complete set of fakes. Keep a reference to the ones you want to inspect.
    public static func fake(reader: BatteryReading = FakeBatteryReader(),
                            smc: SMCReading = FakeSMC(),
                            helper: HelperGateway = FakeHelperGateway(),
                            installer: HelperInstalling = FakeHelperInstaller(),
                            bluetooth: BluetoothControlling = FakeBluetooth(),
                            ceiling: @escaping @MainActor @Sendable () -> ChargeCeilingControlling = { FakeChargeCeiling() },
                            observer: PowerSourceObserving = FakePowerSourceObserver()) -> BatteryServices {
        let holder = UncheckedBox((bluetooth, observer))
        return BatteryServices(reader: reader, smc: smc, helper: helper, installer: installer,
                               bluetoothFactory: { holder.value.0 }, ceilingFactory: ceiling,
                               powerSourceObserverFactory: { holder.value.1 })
    }
}

/// Lets a test hand a non-Sendable fake to a `@Sendable` factory closure.
final class UncheckedBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}
