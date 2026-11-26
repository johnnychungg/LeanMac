// SPDX-License-Identifier: GPL-3.0-only
import Testing
import Foundation
@testable import LeanDomain

@Suite("ChargePolicy")
struct ChargePolicyTests {
    private func input(level: Int, limit: Int = 80, protection: Bool = true, topUp: Bool = false,
                       bypass: Bool = false, charging: Bool = false, amps: Int = 0) -> ChargeInput {
        ChargeInput(isProtectionEnabled: protection, isTopUpActive: topUp, level: level, limit: limit,
                    isBypassActive: bypass, isCharging: charging, amperage: amps)
    }

    @Test func locksAtLimitAndForcesWhenStillCharging() {
        let d = ChargePolicy.decide(input(level: 80, bypass: true, charging: true))
        #expect(d.inhibit && d.forceImmediate && d.status == .lockedAtLimit)
    }

    @Test func locksAtLimitWithoutForceWhenAlreadyBypassed() {
        let d = ChargePolicy.decide(input(level: 85, bypass: true, charging: false, amps: 10))
        #expect(d.inhibit && !d.forceImmediate)
    }

    @Test func forcesWhenBypassNotYetActive() {
        #expect(ChargePolicy.decide(input(level: 80, bypass: false)).forceImmediate)
    }

    @Test func forcesOnHighAmperage() {
        #expect(ChargePolicy.decide(input(level: 90, bypass: true, amps: 121)).forceImmediate)
    }

    @Test func rechargesBelowHysteresis() {
        let d = ChargePolicy.decide(input(level: 77, bypass: true))
        #expect(!d.inhibit && d.status == .rechargingToLimit)
        #expect(ChargePolicy.rechargeThreshold(limit: 80) == 77)
        #expect(ChargePolicy.rechargeThreshold(limit: 12) == 10)
    }

    @Test func hysteresisBandKeepsCurrentMode() {
        #expect(ChargePolicy.decide(input(level: 79, bypass: true)).status == .holdDirectAC)
        #expect(ChargePolicy.decide(input(level: 79, bypass: true)).inhibit)
        #expect(ChargePolicy.decide(input(level: 79, bypass: false)).status == .chargingToLimit)
        #expect(!ChargePolicy.decide(input(level: 79, bypass: false)).inhibit)
    }

    @Test func topUpOverridesLockAndFinishesAt100() {
        let mid = ChargePolicy.decide(input(level: 90, topUp: true))
        #expect(!mid.inhibit && !mid.finishTopUp && mid.status == .topUpInProgress)
        let full = ChargePolicy.decide(input(level: 100, topUp: true))
        #expect(full.finishTopUp && full.status == .topUpDone)
    }

    @Test func unprotectedAlwaysCharges() {
        let d = ChargePolicy.decide(input(level: 95, protection: false))
        #expect(!d.inhibit && d.status == .standardCharging)
    }
}

@Suite("CalibrationMachine")
struct CalibrationMachineTests {
    private func input(_ phase: CalibrationPhase, level: Int, plugged: Bool = true, helper: Bool = true,
                       disabled: Bool = false, inFlight: Bool = false, unsupported: Bool = false) -> CalibrationInput {
        CalibrationInput(phase: phase, level: level, isPluggedIn: plugged, isHelperInstalled: helper,
                         adapterDisabledByApp: disabled, adapterCommandInFlight: inFlight, dischargeUnsupported: unsupported)
    }

    @Test func dischargingPluggedEngagesAdapterDisableOnce() {
        let s = CalibrationMachine.step(input(.discharging, level: 60))
        #expect(s.phase == .discharging)
        #expect(s.actions.contains(.engageAdapterDisable))
        #expect(s.message == .drainingOnAdapter(level: 60))

        let again = CalibrationMachine.step(input(.discharging, level: 59, disabled: true))
        #expect(!again.actions.contains(.engageAdapterDisable))
        let inflight = CalibrationMachine.step(input(.discharging, level: 59, inFlight: true))
        #expect(!inflight.actions.contains(.engageAdapterDisable))
    }

    @Test func dischargingFallsBackToUnplugWhenUnsupported() {
        let plugged = CalibrationMachine.step(input(.discharging, level: 60, unsupported: true))
        #expect(!plugged.actions.contains(.engageAdapterDisable))
        #expect(plugged.message == .unplugAndDischarge(level: 60))
        let battery = CalibrationMachine.step(input(.discharging, level: 60, plugged: false, unsupported: true))
        #expect(battery.message == .dischargingOnBattery(level: 60))
    }

    @Test func noEngageWithoutHelper() {
        let s = CalibrationMachine.step(input(.discharging, level: 60, helper: false))
        #expect(!s.actions.contains(.engageAdapterDisable))
    }

    @Test func reaching20ReleasesAdapterAndStartsCharging() {
        let s = CalibrationMachine.step(input(.discharging, level: 20, plugged: false, disabled: true))
        #expect(s.phase == .charging)
        #expect(s.actions == [.releaseAdapterThenCharge, .notifyReached20(chargingContinuously: true)])
        let manualUnplugged = CalibrationMachine.step(input(.discharging, level: 19, plugged: false, disabled: false))
        #expect(manualUnplugged.actions.last == .notifyReached20(chargingContinuously: false))
    }

    @Test func chargingRestsAt100ThenWaits() {
        let mid = CalibrationMachine.step(input(.charging, level: 70))
        #expect(mid.phase == .charging && mid.actions == [.setChargingInhibited(false, force: false)])
        let full = CalibrationMachine.step(input(.charging, level: 100))
        #expect(full.phase == .resting)
        #expect(full.actions.contains(.startRestTimer(seconds: 900)) && full.actions.contains(.notifyReached100))
        let rest = CalibrationMachine.step(input(.resting, level: 100))
        #expect(rest.actions.isEmpty && rest.phase == .resting)
    }

    @Test func idleAndCompletedAreInert() {
        #expect(CalibrationMachine.step(input(.idle, level: 50)).actions.isEmpty)
        #expect(CalibrationMachine.step(input(.completed, level: 50)).phase == .completed)
    }

    @Test func dueDate() {
        let now = Date()
        let old = Calendar.current.date(byAdding: .day, value: -31, to: now)!
        #expect(CalibrationMachine.isDue(lastCalibration: old, intervalDays: 30, now: now))
        #expect(!CalibrationMachine.isDue(lastCalibration: now, intervalDays: 30, now: now))
        #expect(!CalibrationMachine.isDue(lastCalibration: nil, intervalDays: 30, now: now))
    }
}

@Suite("ByteFormat")
struct ByteFormatTests {
    @Test func formats() {
        #expect(ByteFormat.string(0) == "0 B")
        #expect(ByteFormat.string(2048) == "2 KB")
        #expect(ByteFormat.string(5 * 1024 * 1024) == "5.0 MB")
        #expect(ByteFormat.string(3 * 1024 * 1024 * 1024) == "3.00 GB")
        #expect(ByteFormat.string(-5) == "0 B")
    }
}
