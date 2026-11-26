// SPDX-License-Identifier: GPL-3.0-only
import Foundation

// MARK: - Charging decision while plugged in (pure, no I/O)

/// Input for deciding whether to inhibit charging (run directly from the adapter) or let it charge.
public struct ChargeInput: Equatable, Sendable {
    public var isProtectionEnabled: Bool
    public var isTopUpActive: Bool
    public var level: Int
    public var limit: Int
    public var isBypassActive: Bool
    public var isCharging: Bool
    public var amperage: Int

    public init(isProtectionEnabled: Bool, isTopUpActive: Bool, level: Int, limit: Int,
                isBypassActive: Bool, isCharging: Bool, amperage: Int) {
        self.isProtectionEnabled = isProtectionEnabled
        self.isTopUpActive = isTopUpActive
        self.level = level
        self.limit = limit
        self.isBypassActive = isBypassActive
        self.isCharging = isCharging
        self.amperage = amperage
    }
}

public enum ChargeStatus: Equatable, Sendable {
    case topUpInProgress
    case topUpDone
    case lockedAtLimit
    case rechargingToLimit
    case holdDirectAC
    case chargingToLimit
    case standardCharging
}

public struct ChargeDecision: Equatable, Sendable {
    /// true = inhibit charging (run from the adapter), false = allow charging
    public var inhibit: Bool
    /// Write the SMC immediately (skip the wait) because the battery is taking charge current above the limit
    public var forceImmediate: Bool
    public var status: ChargeStatus
    /// End the temporary full-charge (top-up) mode
    public var finishTopUp: Bool
}

public enum ChargePolicy {
    /// Hysteresis band: at or below `max(10, limit - 3)` charging resumes.
    public static func rechargeThreshold(limit: Int) -> Int { max(10, limit - 3) }

    public static func decide(_ i: ChargeInput) -> ChargeDecision {
        if i.isTopUpActive {
            let done = i.level >= 100
            return ChargeDecision(inhibit: false, forceImmediate: false,
                                  status: done ? .topUpDone : .topUpInProgress, finishTopUp: done)
        }
        guard i.isProtectionEnabled else {
            return ChargeDecision(inhibit: false, forceImmediate: false, status: .standardCharging, finishTopUp: false)
        }
        if i.level >= i.limit {
            let urgent = !i.isBypassActive || i.isCharging || i.amperage > 120
            return ChargeDecision(inhibit: true, forceImmediate: urgent, status: .lockedAtLimit, finishTopUp: false)
        }
        if i.level <= rechargeThreshold(limit: i.limit) {
            return ChargeDecision(inhibit: false, forceImmediate: false, status: .rechargingToLimit, finishTopUp: false)
        }
        if i.isBypassActive {
            return ChargeDecision(inhibit: true, forceImmediate: false, status: .holdDirectAC, finishTopUp: false)
        }
        return ChargeDecision(inhibit: false, forceImmediate: false, status: .chargingToLimit, finishTopUp: false)
    }
}

// MARK: - Battery calibration state machine (pure)

public enum CalibrationPhase: String, CaseIterable, Sendable {
    case idle, discharging, charging, resting, completed
}

public struct CalibrationInput: Equatable, Sendable {
    public var phase: CalibrationPhase
    public var level: Int
    public var isPluggedIn: Bool
    public var isHelperInstalled: Bool
    /// The adapter is cut through the SMC (discharging while plugged in)
    public var adapterDisabledByApp: Bool
    public var adapterCommandInFlight: Bool
    public var dischargeUnsupported: Bool

    public init(phase: CalibrationPhase, level: Int, isPluggedIn: Bool, isHelperInstalled: Bool,
                adapterDisabledByApp: Bool, adapterCommandInFlight: Bool, dischargeUnsupported: Bool) {
        self.phase = phase
        self.level = level
        self.isPluggedIn = isPluggedIn
        self.isHelperInstalled = isHelperInstalled
        self.adapterDisabledByApp = adapterDisabledByApp
        self.adapterCommandInFlight = adapterCommandInFlight
        self.dischargeUnsupported = dischargeUnsupported
    }
}

