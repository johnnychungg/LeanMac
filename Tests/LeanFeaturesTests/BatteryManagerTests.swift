// SPDX-License-Identifier: GPL-3.0-only
import Testing
import Foundation
import LeanDomain
import LeanTestSupport
@testable import LeanFeatures

/// BatteryManager runs against fake ports: no battery, no SMC, no helper, no root.
@MainActor
@Suite("BatteryManager", .serialized)
struct BatteryManagerTests {
    private func snapshot(level: Int, plugged: Bool = true, charging: Bool = false) -> BatterySnapshot {
        var s = BatterySnapshot()
        s.currentCapacity = level
        s.maxCapacity = 100
        s.designCapacity = 5000
        s.nominalChargeCapacity = 4500
        s.cycleCount = 120
        s.isExternalConnected = plugged
        s.isCharging = charging
        s.voltage = 12.0
        s.amperageMilliamps = charging ? 1500 : 0
        s.temperatureCelsius = 31.5
        return s
    }

    private func waitUntil(_ timeout: TimeInterval = 3, _ condition: () -> Bool) async -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return condition()
    }

    @Test func readsASnapshotIntoPublishedState() {
        let reader = FakeBatteryReader(.snapshot(snapshot(level: 64, charging: true)))
        let manager = BatteryManager(services: .fake(reader: reader))
        manager.refreshBatteryInfo()
        #expect(manager.hasBattery)
        #expect(manager.currentLevel == 64)
        #expect(manager.isPluggedIn)
        #expect(manager.isCharging)
        #expect(manager.cycleCount == 120)
        #expect(manager.healthPercent == 90)
        #expect(abs(manager.temperature - 31.5) < 0.01)
        #expect(abs(manager.wattage - 18.0) < 0.01)
    }

    @Test func desktopMacReportsNoBattery() {
        let manager = BatteryManager(services: .fake(reader: FakeBatteryReader(.noBattery)))
        manager.refreshBatteryInfo()
        #expect(!manager.hasBattery)
        #expect(manager.isPluggedIn)
        #expect(manager.currentLevel == 100)
    }

    @Test func unavailableReadingKeepsPreviousValues() {
        let reader = FakeBatteryReader(.snapshot(snapshot(level: 42, plugged: false)))
        let manager = BatteryManager(services: .fake(reader: reader))
        manager.refreshBatteryInfo()
        reader.result = .unavailable
        manager.refreshBatteryInfo()
        #expect(manager.currentLevel == 42)
    }

    @Test func lockingChargeSendsOneValidatedHelperCommand() async {
        let helper = FakeHelperGateway()
        let manager = BatteryManager(services: .fake(
            reader: FakeBatteryReader(.snapshot(snapshot(level: 80, charging: true))), helper: helper))
        manager.refreshBatteryInfo()
        manager.isHelperInstalled = true
        manager.chargeLimit = 80
        manager.setChargingInhibited(true, forceImmediate: true)
        let want = HelperCommand.chargeOff(ChargeLimit(clamping: 80))
        let sent = await waitUntil { helper.commands.contains(want) }
        #expect(sent)
    }

    @Test func withoutHelperNothingIsWritten() async {
        let helper = FakeHelperGateway(isBinaryPresent: false)
        let manager = BatteryManager(services: .fake(
            reader: FakeBatteryReader(.snapshot(snapshot(level: 80, charging: true))), helper: helper))
        manager.refreshBatteryInfo()
        manager.isHelperInstalled = false
        manager.chargeLimit = 80
        manager.setChargingInhibited(true, forceImmediate: true)
        try? await Task.sleep(nanoseconds: 300_000_000)
        #expect(helper.commands.isEmpty)
    }

    @Test func helperStatusUsesVersionFromHelper() async {
        let helper = FakeHelperGateway()
        let manager = BatteryManager(services: .fake(helper: helper))
        var ready: Bool?
        manager.checkHelperStatus { ready = $0 }
        let done = await waitUntil { ready != nil }
        #expect(done)
        #expect(ready == true)
        #expect(manager.isHelperInstalled)
        #expect(helper.commands.contains(.version))
    }

    @Test func wrongHelperVersionMeansNotReady() async {
        let helper = FakeHelperGateway(reply: { _ in ("HELPER_VERSION:99", 0) })
        let manager = BatteryManager(services: .fake(helper: helper))
        var ready: Bool?
        manager.checkHelperStatus { ready = $0 }
        _ = await waitUntil { ready != nil }
        #expect(ready == false)
        #expect(!manager.isHelperInstalled)
    }

    @Test func missingHelperFileSkipsTheProbe() {
        let helper = FakeHelperGateway(isBinaryPresent: false)
        let manager = BatteryManager(services: .fake(helper: helper))
        var ready: Bool?
        manager.checkHelperStatus { ready = $0 }
        #expect(ready == false)
        #expect(helper.commands.isEmpty)
    }
}
