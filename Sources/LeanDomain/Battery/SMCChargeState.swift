// SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// Decodes the SMC keys that Apple Silicon and Intel Macs use to hold back charging.
public enum SMCChargeState {
    /// `true` when any known charge-inhibit key is currently engaged, `false` when keys exist but none
    /// is engaged, `nil` when this Mac exposes none of them.
    ///
    /// - `CHTE` 1: charging inhibited (Apple Silicon, newer firmware)
    /// - `CH0B` 2: charging inhibited (M1)
    /// - `bfF0` 1 or 2: firmware limit active
    /// - `BCLM` 1…99: Intel charge limit below 100
    public static func isBypassed(_ smc: SMCReading) -> Bool? {
        var found = false
        var bypassed = false
        if let bytes = smc.readKeyBytes("CHTE"), !bytes.isEmpty {
            found = true
            if bytes[0] == 1 { bypassed = true }
        }
        if let bytes = smc.readKeyBytes("CH0B"), !bytes.isEmpty {
            found = true
            if bytes[0] == 2 { bypassed = true }
        }
        if let bytes = smc.readKeyBytes("bfF0"), !bytes.isEmpty {
            found = true
            if bytes[0] == 1 || bytes[0] == 2 { bypassed = true }
        }
        if let bytes = smc.readKeyBytes("BCLM"), !bytes.isEmpty {
            found = true
            if bytes[0] > 0 && bytes[0] < 100 { bypassed = true }
        }
        return found ? bypassed : nil
    }
}
