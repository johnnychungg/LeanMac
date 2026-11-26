// SPDX-License-Identifier: GPL-3.0-only
import Testing
import LeanDomain
import LeanTestSupport

@Suite("SMCChargeState")
struct SMCChargeStateTests {
    @Test func noKnownKeyMeansUnknown() {
        #expect(SMCChargeState.isBypassed(FakeSMC()) == nil)
        #expect(SMCChargeState.isBypassed(FakeSMC(["CHTE": []])) == nil)
    }

    @Test func appleSiliconInhibitKeys() {
        #expect(SMCChargeState.isBypassed(FakeSMC(["CHTE": [1, 0, 0, 0]])) == true)
        #expect(SMCChargeState.isBypassed(FakeSMC(["CHTE": [0, 0, 0, 0]])) == false)
        #expect(SMCChargeState.isBypassed(FakeSMC(["CH0B": [2]])) == true)
        #expect(SMCChargeState.isBypassed(FakeSMC(["CH0B": [0]])) == false)
        #expect(SMCChargeState.isBypassed(FakeSMC(["bfF0": [1]])) == true)
        #expect(SMCChargeState.isBypassed(FakeSMC(["bfF0": [2]])) == true)
        #expect(SMCChargeState.isBypassed(FakeSMC(["bfF0": [0]])) == false)
    }

    @Test func intelChargeLimit() {
        #expect(SMCChargeState.isBypassed(FakeSMC(["BCLM": [80]])) == true)
        #expect(SMCChargeState.isBypassed(FakeSMC(["BCLM": [100]])) == false)
        #expect(SMCChargeState.isBypassed(FakeSMC(["BCLM": [0]])) == false)
    }

    @Test func anyEngagedKeyWins() {
        #expect(SMCChargeState.isBypassed(FakeSMC(["CHTE": [0], "bfF0": [2]])) == true)
    }
}
