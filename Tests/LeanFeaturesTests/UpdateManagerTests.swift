// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import CryptoKit
import Testing
@testable import LeanFeatures
import LeanDomain

@Suite("UpdateManager")
@MainActor
struct UpdateManagerTests {
    private final class FakeFetcher: UpdateFetching, @unchecked Sendable {
        var manifest = Data(), signature = Data(), archive = Data("zip-bytes".utf8)
        var fetchCount = 0
        func fetchData(_ url: URL, maxBytes: Int) async throws -> Data {
            fetchCount += 1
            return url.lastPathComponent == "update.json.sig" ? signature : manifest
        }
        func download(_ url: URL, into directory: URL, maxBytes: Int) async throws -> URL {
            let file = directory.appendingPathComponent("a.zip")
            try archive.write(to: file)
            return file
        }
    }
    private final class FakeInstaller: UpdateInstalling, @unchecked Sendable {
        var blocker: String?
        var prepareError: UpdateError?
        var prepared = false, launched = false, preparedOnMainThread = true
        func installBlocker() -> String? { blocker }
        func prepare(archive: URL, expectedVersion: SemanticVersion, workDirectory: URL) throws -> URL {
            if let prepareError { throw prepareError }
            prepared = true
            preparedOnMainThread = Thread.isMainThread
            return workDirectory
        }
        func installAndRelaunch(newApp: URL, workDirectory: URL) throws { launched = true }
    }

    private struct Rig {
        let manager: UpdateManager
        let fetcher: FakeFetcher
        let installer: FakeInstaller
        let defaults: UserDefaults
    }

    private func rig(version: String = "1.2.0", archive: String = "zip-bytes", enabled: Bool = true) -> Rig {
        let key = Curve25519.Signing.PrivateKey()
        let fetcher = FakeFetcher()
        let sha = UpdateVerifier.sha256Hex(Data(archive.utf8))
        let json = """
        {"version":"\(version)","build":2,"minimumSystemVersion":"14.0",
         "url":"https://github.com/johnnychungg/LeanMac/releases/download/v\(version)/LeanMac-\(version).zip","sha256":"\(sha)"}
        """
        fetcher.manifest = Data(json.utf8)
        fetcher.signature = Data(try! key.signature(for: fetcher.manifest).base64EncodedString().utf8)
        let installer = FakeInstaller()
        let defaults = UserDefaults(suiteName: "LeanMac.UpdateTests." + UUID().uuidString)!
        let services = UpdateServices(fetcher: fetcher, installer: installer, currentVersion: SemanticVersion(1, 0, 0), isEnabled: enabled)
        let manager = UpdateManager(defaults: defaults, services: { services },
                                    publicKey: key.publicKey.rawRepresentation.base64EncodedString(),
                                    systemVersion: OperatingSystemVersion(majorVersion: 14, minorVersion: 5, patchVersion: 0),
                                    quit: {},
                                    workRoot: FileManager.default.temporaryDirectory.appendingPathComponent("leanmac-upd-\(UUID().uuidString)"))
        return Rig(manager: manager, fetcher: fetcher, installer: installer, defaults: defaults)
    }

    private func wait(_ manager: UpdateManager, until condition: (UpdateManager.State) -> Bool) async {
        for _ in 0..<200 where !condition(manager.state) { try? await Task.sleep(nanoseconds: 10_000_000) }
    }

    @Test func checkFindsNewerVersion() async {
        let r = rig()
        r.manager.checkNow()
        await wait(r.manager) { if case .available = $0 { return true } else { return false } }
        guard case .available(let m) = r.manager.state else { Issue.record("not available: \(r.manager.state)"); return }
        #expect(m.version == "1.2.0")
    }

    @Test func sameVersionIsUpToDate() async {
        let r = rig(version: "1.0.0")
        r.manager.checkNow()
        await wait(r.manager) { $0 == .upToDate }
        #expect(r.manager.state == .upToDate)
    }

