// SPDX-License-Identifier: GPL-3.0-only
import Foundation

public enum MemoryPressure: Int, Sendable { case normal = 1, warning = 2, critical = 4
    /// Value of macOS's `kern.memorystatus_vm_pressure_level`.
    public init(sysctlLevel: Int) {
        switch sysctlLevel { case 4...: self = .critical; case 2...: self = .warning; default: self = .normal }
    }
}

/// Same formula as Activity Monitor: Used = App (internal − purgeable) + Wired + Compressed.
public struct MemoryStats: Equatable, Sendable {
    public let appBytes: UInt64
    public let wiredBytes: UInt64
    public let compressedBytes: UInt64
    public let totalBytes: UInt64

    public init(internalPages: UInt64, purgeablePages: UInt64, wiredPages: UInt64, compressedPages: UInt64,
                pageSize: UInt64, totalBytes: UInt64) {
        let app = internalPages >= purgeablePages ? internalPages - purgeablePages : 0
        self.appBytes = app &* pageSize
        self.wiredBytes = wiredPages &* pageSize
        self.compressedBytes = compressedPages &* pageSize
        self.totalBytes = totalBytes
    }

    public var usedBytes: UInt64 { appBytes &+ wiredBytes &+ compressedBytes }
    public var usedPercent: Double {
        guard totalBytes > 0 else { return 0 }
        return min(max(Double(usedBytes) / Double(totalBytes) * 100, 0), 100)
    }
    public static func gb(_ bytes: UInt64) -> Double { Double(bytes) / 1_073_741_824 }
    public var summary: String { String(format: "%.1f / %.0f GB", Self.gb(usedBytes), Self.gb(totalBytes)) }
}

// MARK: - Network speed

public enum NetRate {
    /// Difference of two reads of the 32-bit `if_data` counter (safe when the counter wraps).
    public static func delta(prev: UInt32, cur: UInt32) -> UInt64 { UInt64(cur &- prev) }

    /// "0 B/s", "850 KB/s", "1.2 MB/s"
    public static func format(_ bytesPerSecond: Double, compact: Bool = false) -> String {
        let b = max(0, bytesPerSecond)
        let unitSpace = compact ? "" : " "
        if b >= 1_048_576 * 1024 { return String(format: "%.1f%@GB/s", b / (1_048_576 * 1024), unitSpace) }
        if b >= 1_048_576 { return String(format: "%.1f%@MB/s", b / 1_048_576, unitSpace) }
        if b >= 1024 { return String(format: "%.0f%@KB/s", b / 1024, unitSpace) }
        return String(format: "%.0f%@B/s", b, unitSpace)
    }
}
