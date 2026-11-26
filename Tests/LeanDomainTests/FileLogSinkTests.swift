// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Testing
import LeanDomain

@Suite("FileLogSink")
struct FileLogSinkTests {
    private func makeDir() throws -> String {
        let dir = NSTemporaryDirectory() + "leanmac-log-test-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func createsPrivateFileAndAppends() throws {
        let dir = try makeDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let path = dir + "/sub/leanmac.log"
        let sink = FileLogSink(path: path)
        sink.write("one\n"); sink.write("two\n")
        #expect(try String(contentsOfFile: path, encoding: .utf8) == "one\ntwo\n")
        let attrs = try FileManager.default.attributesOfItem(atPath: path)
        #expect((attrs[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }

    @Test func refusesToFollowSymlink() throws {
        let dir = try makeDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let target = dir + "/victim.txt"
        try "keep".write(toFile: target, atomically: true, encoding: .utf8)
        let link = dir + "/leanmac.log"
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: target)
        FileLogSink(path: link).write("attack\n")
        #expect(try String(contentsOfFile: target, encoding: .utf8) == "keep")
    }

    @Test func rotatesWhenTooBig() throws {
        let dir = try makeDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let path = dir + "/leanmac.log"
        try Data(count: Int(FileLogSink.maxBytes) + 10).write(to: URL(fileURLWithPath: path))
        FileLogSink(path: path).write("fresh\n")
        #expect(FileManager.default.fileExists(atPath: path + ".1"))
        #expect(try String(contentsOfFile: path, encoding: .utf8) == "fresh\n")
    }
}
