// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import IOKit
import LeanDomain

/// Reads the `AppleSmartBattery` registry entry.
public struct IOKitBatteryReader: BatteryReading {
    public init() {}

    public func read() -> BatteryReadResult {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        // Desktop Macs (Mac mini, Mac Studio, iMac, Mac Pro) have no internal battery.
        guard service != 0 else { return .noBattery }
        defer { IOObjectRelease(service) }

        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == kIOReturnSuccess,
              let dict = props?.takeRetainedValue() as? [String: Any] else {
            return .unavailable
        }

        var s = BatterySnapshot()
        s.currentCapacity = dict["CurrentCapacity"] as? Int
        s.maxCapacity = dict["MaxCapacity"] as? Int
        s.nominalChargeCapacity = dict["NominalChargeCapacity"] as? Int
        s.designCapacity = dict["DesignCapacity"] as? Int
        s.cycleCount = dict["CycleCount"] as? Int
        s.isCharging = dict["IsCharging"] as? Bool ?? false
        s.isExternalConnected = dict["ExternalConnected"] as? Bool ?? false
        s.isFullyCharged = dict["FullyCharged"] as? Bool ?? false
        s.timeRemaining = dict["TimeRemaining"] as? Int ?? 0

        // Newer macOS no longer reports "Temperature" here: ThermalManager supplies it from SMC/HID then.
        if let raw = dict["Temperature"] as? Double {
            s.temperatureCelsius = raw / 100.0
        } else if let raw = dict["Temperature"] as? Int {
            s.temperatureCelsius = Double(raw) / 100.0
        }
        if let raw = dict["Voltage"] as? Double {
            s.voltage = raw / 1000.0
        } else if let raw = dict["Voltage"] as? Int {
            s.voltage = Double(raw) / 1000.0
        }
        // Signed 64-bit: negative = discharging, positive = charging, 0 = bypass.
        // IOKit may hand back a negative value as an unsigned 64-bit number, so go through NSNumber
        // (int64Value reinterprets the bit pattern) instead of a Swift cast that would fail.
        if let raw = (dict["Amperage"] as? NSNumber)?.int64Value {
            s.amperageMilliamps = Int(raw)
        }

        if let adapter = dict["AdapterDetails"] as? [String: Any], let w = adapter["Watts"] as? Int, w > 0 {
            s.adapterWatts = w
            s.adapterDescription = adapter["Description"] as? String ?? "USB-C PD"
            s.adapterSerial = adapter["SerialString"] as? String ?? ""
        } else if let list = dict["AppleRawAdapterDetails"] as? [[String: Any]],
                  let first = list.first, let w = first["Watts"] as? Int, w > 0 {
            s.adapterWatts = w
            s.adapterDescription = first["Description"] as? String ?? "USB-C PD"
            s.adapterSerial = first["SerialString"] as? String ?? ""
        }

        s.serial = dict["Serial"] as? String
        s.deviceName = dict["DeviceName"] as? String
        return .snapshot(s)
    }
}
