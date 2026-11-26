// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Testing
import LeanDomain

@Suite("FanReader")
struct FanReaderTests {
    private struct FakeSMC: SMCReading {
        var keys: [String: [UInt8]]
        func readKeyBytes(_ key: String) -> [UInt8]? { keys[key] }
    }
    private func flt(_ value: Float) -> [UInt8] {
        let bits = value.bitPattern
        return [UInt8(bits & 0xff), UInt8((bits >> 8) & 0xff), UInt8((bits >> 16) & 0xff), UInt8((bits >> 24) & 0xff)]
    }

    @Test func readsTwoFans() {
        let smc = FakeSMC(keys: ["FNum": [2], "F0Ac": flt(1523.4), "F0Mn": flt(1200), "F0Mx": flt(5800),
                                 "F1Ac": flt(1610), "F1Mn": flt(1200), "F1Mx": flt(5800)])
        #expect(FanReader.read(from: smc) == [FanInfo(index: 0, rpm: 1523, minRPM: 1200, maxRPM: 5800),
                                              FanInfo(index: 1, rpm: 1610, minRPM: 1200, maxRPM: 5800)])
    }

    @Test func fanlessMacAndMissingKeysGiveNoFans() {
        #expect(FanReader.read(from: FakeSMC(keys: ["FNum": [0]])).isEmpty)
        #expect(FanReader.read(from: FakeSMC(keys: [:])).isEmpty)
        #expect(FanReader.read(from: FakeSMC(keys: ["FNum": [1]])).isEmpty)   // count without a reading
    }

    @Test func decodesBothSmcFormatsAndRejectsGarbage() {
        #expect(FanReader.decode(flt(0)) == 0)
        #expect(FanReader.decode([0x17, 0x70]) == 1500)                        // fpe2: 0x1770 >> 2
        #expect(FanReader.decode(flt(.nan)) == nil)
        #expect(FanReader.decode(flt(-5)) == nil)
        #expect(FanReader.decode([1, 2, 3]) == nil)
    }
}
