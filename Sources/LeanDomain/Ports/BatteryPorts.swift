// SPDX-License-Identifier: GPL-3.0-only
import Foundation

// MARK: - Battery readings

/// One reading of the battery as reported by the system. Raw units are already converted
/// (volts, degrees Celsius, milliamps); fields the system did not report are `nil`.
public struct BatterySnapshot: Equatable, Sendable {
    public var currentCapacity: Int?
    public var maxCapacity: Int?
    public var nominalChargeCapacity: Int?
    public var designCapacity: Int?
    public var cycleCount: Int?
    public var isCharging = false
    public var isExternalConnected = false
    public var isFullyCharged = false
    public var timeRemaining = 0
    public var temperatureCelsius: Double?
    public var voltage: Double?
    public var amperageMilliamps: Int?
    public var adapterWatts: Int?
    public var adapterDescription: String?
    public var adapterSerial: String?
    public var serial: String?
    public var deviceName: String?

    public init() {}
}

public enum BatteryReadResult: Equatable, Sendable {
    /// Desktop Mac: there is no internal battery.
    case noBattery
    /// The system did not answer; keep the previous values.
    case unavailable
    case snapshot(BatterySnapshot)
}

public protocol BatteryReading: Sendable {
    func read() -> BatteryReadResult
}

/// Raw System Management Controller keys, read in-process (no child process, no root).
public protocol SMCReading: Sendable {
    func readKeyBytes(_ key: String) -> [UInt8]?
}

/// Calls the callback whenever the power source changes (plug, unplug, percentage).
public protocol PowerSourceObserving: AnyObject {
    func start(onChange: @escaping @MainActor () -> Void)
}

// MARK: - Hardware control

public protocol BluetoothControlling: AnyObject {
    var isAvailable: Bool { get }
    var isPowerOn: Bool { get set }
}

/// macOS's own firmware charge ceiling (PowerUI). Only 80, 85, 90, 95 and 100 are accepted by the system.
@MainActor
public protocol ChargeCeilingControlling: AnyObject {
    var isSupported: Bool { get }
    func setLimit(_ limit: Int) -> Bool
    func disable() -> Bool
    func isCurrentlyEnabled() -> Bool
    func currentLimit() -> Int
}

/// Runs a command in the privileged charge helper.
public protocol HelperGateway: Sendable {
    /// True when the helper file exists (it may still have the wrong version).
    var isBinaryPresent: Bool { get }
    func run(_ command: HelperCommand) -> (output: String, exitCode: Int32)
}

/// Installs the privileged helper (asks the user for an administrator password).
public protocol HelperInstalling: Sendable {
    /// Blocking: call it from a background queue. Returns the helper version that answers afterwards (0 = failed).
    func install(using gateway: HelperGateway) -> Int
}

// MARK: - Bundle

/// Everything `BatteryManager` needs from the machine. `AppContainer` installs the real adapters
/// (or read-only ones in contributor mode); tests install fakes.
public struct BatteryServices: Sendable {
    public var reader: BatteryReading
    public var smc: SMCReading
    public var helper: HelperGateway
    public var installer: HelperInstalling
    public var bluetoothFactory: @Sendable () -> BluetoothControlling
    public var ceilingFactory: @MainActor @Sendable () -> ChargeCeilingControlling
    public var powerSourceObserverFactory: @Sendable () -> PowerSourceObserving

    public init(reader: BatteryReading, smc: SMCReading, helper: HelperGateway, installer: HelperInstalling,
                bluetoothFactory: @escaping @Sendable () -> BluetoothControlling,
                ceilingFactory: @escaping @MainActor @Sendable () -> ChargeCeilingControlling,
                powerSourceObserverFactory: @escaping @Sendable () -> PowerSourceObserving) {
        self.reader = reader
        self.smc = smc
        self.helper = helper
        self.installer = installer
        self.bluetoothFactory = bluetoothFactory
        self.ceilingFactory = ceilingFactory
        self.powerSourceObserverFactory = powerSourceObserverFactory
    }

    private final class Box: @unchecked Sendable {
        let lock = NSLock()
        var services: BatteryServices?
    }
    private static let box = Box()

    /// Installed once at launch by `AppContainer`. Reading it earlier (a SwiftUI preview, a test that forgot
    /// to install fakes) yields inert services that touch nothing, and logs it, instead of crashing.
    public static var current: BatteryServices {
        get {
            box.lock.lock(); defer { box.lock.unlock() }
            if let services = box.services { return services }
            appLog("BatteryServices.current read before it was installed; using inert services")
            return .inert
        }
        set { box.lock.lock(); defer { box.lock.unlock() }; box.services = newValue }
    }
}

// MARK: - Inert services

extension BatteryServices {
    /// Services that read nothing and write nothing.
    public static var inert: BatteryServices {
        BatteryServices(reader: InertBatteryReader(), smc: InertSMC(), helper: InertHelperGateway(),
                        installer: InertHelperInstaller(),
                        bluetoothFactory: { InertBluetooth() },
                        ceilingFactory: { InertChargeCeiling() },
                        powerSourceObserverFactory: { InertPowerSourceObserver() })
    }
}

struct InertBatteryReader: BatteryReading { func read() -> BatteryReadResult { .unavailable } }
struct InertSMC: SMCReading { func readKeyBytes(_ key: String) -> [UInt8]? { nil } }
struct InertHelperGateway: HelperGateway {
    var isBinaryPresent: Bool { false }
    func run(_ command: HelperCommand) -> (output: String, exitCode: Int32) { ("inert", 1) }
}
struct InertHelperInstaller: HelperInstalling { func install(using gateway: HelperGateway) -> Int { 0 } }
final class InertBluetooth: BluetoothControlling {
    var isAvailable: Bool { false }
    var isPowerOn: Bool { get { true } set {} }
}
@MainActor final class InertChargeCeiling: ChargeCeilingControlling {
    var isSupported: Bool { false }
    func setLimit(_ limit: Int) -> Bool { false }
    func disable() -> Bool { false }
    func isCurrentlyEnabled() -> Bool { false }
    func currentLimit() -> Int { 100 }
}
final class InertPowerSourceObserver: PowerSourceObserving { func start(onChange: @escaping @MainActor () -> Void) {} }
