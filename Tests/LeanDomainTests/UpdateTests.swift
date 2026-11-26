// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import CryptoKit
import Testing
import LeanDomain

@Suite("Update")
struct UpdateTests {
    private let key = Curve25519.Signing.PrivateKey()
    private var publicKey: String { key.publicKey.rawRepresentation.base64EncodedString() }
    private let sha = String(repeating: "a", count: 64)
    private let asset = "https://github.com/johnnychungg/LeanMac/releases/download/v1.2.0/LeanMac-1.2.0.zip"

    private func manifest(version: String = "1.2.0", url: String? = nil, min: String = "14.0", sha: String? = nil) -> Data {
        let json = """
        {"version":"\(version)","build":2,"minimumSystemVersion":"\(min)","url":"\(url ?? asset)","sha256":"\(sha ?? self.sha)",
         "notesURL":"https://github.com/johnnychungg/LeanMac/releases/tag/v\(version)"}
        """
        return Data(json.utf8)
    }
    private func sign(_ data: Data) -> String { try! key.signature(for: data).base64EncodedString() }

    private func evaluate(_ data: Data, sig: String? = nil, current: String = "1.0.0", system: String = "14.5.0",
                          skipped: String? = nil, publicKey: String? = nil) throws -> UpdateDecision {
        try UpdateVerifier.evaluate(manifestData: data, signatureBase64: sig ?? sign(data),
                                    publicKeyBase64: publicKey ?? self.publicKey,
                                    currentVersion: SemanticVersion(current)!, systemVersion: SemanticVersion(system)!,
                                    skipped: skipped.flatMap { SemanticVersion($0) })
    }

    @Test func versionParsingAndOrdering() {
        #expect(SemanticVersion("1.2.3") == SemanticVersion(1, 2, 3))
        #expect(SemanticVersion("v10.0.1") == SemanticVersion(10, 0, 1))
        #expect(SemanticVersion("1.10.0")! > SemanticVersion("1.9.9")!)
        for bad in ["1.2", "1.2.3.4", "a.b.c", "1.2.-3", "1..3", "", "1.2.3-beta", "+1.2.3"] {
            #expect(SemanticVersion(bad) == nil)
        }
    }

    @Test func validNewerManifestIsAvailable() throws {
        guard case .available(let m) = try evaluate(manifest()) else { Issue.record("expected available"); return }
        #expect(m.version == "1.2.0")
    }

    @Test func tamperedManifestAndWrongKeyAreRejected() throws {
        let data = manifest()
        let sig = sign(data)
        let tampered = manifest(url: "https://github.com/johnnychungg/LeanMac/releases/download/v1.2.0/evil.zip")
        #expect(throws: UpdateError.badSignature) { try evaluate(tampered, sig: sig) }
        let other = Curve25519.Signing.PrivateKey().publicKey.rawRepresentation.base64EncodedString()
        #expect(throws: UpdateError.badSignature) { try evaluate(data, publicKey: other) }
        #expect(throws: UpdateError.badSignature) { try evaluate(data, sig: "not-base64!") }
    }

    @Test func noKeyMeansNotConfigured() {
        #expect(throws: UpdateError.notConfigured) { try evaluate(manifest(), publicKey: "") }
    }

    @Test func rollbackAndSameVersionAreUpToDate() throws {
        #expect(try evaluate(manifest(version: "1.0.0")) == .upToDate)
        #expect(try evaluate(manifest(version: "0.9.0")) == .upToDate)
    }

    @Test func skippedVersionAndMinimumSystem() throws {
        #expect(try evaluate(manifest(), skipped: "1.2.0") == .skipped(SemanticVersion(1, 2, 0)))
        guard case .needsNewerSystem = try evaluate(manifest(min: "15.0"), system: "14.5.0") else {
            Issue.record("expected needsNewerSystem"); return
        }
        guard case .available = try evaluate(manifest(min: "14.0"), system: "14.0.0") else {
            Issue.record("expected available"); return
        }
    }

    @Test func urlsMustBeThisRepositorysReleaseAssets() {
        for bad in ["http://github.com/johnnychungg/LeanMac/releases/download/v1/x.zip",
                    "https://evil.example.com/johnnychungg/LeanMac/releases/download/v1/x.zip",
                    "https://github.com/someone/else/releases/download/v1/x.zip",
                    "https://github.com:8443/johnnychungg/LeanMac/releases/download/v1/x.zip",
                    "https://user@github.com/johnnychungg/LeanMac/releases/download/v1/x.zip",
                    "https://objects.githubusercontent.com/johnnychungg/LeanMac/releases/download/v1/x.zip"] {
            #expect(throws: UpdateError.badManifest) { try evaluate(manifest(url: bad)) }
        }
        #expect(UpdateVerifier.isAllowed(URL(string: "https://objects.githubusercontent.com/x")!))
        #expect(!UpdateVerifier.isAllowed(URL(string: "https://githubusercontent.com.evil.com/x")!))
    }

    @Test func badChecksumFormatIsRejected() {
        #expect(throws: UpdateError.badManifest) { try evaluate(manifest(sha: "xyz")) }
    }

    @Test func sha256Hex() {
        #expect(UpdateVerifier.sha256Hex(Data("abc".utf8)) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
}
