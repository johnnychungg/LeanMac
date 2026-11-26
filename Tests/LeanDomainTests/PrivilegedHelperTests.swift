// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Testing
import LeanDomain

@Suite("PrivilegedHelper")
struct PrivilegedHelperTests {
    /// These values are baked into every existing install (files on disk, sudoers rule, version check).
    /// A pull request that changes one of them must change this test on purpose.
    @Test func installLocationsAndVersionAreLocked() {
        #expect(PrivilegedHelper.powerPath == "/Library/PrivilegedHelperTools/com.local.leanmac.power")
        #expect(PrivilegedHelper.smcPath == "/Library/PrivilegedHelperTools/com.local.leanmac.smc")
        #expect(PrivilegedHelper.sudoersPath == "/etc/sudoers.d/leanmac_power")
        #expect(PrivilegedHelper.requiredVersion == 1)
    }

    @Test func chargeLimitAcceptsOnlyHelperRange() {
        #expect(ChargeLimit(20)?.value == 20)
        #expect(ChargeLimit(100)?.value == 100)
        for bad in [-1, 0, 19, 101, 1_000, Int.max, Int.min] {
            #expect(ChargeLimit(bad) == nil)
        }
        #expect(ChargeLimit(clamping: 5).value == 20)
        #expect(ChargeLimit(clamping: 500).value == 100)
        #expect(ChargeLimit(clamping: 80).value == 80)
    }

    @Test func commandsBuildExactCommandLines() {
        let p = PrivilegedHelper.powerPath
        let eighty = ChargeLimit(clamping: 80)
        #expect(PrivilegedHelper.sudoCommand(.version) == "sudo -n \(p) version")
        #expect(PrivilegedHelper.sudoCommand(.status) == "sudo -n \(p) status")
        #expect(PrivilegedHelper.sudoCommand(.chargeOff(eighty)) == "sudo -n \(p) charge-off 80")
        #expect(PrivilegedHelper.sudoCommand(.chargeOn(eighty)) == "sudo -n \(p) charge-on 80")
        #expect(PrivilegedHelper.sudoCommand(.dischargeOn) == "sudo -n \(p) discharge-on")
        #expect(PrivilegedHelper.sudoCommand(.dischargeOff) == "sudo -n \(p) discharge-off")
    }

    @Test func everyCommandLineContainsOnlySafeCharacters() {
        let all: [HelperCommand] = [.version, .status, .dischargeOn, .dischargeOff,
                                    .chargeOff(ChargeLimit(clamping: 20)), .chargeOn(ChargeLimit(clamping: 100))]
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 -./_")
        for command in all {
            #expect(PrivilegedHelper.sudoCommand(command).allSatisfy { allowed.contains($0) })
        }
    }

    @Test func onlyChargeAndDischargeWriteHardware() {
        #expect(!HelperCommand.version.writesHardware)
        #expect(!HelperCommand.status.writesHardware)
        #expect(HelperCommand.dischargeOn.writesHardware)
        #expect(HelperCommand.dischargeOff.writesHardware)
        #expect(HelperCommand.chargeOn(ChargeLimit(clamping: 90)).writesHardware)
        #expect(HelperCommand.chargeOff(ChargeLimit(clamping: 90)).writesHardware)
    }

    @Test func parsesHelperVersion() {
        #expect(PrivilegedHelper.parseVersion(output: "HELPER_VERSION:1", exitCode: 0) == 1)
        #expect(PrivilegedHelper.parseVersion(output: "noise\nHELPER_VERSION: 12 \n", exitCode: 0) == 12)
        #expect(PrivilegedHelper.parseVersion(output: "HELPER_VERSION:1", exitCode: 1) == 0)
        #expect(PrivilegedHelper.parseVersion(output: "sudo: a password is required", exitCode: 1) == 0)
        #expect(PrivilegedHelper.parseVersion(output: "HELPER_VERSION:abc", exitCode: 0) == 0)
    }

    // MARK: - Install command (no staging folder, payload travels inline)

    private func sample(user: String = "johnny", size: Int = 100) -> String? {
        let blob = Data(repeating: 0xAB, count: size)
        return HelperInstallCommand.shellCommand(user: user, installScript: blob, smc: blob, power: blob)
    }

    @Test func installCommandNeverTouchesUserWritableFiles() throws {
        let command = try #require(sample())
        #expect(!command.contains("/Users"))
        #expect(!command.contains("/var/folders"))
        #expect(!command.contains("TMPDIR"))
        #expect(command.contains("/usr/bin/mktemp -d /private/tmp/leanmac.XXXXXX"))   // explicit template, never $TMPDIR
        #expect(command.contains("cd \"$T\""))
        #expect(command.contains("/bin/bash ./install-helper.sh ./smc ./leanmac-power"))
        #expect(command.contains("base64 -D"))
    }

    @Test func installCommandContainsOnlyWhitelistedCharacters() throws {
        let command = try #require(sample())
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789+/= -._$|&;?'\"()%>")
        #expect(command.allSatisfy { allowed.contains($0) })
    }

    @Test func installCommandRejectsUnsafeUsersAndOversizedPayloads() {
        for bad in ["root", "ALL", ".", "..", "-x", "a b", "a;b", "a'b", "a$(id)", ""] {
            #expect(sample(user: bad) == nil)
        }
        #expect(sample(size: HelperInstallCommand.maxPayloadBytes) == nil)   // 3 files > cap
        #expect(sample(size: 1_000) != nil)
    }

    @Test func appleScriptEscapesQuotesAndBackslashes() throws {
        let source = HelperInstallCommand.appleScript(for: #"a "b" \c"#)
        #expect(source == #"do shell script "a \"b\" \\c" with administrator privileges"#)
    }
}
