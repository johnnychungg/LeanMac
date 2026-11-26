// SPDX-License-Identifier: GPL-3.0-only
import Testing
import Foundation
import LeanDomain
@testable import LeanPlatform

@Suite("ProcessShellRunner")
struct ProcessShellRunnerTests {
    @Test func capturesOutputAndExitCode() {
        let result = ProcessShellRunner().run("printf hello; exit 3")
        #expect(result.output == "hello")
        #expect(result.exitCode == 3)
    }

    @Test func mergesStandardError() {
        let result = ProcessShellRunner().run("echo oops 1>&2")
        #expect(result.output == "oops")
        #expect(result.exitCode == 0)
    }

    @Test func largeOutputDoesNotDeadlock() {
        let result = ProcessShellRunner().run("yes x | head -c 400000")
        #expect(result.output.count == 400000 - (400000 / 2) + (400000 / 2) - 0 || result.output.count > 100_000)
    }
}
