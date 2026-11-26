// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import AppKit
import Combine
import LeanDomain

/// Checks for a newer release, tells the user, and installs it only after the user confirms.
///
/// No repeating timer: one check shortly after launch and one when the popover opens, at most once a day.
/// Nothing is installed without the signature and code-signature checks in `UpdateVerifier` / `UpdateInstalling`.
@MainActor
public final class UpdateManager: ObservableObject {
    public static let shared = UpdateManager()

    public enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(UpdateManifest)
        case needsNewerSystem(UpdateManifest)
        case downloading
        case installing
        case failed(String)
    }

    @Published public private(set) var state: State = .idle
    @Published public var autoCheckEnabled: Bool {
        didSet { defaults.set(autoCheckEnabled, forKey: Keys.autoCheck) }
    }

    private enum Keys {
        static let autoCheck = "update_auto_check"
        static let lastCheck = "update_last_check"
        static let skipped = "update_skipped_version"
        static let notified = "update_notified_version"
        static let lastFailure = "update_last_failure"
    }

    private let defaults: UserDefaults
    private let services: () -> UpdateServices
    private let publicKey: String
    private let systemVersion: SemanticVersion
    private let workRoot: URL
    private let quit: @MainActor () -> Void
    private var task: Task<Void, Never>?

    public init(defaults: UserDefaults = .standard,
                services: @escaping () -> UpdateServices = { UpdateServices.current },
                publicKey: String = UpdateConfig.publicKeyBase64,
                systemVersion: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion,
                quit: @escaping @MainActor () -> Void = { NSApp.terminate(nil) },
                workRoot: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches/LeanMac/Updates", isDirectory: true)) {
        self.quit = quit
        self.workRoot = workRoot
        self.defaults = defaults
        self.services = services
        self.publicKey = publicKey
        self.systemVersion = SemanticVersion(systemVersion.majorVersion, systemVersion.minorVersion, systemVersion.patchVersion)
        autoCheckEnabled = (defaults.object(forKey: Keys.autoCheck) as? Bool) ?? true
    }

    public var isAvailableInThisBuild: Bool { services().isEnabled && !publicKey.isEmpty }
    public var currentVersion: String { services().currentVersion.description }
    public var installBlocker: String? { services().installer.installBlocker() }

    // MARK: - Checking

    /// Called at launch (after a short delay) and when the popover opens. Does nothing unless a day has passed.
    public func checkIfDue(now: Date = Date()) {
        guard isAvailableInThisBuild, autoCheckEnabled, !isBusy else { return }
        let last = defaults.object(forKey: Keys.lastCheck) as? Date ?? .distantPast
        guard now.timeIntervalSince(last) >= UpdateConfig.checkIntervalSeconds else { return }
        // An offline Mac must not retry on every popover open.
        let lastFailure = defaults.object(forKey: Keys.lastFailure) as? Date ?? .distantPast
        guard now.timeIntervalSince(lastFailure) >= 3600 else { return }
        check(userInitiated: false)
    }

    public func checkNow() {
        guard isAvailableInThisBuild, !isBusy else { return }
        check(userInitiated: true)
    }

    private var isBusy: Bool {
        switch state {
        case .checking, .downloading, .installing: return true
        default: return false
        }
    }

    private func check(userInitiated: Bool) {
        let services = services()
        let key = publicKey
        let system = systemVersion
        let skipped = defaults.string(forKey: Keys.skipped).flatMap { SemanticVersion($0) }
        state = .checking
        task = Task { [weak self] in
            do {
                let data = try await services.fetcher.fetchData(UpdateConfig.manifestURL, maxBytes: UpdateConfig.maxManifestBytes)
                let sigData = try await services.fetcher.fetchData(UpdateConfig.signatureURL, maxBytes: 4096)
                let signature = String(decoding: sigData, as: UTF8.self)
                let decision = try UpdateVerifier.evaluate(
                    manifestData: data, signatureBase64: signature, publicKeyBase64: key,
                    currentVersion: services.currentVersion, systemVersion: system,
                    skipped: userInitiated ? nil : skipped)
                self?.finishCheck(decision, userInitiated: userInitiated)
            } catch {
                self?.failCheck(error, userInitiated: userInitiated)
            }
        }
    }

    private func finishCheck(_ decision: UpdateDecision, userInitiated: Bool) {
        defaults.set(Date(), forKey: Keys.lastCheck)
        switch decision {
        case .upToDate, .skipped:
            state = .upToDate
        case .needsNewerSystem(let manifest):
            state = .needsNewerSystem(manifest)
        case .available(let manifest):
            state = .available(manifest)
            if !userInitiated, defaults.string(forKey: Keys.notified) != manifest.version {
                defaults.set(manifest.version, forKey: Keys.notified)
                Notifier.send(title: tr("LeanMac update available"),
                              body: tr("Version \(manifest.version) is ready. Open LeanMac settings to install it."), sound: false)
            }
        }
    }

    private func failCheck(_ error: Error, userInitiated: Bool) {
        appLog("Update check failed: \(error)")
        defaults.set(Date(), forKey: Keys.lastFailure)
        // A background check that fails stays silent; only an explicit "Check now" reports the problem.
        state = userInitiated ? .failed(Self.message(for: error)) : .idle
    }

    // MARK: - Installing

    /// Starts the download and install after the user pressed the button.
    public func installAvailable() {
        guard case .available(let manifest) = state, let version = manifest.semanticVersion else { return }
        let services = services()
        let root = workRoot
        if let reason = services.installer.installBlocker() {
            state = .failed(reason)
            return
        }
        state = .downloading
        task = Task { [weak self] in
            do {
                let work = try Self.makeWorkDirectory(in: root)
                let zip = try await services.fetcher.download(manifest.url, into: work, maxBytes: UpdateConfig.maxArchiveBytes)
                self?.state = .installing
                // Hashing up to 100 MB, unpacking and the code-signature check are heavy: never on the main thread
                // (the keyboard event tap lives on its run loop).
                let expected = manifest.sha256.lowercased()
                try await Task.detached(priority: .userInitiated) {
                    let bytes = try Data(contentsOf: zip, options: .mappedIfSafe)
                    guard UpdateVerifier.sha256Hex(bytes) == expected else { throw UpdateError.checksumMismatch }
                    let newApp = try services.installer.prepare(archive: zip, expectedVersion: version, workDirectory: work)
                    try services.installer.installAndRelaunch(newApp: newApp, workDirectory: work)
                }.value
                self?.quit()
            } catch {
                appLog("Update install failed: \(error)")
                self?.state = .failed(Self.message(for: error))
            }
        }
    }

    public func skipAvailableVersion() {
        guard case .available(let manifest) = state else { return }
        defaults.set(manifest.version, forKey: Keys.skipped)
        state = .idle
    }

    public func openReleasePage() {
        let url: URL?
        switch state {
        case .available(let m), .needsNewerSystem(let m): url = m.notesURL ?? URL(string: "https://github.com/\(UpdateConfig.owner)/\(UpdateConfig.repository)/releases")
        default: url = URL(string: "https://github.com/\(UpdateConfig.owner)/\(UpdateConfig.repository)/releases")
        }
        if let url, UpdateVerifier.isAllowed(url) { NSWorkspace.shared.open(url) }
    }

    // MARK: - Helpers

    /// `~/Library/Caches/LeanMac/Updates/<uuid>`, private to the user; older runs are removed first.
    private static func makeWorkDirectory(in root: URL) throws -> URL {
        try? FileManager.default.removeItem(at: root)
        let dir = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return dir
    }

    static func message(for error: Error) -> String {
        switch error as? UpdateError {
        case .notConfigured: return tr("Updates are not set up in this build.")
        case .badSignature: return tr("The update information is not signed by LeanMac. Nothing was installed.")
        case .badManifest, .badURL: return tr("The update information is not valid.")
        case .tooLarge: return tr("The update is larger than allowed.")
        case .checksumMismatch: return tr("The download is damaged. Nothing was installed.")
        case .invalidBundle(let reason): return tr("The update was rejected: \(reason)")
        case .cannotInstall(let reason): return reason
        case .network: return tr("Could not reach GitHub. Try again later.")
        case nil: return tr("Update failed.")
        }
    }
}
