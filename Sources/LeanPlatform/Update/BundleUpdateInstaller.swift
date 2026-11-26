// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Security
import LeanDomain

/// Verifies a downloaded release and swaps it in for the running app. User level only: no root, no helper.
///
/// The decisive check is `SecStaticCodeCheckValidity` against the RUNNING app's own designated requirement.
/// For a self-signed identity that pins the maintainer's certificate, so a bundle signed by anybody else is refused,
/// and the Accessibility permission (tied to that same requirement) survives the update.
public struct BundleUpdateInstaller: UpdateInstalling {
    private let bundleURL: URL

    public init(bundleURL: URL = Bundle.main.bundleURL) { self.bundleURL = bundleURL }

    public func installBlocker() -> String? {
        let path = bundleURL.path
        guard path.hasSuffix(".app") else { return "LeanMac is not running from an app bundle." }
        if path.contains("AppTranslocation") { return "LeanMac is running from a quarantined location. Move it to /Applications first." }
        let parent = bundleURL.deletingLastPathComponent().path
        guard FileManager.default.isWritableFile(atPath: parent) else { return "The folder \(parent) is not writable by you." }
        return nil
    }

    public func prepare(archive: URL, expectedVersion: SemanticVersion, workDirectory: URL) throws -> URL {
        let extractDir = workDirectory.appendingPathComponent("extracted", isDirectory: true)
        try? FileManager.default.removeItem(at: extractDir)
        try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let result = Shell.runner.execute("/usr/bin/ditto", arguments: ["-x", "-k", archive.path, extractDir.path], timeout: 120)
        guard result.exitCode == 0 else { throw UpdateError.invalidBundle("The archive could not be unpacked.") }

        let entries = (try? FileManager.default.contentsOfDirectory(at: extractDir, includingPropertiesForKeys: [.isSymbolicLinkKey])) ?? []
        let apps = entries.filter { $0.pathExtension == "app" }
        guard apps.count == 1, let app = apps.first,
              (try? app.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else {
            throw UpdateError.invalidBundle("The archive must contain exactly one app.")
        }

        guard let info = Bundle(url: app)?.infoDictionary,
              info["CFBundleIdentifier"] as? String == UpdateConfig.bundleIdentifier,
              info["CFBundleShortVersionString"] as? String == expectedVersion.description else {
            throw UpdateError.invalidBundle("The app inside the archive is not the announced release.")
        }
        try verifySignature(of: app)
        return app
    }

    private func verifySignature(of app: URL) throws {
        var selfCode: SecCode?
        var selfStatic: SecStaticCode?
        var requirement: SecRequirement?
        guard SecCodeCopySelf([], &selfCode) == errSecSuccess, let selfCode,
              SecCodeCopyStaticCode(selfCode, [], &selfStatic) == errSecSuccess, let selfStatic,
              SecCodeCopyDesignatedRequirement(selfStatic, [], &requirement) == errSecSuccess,
              let requirement else {
            throw UpdateError.invalidBundle("The running app has no usable code signature.")
        }
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &staticCode) == errSecSuccess, let staticCode else {
            throw UpdateError.invalidBundle("The new app could not be read.")
        }
        let flags = SecCSFlags(rawValue: UInt32(kSecCSStrictValidate | kSecCSCheckNestedCode | kSecCSCheckAllArchitectures))
        var error: Unmanaged<CFError>?
        guard SecStaticCodeCheckValidityWithErrors(staticCode, flags, requirement, &error) == errSecSuccess else {
            throw UpdateError.invalidBundle("The new app is not signed by the same identity as this one.")
        }
    }

    public func installAndRelaunch(newApp: URL, workDirectory: URL) throws {
        if let reason = installBlocker() { throw UpdateError.cannotInstall(reason) }
        let script = workDirectory.appendingPathComponent("install-update.sh")
        try Self.scriptSource.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path, String(ProcessInfo.processInfo.processIdentifier), newApp.path, bundleURL.path,
                             workDirectory.appendingPathComponent("LeanMac.app.backup").path]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }

    /// Static text: every value arrives as an argument, nothing is interpolated into the script.
    /// It waits for the old process to exit first (the single-instance guard would kill an early new copy),
    /// keeps the old bundle until the new one is running, and puts it back if the copy fails.
    static let scriptSource = """
    #!/bin/bash
    # SPDX-License-Identifier: GPL-3.0-only
    PID="$1"; NEW="$2"; DEST="$3"; BACKUP="$4"
    for _ in $(seq 1 100); do /bin/kill -0 "$PID" 2>/dev/null || break; /bin/sleep 0.3; done
    /bin/kill -0 "$PID" 2>/dev/null && exit 1
    /bin/rm -rf "$BACKUP"
    /bin/mv "$DEST" "$BACKUP" || exit 1
    if /usr/bin/ditto "$NEW" "$DEST"; then
        /usr/bin/open "$DEST"
        for _ in $(seq 1 30); do /usr/bin/pgrep -x LeanMac >/dev/null && break; /bin/sleep 0.5; done
        /bin/rm -rf "$BACKUP" "$NEW"
    else
        /bin/rm -rf "$DEST"
        /bin/mv "$BACKUP" "$DEST"
        /usr/bin/open "$DEST"
    fi
    """
}
