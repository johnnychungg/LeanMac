// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import LeanDomain

/// Installs the privileged helper: stages a clean copy of the bundled files in a private (0700) folder,
/// then runs `install-helper.sh` as root through the standard macOS administrator-password prompt.
public struct HelperInstaller: HelperInstalling {
    public init() {}

    public func install(using gateway: HelperGateway) -> Int {
        // Source files come only from the app bundle (or /Applications/LeanMac.app), never from the working directory.
        let searchDirs = [
            Bundle.main.resourcePath,
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources").path,
            "/Applications/LeanMac.app/Contents/Resources"
        ].compactMap { $0 }

        var smcSrc = Bundle.main.path(forResource: "smc", ofType: nil)
        var helperSrc = Bundle.main.path(forResource: "leanmac-power", ofType: nil)
        var installScript = Bundle.main.path(forResource: "install-helper", ofType: "sh")

        let fm = FileManager.default
        for dir in searchDirs {
            if smcSrc == nil {
                let path = (dir as NSString).appendingPathComponent("smc")
                if fm.fileExists(atPath: path) { smcSrc = path }
            }
            if helperSrc == nil {
                let path = (dir as NSString).appendingPathComponent("leanmac-power")
                if fm.fileExists(atPath: path) { helperSrc = path }
            }
            if installScript == nil {
                let path = (dir as NSString).appendingPathComponent("install-helper.sh")
                if fm.fileExists(atPath: path) { installScript = path }
            }
        }

        guard let sSMC = smcSrc, let sHelper = helperSrc, let sInstall = installScript else {
            appLog("installHelper: missing resource paths (smc: \(smcSrc ?? "nil"), helper: \(helperSrc ?? "nil"), script: \(installScript ?? "nil"))")
            return 0
        }

        // Read the payload into memory once; root never reads a user-writable file (see HelperInstallCommand).
        guard let installData = fm.contents(atPath: sInstall),
              let smcData = fm.contents(atPath: sSMC),
              let powerData = fm.contents(atPath: sHelper) else {
            appLog("installHelper: could not read bundled resources")
            return 0
        }
        // The user name goes into a sudoers rule: accept only safe characters (the script checks again as root).
        guard let command = HelperInstallCommand.shellCommand(
            user: NSUserName(), installScript: installData, smc: smcData, power: powerData
        ) else {
            appLog("installHelper: unsafe user name or oversized payload")
            return 0
        }

        var errorDict: NSDictionary?
        if let object = NSAppleScript(source: HelperInstallCommand.appleScript(for: command)) {
            _ = object.executeAndReturnError(&errorDict)
            if let err = errorDict { appLog("installHelper AppleScript error: \(err)") }
        }

        // Verify with a real call to the helper.
        let (out, code) = gateway.run(.version)
        return PrivilegedHelper.parseVersion(output: out, exitCode: code)
    }

    public static func isSafeUserName(_ user: String) -> Bool { HelperInstallCommand.isSafeUserName(user) }
}
