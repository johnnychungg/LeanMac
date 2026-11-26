// SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// Builds the one-line root command that installs the privileged helper.
///
/// Root never reads a file a normal user could modify: the three payload files are read into memory by
/// the app and travel INSIDE the command (base64). Root unpacks them into a fresh directory created
/// with an explicit template under `/private/tmp` (sticky, so a user cannot rename a root-owned entry;
/// the environment's temp dir is never trusted), `cd`s into it and runs the installer with relative paths, so even a
/// rename cannot redirect root. There is no user-owned staging folder, so there is nothing to swap.
public enum HelperInstallCommand {
    /// Refuse absurd payloads (the real ones are ~65 KB) so the command stays far below ARG_MAX.
    public static let maxPayloadBytes = 512 * 1024

    /// Same rule as `install-helper.sh`: letters, digits, `.`, `_`, `-`; no leading `-`; not `.`, `..`, `ALL`, `root`.
    public static func isSafeUserName(_ user: String) -> Bool {
        user.range(of: #"^[A-Za-z0-9._-]+$"#, options: .regularExpression) != nil
            && !user.hasPrefix("-") && user != "." && user != ".." && user != "ALL" && user != "root"
    }

    /// The shell command run as root, or nil when the user name is unsafe or the payload is too big.
    public static func shellCommand(user: String, installScript: Data, smc: Data, power: Data) -> String? {
        guard isSafeUserName(user),
              installScript.count + smc.count + power.count <= maxPayloadBytes else { return nil }

        func unpack(_ data: Data, as name: String) -> String {
            "printf %s '\(data.base64EncodedString())' | /usr/bin/base64 -D > \"./\(name)\""
        }
        let steps = [
            "T=$(/usr/bin/mktemp -d /private/tmp/leanmac.XXXXXX)",
            "cd \"$T\"",
            unpack(installScript, as: "install-helper.sh"),
            unpack(smc, as: "smc"),
            unpack(power, as: "leanmac-power"),
            "/bin/bash ./install-helper.sh ./smc ./leanmac-power '\(user)'"
        ]
        return steps.joined(separator: " && ") + "; rc=$?; cd /; /bin/rm -rf \"$T\"; exit $rc"
    }

    /// AppleScript source that runs `shellCommand` with the standard administrator-password prompt.
    public static func appleScript(for shellCommand: String) -> String {
        let escaped = shellCommand
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "do shell script \"\(escaped)\" with administrator privileges"
    }
}