public enum CalibrationAction: Equatable, Sendable {
    /// Inhibit/allow charging according to the limit
    case setChargingInhibited(Bool, force: Bool)
    /// Cut the adapter to discharge the battery even though it is plugged in
    case engageAdapterDisable
    /// Release the adapter, then enable charging (after reaching 20%)
    case releaseAdapterThenCharge
    case notifyReached20(chargingContinuously: Bool)
    case notifyReached100
    case startRestTimer(seconds: Int)
}

public enum CalibrationMessage: Equatable, Sendable {
    case drainingOnAdapter(level: Int)       // discharging down to 20% (automatic)
    case unplugAndDischarge(level: Int)      // fallback mode: waiting for the user to unplug
    case dischargingOnBattery(level: Int)
    case charging(level: Int)
    case resting
    case none
}

public struct CalibrationStep: Equatable, Sendable {
    public var phase: CalibrationPhase
    public var actions: [CalibrationAction]
    public var message: CalibrationMessage
}

public enum CalibrationMachine {
    public static let dischargeTarget = 20
    public static let restSeconds = 900

    /// Next step of the calibration. `idle` and `completed` never change state on their own.
    public static func step(_ i: CalibrationInput) -> CalibrationStep {
        switch i.phase {
        case .discharging:
            if i.level <= dischargeTarget {
                return CalibrationStep(
                    phase: .charging,
                    actions: [.releaseAdapterThenCharge,
                              .notifyReached20(chargingContinuously: i.isPluggedIn || i.adapterDisabledByApp)],
                    message: .charging(level: i.level))
            }
            var actions: [CalibrationAction] = [.setChargingInhibited(true, force: false)]
            if !i.dischargeUnsupported && i.isHelperInstalled && !i.adapterDisabledByApp
                && !i.adapterCommandInFlight && i.isPluggedIn {
                actions.append(.engageAdapterDisable)
            }
            let message: CalibrationMessage
            if !i.dischargeUnsupported { message = .drainingOnAdapter(level: i.level) }
            else if i.isPluggedIn { message = .unplugAndDischarge(level: i.level) }
            else { message = .dischargingOnBattery(level: i.level) }
            return CalibrationStep(phase: .discharging, actions: actions, message: message)

        case .charging:
            if i.level >= 100 {
                return CalibrationStep(phase: .resting,
                                       actions: [.setChargingInhibited(false, force: false), .notifyReached100,
                                                 .startRestTimer(seconds: restSeconds)],
                                       message: .resting)
            }
            return CalibrationStep(phase: .charging, actions: [.setChargingInhibited(false, force: false)],
                                   message: .charging(level: i.level))

        case .resting:
            return CalibrationStep(phase: .resting, actions: [], message: .none)

        case .idle, .completed:
            return CalibrationStep(phase: i.phase, actions: [], message: .none)
        }
    }

    /// Whether a scheduled automatic calibration should start.
    public static func isDue(lastCalibration: Date?, intervalDays: Int, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard let last = lastCalibration else { return false }
        let days = calendar.dateComponents([.day], from: last, to: now).day ?? 0
        return days >= intervalDays
    }
}

// MARK: - Byte formatting

public enum ByteFormat {
    public static func string(_ bytes: Int64) -> String {
        let b = Double(max(0, bytes))
        if b >= 1024 * 1024 * 1024 { return String(format: "%.2f GB", b / (1024 * 1024 * 1024)) }
        if b >= 1024 * 1024 { return String(format: "%.1f MB", b / (1024 * 1024)) }
        if b >= 1024 { return String(format: "%.0f KB", b / 1024) }
        return "\(Int64(b)) B"
    }
}
