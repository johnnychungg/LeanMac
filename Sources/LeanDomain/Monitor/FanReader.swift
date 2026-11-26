// SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// One fan as the SMC reports it. LeanMac only reads fans; it never controls them.
public struct FanInfo: Equatable, Sendable {
    public let index: Int
    public let rpm: Int
    public let minRPM: Int
    public let maxRPM: Int

    public init(index: Int, rpm: Int, minRPM: Int, maxRPM: Int) {
        self.index = index; self.rpm = rpm; self.minRPM = minRPM; self.maxRPM = maxRPM
    }
}

public enum FanReader {
    /// Most Macs have at most two fans; the cap also bounds the number of SMC reads.
    public static let maxFans = 4

    /// Reads `FNum` and `F<n>Ac/Mn/Mx`. Returns an empty list for fanless Macs (MacBook Air) or when the keys are missing.
    public static func read(from smc: SMCReading) -> [FanInfo] {
        guard let count = smc.readKeyBytes("FNum")?.first, count > 0 else { return [] }
        return (0..<min(Int(count), maxFans)).compactMap { i in
            guard let actual = smc.readKeyBytes("F\(i)Ac").flatMap(decode) else { return nil }
            let minimum = smc.readKeyBytes("F\(i)Mn").flatMap(decode) ?? 0
            let maximum = smc.readKeyBytes("F\(i)Mx").flatMap(decode) ?? 0
            return FanInfo(index: i, rpm: actual, minRPM: minimum, maxRPM: maximum)
        }
    }

    /// Apple Silicon reports a 4-byte little-endian float (`flt `); older Intel Macs a 2-byte fixed point (`fpe2`).
    public static func decode(_ bytes: [UInt8]) -> Int? {
        switch bytes.count {
        case 4:
            let bits = UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
            let value = Float(bitPattern: bits)
            guard value.isFinite, value >= 0, value < 100_000 else { return nil }
            return Int(value.rounded())
        case 2:
            return Int((UInt16(bytes[0]) << 8 | UInt16(bytes[1])) >> 2)
        default:
            return nil
        }
    }
}
