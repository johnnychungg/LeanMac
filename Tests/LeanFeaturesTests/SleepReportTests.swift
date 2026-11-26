// SPDX-License-Identifier: GPL-3.0-only
import Testing
@testable import LeanFeatures
import LeanDomain

@Suite("Sleep report", .serialized)
@MainActor
struct SleepReportTests {
    @Test func reportIsBuiltFromNumbersInTheCurrentLanguage() {
        let record = BatteryManager.SleepRecord(seconds: 8 * 3600 + 44 * 60, from: 63, to: 61)
        L10n.setLanguage(.en)
        let english = BatteryManager.sleepSummary(record)
        #expect(english.hasPrefix("Slept 8h44m"))
        #expect(english.contains("63%"))
        L10n.setLanguage(.en)
    }

    @Test func noDrainWhenLevelDidNotFall() {
        L10n.setLanguage(.en)
        #expect(BatteryManager.sleepDrainText(from: 60, to: 62) == "Battery drain: 0%")
    }
}
