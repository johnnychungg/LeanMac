// SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// Where the privileged charge helper is installed and which version the app expects.
///
/// `/Library/PrivilegedHelperTools` is always `root:wheel` (755), so a normal user cannot replace the
/// helper. These constants are locked by tests: changing a path or the version silently would break
/// every existing install (the version forces a re-install prompt).
public enum PrivilegedHelper {
    public static let powerPath = "/Library/PrivilegedHelperTools/com.local.leanmac.power"
    public static let smcPath = "/Library/PrivilegedHelperTools/com.local.leanmac.smc"
    public static let sudoersPath = "/etc/sudoers.d/leanmac_power"

    /// Helper version, matched exactly: a different installed number makes the app ask for a re-install.
    /// 1 = charge-on/off + watchdog, discharge-on/off (CHIE) for calibration, argument validation.
    public static let requiredVersion = 1

    /// The ONLY place a `sudo` command line is assembled. It is built from a typed `HelperCommand`
    /// (verbs plus a validated `ChargeLimit`), never from free-form text, so no caller can inject
    /// shell syntax. The helper validates every argument again on the root side.
    public static func sudoCommand(_ command: HelperCommand) -> String {
        "sudo -n \(powerPath) \(command.arguments)"
    }

    /// Extracts the version from `HELPER_VERSION:<n>` output; 0 when the helper did not answer properly.
    public static func parseVersion(output: String, exitCode: Int32) -> Int {
        guard exitCode == 0, let range = output.range(of: "HELPER_VERSION:") else { return 0 }
        let digits = output[range.upperBound...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(while: { $0.isNumber })
        return Int(digits) ?? 0
    }
}

/// A charge limit in percent. The helper accepts exactly 20...100; anything else cannot be constructed.
public struct ChargeLimit: Equatable, Sendable {
    public static let range = 20...100
    public let value: Int

    public init?(_ value: Int) {
        guard Self.range.contains(value) else { return nil }
        self.value = value
    }

    /// Clamps instead of failing, for values that come from the user's own settings.
    public init(clamping value: Int) {
        self.value = min(max(value, Self.range.lowerBound), Self.range.upperBound)
    }
}

/// Everything the app may ask the privileged helper to do.
public enum HelperCommand: Equatable, Sendable {
    case version
    case status
    case chargeOff(ChargeLimit)
    case chargeOn(ChargeLimit)
    case dischargeOn
    case dischargeOff

    public var arguments: String {
        switch self {
        case .version: return "version"
        case .status: return "status"
        case .chargeOff(let limit): return "charge-off \(limit.value)"
        case .chargeOn(let limit): return "charge-on \(limit.value)"
        case .dischargeOn: return "discharge-on"
        case .dischargeOff: return "discharge-off"
        }
    }

    /// True for commands that change hardware state (SMC writes).
    public var writesHardware: Bool {
        switch self {
        case .version, .status: return false
        case .chargeOff, .chargeOn, .dischargeOn, .dischargeOff: return true
        }
    }
}
