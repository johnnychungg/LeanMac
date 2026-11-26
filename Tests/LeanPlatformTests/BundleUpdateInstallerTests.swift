// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Testing
@testable import LeanPlatform
import LeanDomain

@Suite("BundleUpdateInstaller")
struct BundleUpdateInstallerTests {
    @Test func refusesToInstallOutsideAWritableApplicationsFolder() {
        #expect(BundleUpdateInstaller(bundleURL: URL(fileURLWithPath: "/usr/bin/true")).installBlocker() != nil)
        #expect(BundleUpdateInstaller(bundleURL: URL(fileURLWithPath: "/private/var/folders/x/AppTranslocation/ABC/d/LeanMac.app")).installBlocker() != nil)
        #expect(BundleUpdateInstaller(bundleURL: URL(fileURLWithPath: "/System/Applications/LeanMac.app")).installBlocker() != nil)
    }

    @Test func relaunchScriptIsStaticAndSyntacticallyValid() throws {
        let script = BundleUpdateInstaller.scriptSource
        #expect(!script.contains("\\("))                       // no interpolation: values only arrive as arguments
        #expect(script.contains("kill -0 \"$PID\""))           // waits for the old process before swapping
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("leanmac-script-\(UUID().uuidString).sh")
        try script.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-n", url.path]
        try process.run(); process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }

    @Test func archiveWithoutAnAppIsRejected() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("leanmac-upd-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data("not a zip".utf8).write(to: dir.appendingPathComponent("a.zip"))
        Shell.runner = ProcessShellRunner()
        #expect(throws: UpdateError.self) {
            try BundleUpdateInstaller().prepare(archive: dir.appendingPathComponent("a.zip"),
                                                expectedVersion: SemanticVersion(1, 0, 0), workDirectory: dir)
        }
    }
}
