// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import LeanDomain

/// Real shell runner built on `Process`. Uses `/bin/sh` (it does not load zshenv) and reads the whole
/// pipe BEFORE waiting for exit so large output cannot deadlock the child.
public struct ProcessShellRunner: ShellRunning {
    public init() {}

    public func run(_ command: String) -> (output: String, exitCode: Int32) {
        let process = Process()
        let pipe = Pipe()

        process.standardOutput = pipe
        process.standardError = pipe
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return ("Error: \(error.localizedDescription)", -1)
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(data: data, encoding: .utf8) ?? ""
        return (output.trimmingCharacters(in: .whitespacesAndNewlines), process.terminationStatus)
    }

    public func execute(_ executable: String, arguments: [String], timeout: TimeInterval) -> (output: String, exitCode: Int32) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return ("", -1) }
        let killer = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        killer.cancel()
        return (String(decoding: data, as: UTF8.self), process.terminationStatus)
    }
}
