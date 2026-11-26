// SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// Runs shell commands. The real implementation (`ProcessShellRunner`) lives in `LeanPlatform`;
/// tests install a fake so no feature ever needs a real shell.
///
/// The call is synchronous on purpose: that is how the app has always used it. Never call it from the
/// main thread for anything slow.
public protocol ShellRunning: Sendable {
    func run(_ command: String) -> (output: String, exitCode: Int32)

    /// Runs one executable with an argument vector (no shell, so arguments cannot inject commands).
    /// Standard error is discarded. The process is terminated after `timeout` seconds.
    func execute(_ executable: String, arguments: [String], timeout: TimeInterval) -> (output: String, exitCode: Int32)
}

/// Injection point for `ShellRunning`.
///
/// Transitional global: every caller should eventually receive a `ShellRunning` through its initializer.
/// Until then `AppContainer` installs the real runner at launch and tests install fakes.
public enum Shell {
    private final class Box: @unchecked Sendable {
        let lock = NSLock()
        var runner: ShellRunning = UnconfiguredShellRunner()
    }
    private static let box = Box()

    public static var runner: ShellRunning {
        get { box.lock.lock(); defer { box.lock.unlock() }; return box.runner }
        set { box.lock.lock(); defer { box.lock.unlock() }; box.runner = newValue }
    }
}

/// Default runner: refuses to run anything and says so, instead of crashing or silently succeeding.
struct UnconfiguredShellRunner: ShellRunning {
    func run(_ command: String) -> (output: String, exitCode: Int32) {
        appLog("Shell runner not configured; refusing to run a command")
        return ("Error: shell runner not configured", -1)
    }

    func execute(_ executable: String, arguments: [String], timeout: TimeInterval) -> (output: String, exitCode: Int32) {
        appLog("Shell runner not configured; refusing to run an executable")
        return ("", -1)
    }
}

/// Runs a shell command through the installed runner.
@discardableResult
public func shell(_ command: String) -> (output: String, exitCode: Int32) {
    Shell.runner.run(command)
}
