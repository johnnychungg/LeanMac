// SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// Downloads over HTTPS from the allowed hosts only (every redirect is checked too).
public protocol UpdateFetching: Sendable {
    func fetchData(_ url: URL, maxBytes: Int) async throws -> Data
    /// Downloads into `directory` and returns the file URL.
    func download(_ url: URL, into directory: URL, maxBytes: Int) async throws -> URL
}

/// Verifies and installs a downloaded release. Never root, never touches the privileged helper.
public protocol UpdateInstalling: Sendable {
    /// nil when the running app can replace itself; otherwise the reason why it must not.
    func installBlocker() -> String?
    /// Unpacks the zip and returns the new `.app` only if it passes every check (bundle ID, version,
    /// code signature and the same designated requirement as the running app).
    func prepare(archive: URL, expectedVersion: SemanticVersion, workDirectory: URL) throws -> URL
    /// Starts the detached swap-and-relaunch script. The caller quits the app right after.
    func installAndRelaunch(newApp: URL, workDirectory: URL) throws
}

public struct UpdateServices: Sendable {
    public var fetcher: UpdateFetching
    public var installer: UpdateInstalling
    public var currentVersion: SemanticVersion
    public var isEnabled: Bool

    public init(fetcher: UpdateFetching, installer: UpdateInstalling, currentVersion: SemanticVersion, isEnabled: Bool) {
        self.fetcher = fetcher; self.installer = installer
        self.currentVersion = currentVersion; self.isEnabled = isEnabled
    }

    private final class Box: @unchecked Sendable {
        let lock = NSLock()
        var services: UpdateServices?
    }
    private static let box = Box()

    /// Installed once at launch by `AppContainer`; before that (previews, tests) the updater is inert.
    public static var current: UpdateServices {
        get { box.lock.lock(); defer { box.lock.unlock() }; return box.services ?? .inert }
        set { box.lock.lock(); defer { box.lock.unlock() }; box.services = newValue }
    }

    public static var inert: UpdateServices {
        UpdateServices(fetcher: InertUpdateFetcher(), installer: InertUpdateInstaller(),
                       currentVersion: SemanticVersion(0, 0, 0), isEnabled: false)
    }
}

struct InertUpdateFetcher: UpdateFetching {
    func fetchData(_ url: URL, maxBytes: Int) async throws -> Data { throw UpdateError.notConfigured }
    func download(_ url: URL, into directory: URL, maxBytes: Int) async throws -> URL { throw UpdateError.notConfigured }
}
struct InertUpdateInstaller: UpdateInstalling {
    func installBlocker() -> String? { "Updates are switched off." }
    func prepare(archive: URL, expectedVersion: SemanticVersion, workDirectory: URL) throws -> URL { throw UpdateError.notConfigured }
    func installAndRelaunch(newApp: URL, workDirectory: URL) throws { throw UpdateError.notConfigured }
}
