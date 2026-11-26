// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import LeanDomain

/// Talks to the installed privileged helper through `sudo -n` (the sudoers rule installed with the helper
/// allows exactly this one file for exactly one user, with no password).
public struct SudoHelperGateway: HelperGateway {
    private let shell: ShellRunning

    public init(shell: ShellRunning) {
        self.shell = shell
    }

    public var isBinaryPresent: Bool {
        FileManager.default.fileExists(atPath: PrivilegedHelper.powerPath)
    }

    public func run(_ command: HelperCommand) -> (output: String, exitCode: Int32) {
        shell.run(PrivilegedHelper.sudoCommand(command))
    }
}
