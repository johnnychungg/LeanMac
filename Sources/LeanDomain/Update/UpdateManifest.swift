// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import CryptoKit

/// Fixed facts about where updates come from. Changing any of them is a security decision (see ADR 0004).
public enum UpdateConfig {
    public static let owner = "johnnychungg"
    public static let repository = "LeanMac"
    /// The signed manifest published with every release (the "latest" alias never returns drafts or pre-releases).
    public static let manifestURL = URL(string: "https://github.com/johnnychungg/LeanMac/releases/latest/download/update.json")!
    public static let signatureURL = URL(string: "https://github.com/johnnychungg/LeanMac/releases/latest/download/update.json.sig")!
    /// Hosts a request or redirect may touch. Everything else is refused.
    public static let allowedHosts: Set<String> = ["github.com", "objects.githubusercontent.com", "release-assets.githubusercontent.com"]
    /// Base64 of the raw 32-byte Ed25519 public key (`Scripts/updater-keygen.sh` prints it).
    /// Empty = no key has been provisioned yet, and the updater stays switched off.
    public static let publicKeyBase64 = "vRjR5siWJ3I2+mUcN1HtUS64pC10OuSnOCGfkWy6Nx8="
    public static let bundleIdentifier = "com.local.jmac"
    public static let maxManifestBytes = 64 * 1024
    public static let maxArchiveBytes = 100 * 1024 * 1024
    public static let checkIntervalSeconds: TimeInterval = 24 * 3600
}

/// The signed description of one release (`update.json`).
public struct UpdateManifest: Codable, Equatable, Sendable {
    public let version: String
    public let build: Int
    public let minimumSystemVersion: String
    public let url: URL
    public let sha256: String
    public let notesURL: URL?

    public init(version: String, build: Int, minimumSystemVersion: String, url: URL, sha256: String, notesURL: URL?) {
        self.version = version; self.build = build; self.minimumSystemVersion = minimumSystemVersion
        self.url = url; self.sha256 = sha256; self.notesURL = notesURL
    }

    public var semanticVersion: SemanticVersion? { SemanticVersion(version) }
}

public enum UpdateError: Error, Equatable, Sendable {
    case notConfigured
    case badURL
    case tooLarge
    case badSignature
    case badManifest
    case checksumMismatch
    case invalidBundle(String)
    case cannotInstall(String)
    case network(String)
}

public enum UpdateDecision: Equatable, Sendable {
    case upToDate
    case skipped(SemanticVersion)
    case needsNewerSystem(UpdateManifest)
    case available(UpdateManifest)
}

public enum UpdateVerifier {
    /// True only when `signatureBase64` is a valid Ed25519 signature of exactly `data` under the given key.
    public static func isValid(data: Data, signatureBase64: String, publicKeyBase64: String) -> Bool {
        guard let keyData = Data(base64Encoded: publicKeyBase64.trimmingCharacters(in: .whitespacesAndNewlines)),
              let sig = Data(base64Encoded: signatureBase64.trimmingCharacters(in: .whitespacesAndNewlines)),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData) else { return false }
        return key.isValidSignature(sig, for: data)
    }

    public static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Only HTTPS, only the allowed hosts.
    public static func isAllowed(_ url: URL, hosts: Set<String> = UpdateConfig.allowedHosts) -> Bool {
        url.scheme == "https" && url.user == nil && url.port == nil && hosts.contains(url.host?.lowercased() ?? "")
    }

    /// A release asset must live under this repository's own release path, not just on github.com.
    public static func isReleaseAsset(_ url: URL, owner: String = UpdateConfig.owner, repository: String = UpdateConfig.repository) -> Bool {
        guard isAllowed(url), url.host?.lowercased() == "github.com" else { return false }
        return url.path.hasPrefix("/\(owner)/\(repository)/releases/")
    }

    /// Verifies the signature, decodes the manifest and applies every policy (rollback, OS, skip list, URL pinning).
    public static func evaluate(manifestData: Data, signatureBase64: String, publicKeyBase64: String,
                                currentVersion: SemanticVersion, systemVersion: SemanticVersion,
                                skipped: SemanticVersion?, owner: String = UpdateConfig.owner,
                                repository: String = UpdateConfig.repository) throws -> UpdateDecision {
        guard !publicKeyBase64.isEmpty else { throw UpdateError.notConfigured }
        guard manifestData.count <= UpdateConfig.maxManifestBytes else { throw UpdateError.tooLarge }
        guard isValid(data: manifestData, signatureBase64: signatureBase64, publicKeyBase64: publicKeyBase64) else {
            throw UpdateError.badSignature
        }
        guard let manifest = try? JSONDecoder().decode(UpdateManifest.self, from: manifestData),
              let version = manifest.semanticVersion,
              manifest.sha256.count == 64, manifest.sha256.allSatisfy(\.isHexDigit),
              isReleaseAsset(manifest.url, owner: owner, repository: repository),
              manifest.notesURL.map({ isReleaseAsset($0, owner: owner, repository: repository) }) ?? true
        else { throw UpdateError.badManifest }

        guard version > currentVersion else { return .upToDate }          // equal or older: never roll back
        if let skipped, skipped == version { return .skipped(version) }
        if let minimum = SemanticVersion(manifest.minimumSystemVersion.split(separator: ".").count == 2
                                         ? manifest.minimumSystemVersion + ".0" : manifest.minimumSystemVersion),
           systemVersion < minimum {
            return .needsNewerSystem(manifest)
        }
        return .available(manifest)
    }
}
