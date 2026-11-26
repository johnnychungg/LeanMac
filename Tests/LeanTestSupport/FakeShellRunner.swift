// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import LeanDomain

/// Records commands and answers from a script, so tests never spawn a real process.
public final class FakeShellRunner: ShellRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var _commands: [String] = []
    private let responder: @Sendable (String) -> (output: String, exitCode: Int32)

    public init(responder: @escaping @Sendable (String) -> (output: String, exitCode: Int32) = { _ in ("", 0) }) {
        self.responder = responder
    }

    public var commands: [String] {
        lock.lock(); defer { lock.unlock() }
        return _commands
    }

    public func run(_ command: String) -> (output: String, exitCode: Int32) {
        lock.lock(); _commands.append(command); lock.unlock()
        return responder(command)
    }

    public func execute(_ executable: String, arguments: [String], timeout: TimeInterval) -> (output: String, exitCode: Int32) {
        let line = ([executable] + arguments).joined(separator: " ")
        lock.lock(); _commands.append(line); lock.unlock()
        return responder(line)
    }
}