    @Test func badSignatureReportsFailureOnlyWhenUserAsked() async {
        let r = rig()
        r.fetcher.signature = Data("AAAA".utf8)
        r.manager.checkNow()
        await wait(r.manager) { if case .failed = $0 { return true } else { return false } }
        guard case .failed = r.manager.state else { Issue.record("expected failure"); return }
        // A background check stays silent.
        let quiet = rig()
        quiet.fetcher.signature = Data("AAAA".utf8)
        quiet.manager.checkIfDue()
        await wait(quiet.manager) { $0 == .idle }
        #expect(quiet.manager.state == .idle)
    }

    @Test func backgroundChecksAreThrottledToOncePerDay() async {
        let r = rig(version: "1.0.0")
        r.manager.checkIfDue()
        await wait(r.manager) { $0 == .upToDate }
        let first = r.fetcher.fetchCount
        r.manager.checkIfDue()
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(r.fetcher.fetchCount == first)
        r.manager.checkIfDue(now: Date().addingTimeInterval(UpdateConfig.checkIntervalSeconds + 1))
        await wait(r.manager) { $0 == .upToDate }
        #expect(r.fetcher.fetchCount > first)
    }

    @Test func disabledOrAutoOffNeverChecks() async {
        let off = rig(enabled: false)
        off.manager.checkNow(); off.manager.checkIfDue()
        #expect(off.fetcher.fetchCount == 0)
        let manual = rig()
        manual.manager.autoCheckEnabled = false
        manual.manager.checkIfDue()
        #expect(manual.fetcher.fetchCount == 0)
    }

    @Test func installNeedsUserActionAndRunsEveryCheck() async {
        let r = rig()
        r.manager.checkNow()
        await wait(r.manager) { if case .available = $0 { return true } else { return false } }
        #expect(!r.installer.prepared && !r.installer.launched)       // nothing happens without the user's click
        r.manager.installAvailable()
        await wait(r.manager) { _ in r.installer.launched }
        #expect(r.installer.prepared && r.installer.launched, "state: \(r.manager.state)")
        #expect(!r.installer.preparedOnMainThread)     // hashing and verifying must not stall the main thread
    }

    @Test func checksumMismatchAndIdentityMismatchInstallNothing() async {
        let tampered = rig()
        tampered.fetcher.archive = Data("other-bytes".utf8)
        tampered.manager.checkNow()
        await wait(tampered.manager) { if case .available = $0 { return true } else { return false } }
        tampered.manager.installAvailable()
        await wait(tampered.manager) { if case .failed = $0 { return true } else { return false } }
        #expect(!tampered.installer.prepared && !tampered.installer.launched)

        let foreign = rig()
        foreign.installer.prepareError = .invalidBundle("different identity")
        foreign.manager.checkNow()
        await wait(foreign.manager) { if case .available = $0 { return true } else { return false } }
        foreign.manager.installAvailable()
        await wait(foreign.manager) { if case .failed = $0 { return true } else { return false } }
        #expect(!foreign.installer.launched)
    }

    @Test func blockedInstallFallsBackWithoutDownloading() async {
        let r = rig()
        r.installer.blocker = "not writable"
        r.manager.checkNow()
        await wait(r.manager) { if case .available = $0 { return true } else { return false } }
        r.manager.installAvailable()
        #expect(r.manager.state == .failed("not writable"))
        #expect(!r.installer.prepared)
    }

    @Test func skippedVersionIsNotOfferedAgainInBackground() async {
        let r = rig()
        r.manager.checkNow()
        await wait(r.manager) { if case .available = $0 { return true } else { return false } }
        r.manager.skipAvailableVersion()
        r.manager.checkIfDue(now: Date().addingTimeInterval(UpdateConfig.checkIntervalSeconds + 1))
        await wait(r.manager) { $0 == .upToDate }
        #expect(r.manager.state == .upToDate)
    }
}
