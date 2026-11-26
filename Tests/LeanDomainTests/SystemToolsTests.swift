// SPDX-License-Identifier: GPL-3.0-only
import Testing
import Foundation
@testable import LeanDomain

@Suite("TopParser")
struct TopParserTests {
    let sample = """
    Processes: 1 total
    PID    COMMAND          %CPU MEM    POWER
    1      old              1.0  1M     1.0
    PID    COMMAND          %CPU MEM    POWER
    404    WindowServer     34.2 1273M- 34.2
    94339  Microsoft Edge H 20.1 110M   20.1
    63061  top              8.1  7264K+ 8.1
    0      kernel_task      6.1  27M+   0.0
    """

    @Test func parsesLastSampleAndNamesWithSpaces() {
        let r = TopParser.parse(sample, excludingPIDs: [63061])
        #expect(r.map(\.pid) == [404, 94339])
        #expect(r[1].name == "Microsoft Edge H")
        #expect(r[0].memoryMB == 1273 && r[0].power == 34.2)
    }
    @Test func units() {
        #expect(TopParser.megabytes("7264K+") == 7264.0 / 1024)
        #expect(TopParser.megabytes("1.5G") == 1536)
        #expect(TopParser.megabytes("0B") == 0)
    }
    @Test func emptyOutput() { #expect(TopParser.parse("").isEmpty) }
}

@Suite("Launch items")
struct LaunchItemTests {
    @Test func parsesPlist() throws {
        let dict: [String: Any] = ["Label": "com.google.keystone.agent", "ProgramArguments": ["/Users/x/Library/Google/GoogleSoftwareUpdate.app/Contents/MacOS/ksagent", "-a"],
                                   "RunAtLoad": true, "KeepAlive": ["SuccessfulExit": false]]
        let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
        let item = try #require(LaunchPlist.parse(data: data, path: "/p.plist"))
        #expect(item.label == "com.google.keystone.agent" && item.runAtLoad && item.keepAlive)
        #expect(item.displayName == "GoogleSoftwareUpdate")
        #expect(!item.isApple)
    }
    @Test func rejectsPlistWithoutLabel() throws {
        let data = try PropertyListSerialization.data(fromPropertyList: ["x": 1], format: .xml, options: 0)
        #expect(LaunchPlist.parse(data: data, path: "/p") == nil)
    }
    @Test func displayNameFromLabel() {
        #expect(LaunchPlist.displayName(label: "io.tailscale.ipn.macsys.login-item-helper", program: "") == "tailscale ipn")
    }
    @Test func parsesDisabledDB() {
        let out = """
        disabled services = {
        \t"a.b" => enabled
        \t"c.d" => disabled
        }
        """
        #expect(DisabledDB.parse(out) == ["a.b": false, "c.d": true])
    }
    @Test func runningLabels() {
        let out = "PID\tStatus\tLabel\n-\t0\ta.b\n123\t0\tc.d\n"
        #expect(DisabledDB.runningLabels(fromList: out) == ["c.d"])
    }
}

@Suite("MemoryStats")
struct MemoryStatsTests {
    @Test func matchesActivityMonitorFormula() {
        // Real numbers measured on a 24 GB Mac: internal 533762, purgeable 11798, wired 219751, compressor 434018 (16 KB pages)
        let s = MemoryStats(internalPages: 533_762, purgeablePages: 11_798, wiredPages: 219_751,
                            compressedPages: 434_018, pageSize: 16_384, totalBytes: 25_769_803_776)
        #expect(abs(MemoryStats.gb(s.usedBytes) - 17.9) < 0.1)
        #expect(abs(s.usedPercent - 74.6) < 0.5)
        #expect(s.summary == "17.9 / 24 GB")
    }
    @Test func clampsAndHandlesUnderflow() {
        let s = MemoryStats(internalPages: 1, purgeablePages: 5, wiredPages: 0, compressedPages: 0, pageSize: 4096, totalBytes: 0)
        #expect(s.appBytes == 0 && s.usedPercent == 0)
    }
    @Test func pressureLevels() {
        #expect(MemoryPressure(sysctlLevel: 1) == .normal)
        #expect(MemoryPressure(sysctlLevel: 2) == .warning)
        #expect(MemoryPressure(sysctlLevel: 4) == .critical)
    }
}

@Suite("NetRate")
struct NetRateTests {
    @Test func deltaHandlesWrap() {
        #expect(NetRate.delta(prev: 100, cur: 250) == 150)
        #expect(NetRate.delta(prev: UInt32.max - 9, cur: 5) == 15)
    }
    @Test func formatting() {
        #expect(NetRate.format(0) == "0 B/s")
        #expect(NetRate.format(850 * 1024) == "850 KB/s")
        #expect(NetRate.format(1.5 * 1_048_576) == "1.5 MB/s")
        #expect(NetRate.format(2_000_000, compact: true) == "1.9MB/s")
        #expect(NetRate.format(-3) == "0 B/s")
    }
}
