// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import LeanDomain
import Combine
import AppKit

// MARK: - Battery Manager (Hardware Care & Longevity)

@MainActor
public class BatteryManager: ObservableObject {
    public static let shared = BatteryManager(services: BatteryServices.current)

    // MARK: - Published State
    @Published public var hasBattery: Bool = true
    @Published public var currentLevel: Int = 100
    @Published public var maxCapacityPercent: Int = 100
    @Published public var nominalCapacity: Int = 0
    @Published public var designCapacity: Int = 0
    @Published public var healthPercent: Int = 100
    @Published public var exactHealthPercent: Double = 100.0
    @Published public var cycleCount: Int = 0
    @Published public var temperature: Double = 0.0      // in °C
    public var hasIOKitTemperature: Bool = true
    @Published public var voltage: Double = 0.0          // in Volts
    @Published public var amperage: Int = 0              // in mA
    @Published public var wattage: Double = 0.0          // in Watts
    @Published public var isPluggedIn: Bool = false
    @Published public var isCharging: Bool = false
    @Published public var isFullyCharged: Bool = false
    @Published public var timeRemaining: Int = 0         // in minutes
    @Published public var isBypassActive: Bool = false    // SMC CHTE = 1 (Running direct from AC)
    @Published public var isHelperInstalled: Bool = false
    @Published public var helperVersion: Int = 0
    /// An older helper answers, but this app needs a newer one (the installed copy is replaced by Install).
    public var isHelperOutdated: Bool { helperVersion > 0 && helperVersion != PrivilegedHelper.requiredVersion }
    @Published public var isInstallingHelper: Bool = false
    @Published public var statusMessage: String = tr("Checking...")
    @Published public var lastUpdated: Date = Date()

    // Extended Telemetry
    @Published public var adapterWatts: Int = 0          // e.g. 30W
    @Published public var adapterDescription: String = "" // e.g. "pd charger"
    @Published public var adapterSerial: String = ""
    @Published public var batterySerial: String = ""
    @Published public var gasGaugeChip: String = ""

    // User Settings (Stored in UserDefaults)
    @Published public var isProtectionEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(isProtectionEnabled, forKey: "battery_protection_enabled")
            updateAppNapProtection()
            if !isProtectionEnabled {
                self.isBypassActive = false
                setChargingInhibited(false, forceImmediate: true)
            }
            evaluatePowerManagement()
            syncPollingTimer()
        }
    }

    @Published public var chargeLimit: Int = 80 {
        didSet {
            UserDefaults.standard.set(chargeLimit, forKey: "battery_charge_limit")
            lastAppliedLimit = 0 // Force immediate SMC re-apply on limit change
            evaluatePowerManagement()
        }
    }

    @Published public var isTopUpActive: Bool = false {
        didSet {
            UserDefaults.standard.set(isTopUpActive, forKey: "battery_top_up_active")
            updateAppNapProtection()
            lastAppliedInhibitState = nil
            evaluatePowerManagement()
            syncPollingTimer()
        }
    }

    @Published public var isTempAlertEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(isTempAlertEnabled, forKey: "battery_temp_alert_enabled")
        }
    }

    @Published public var isSmartAlertsEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(isSmartAlertsEnabled, forKey: "battery_smart_alerts_enabled")
        }
    }

    // Hardware Tab Selection (0: Power & Battery, 1: Sleep Guard, 2: Calibration)
    @Published public var selectedHardwareTab: Int = 0

    // Sleep Guard Settings & State
    @Published public var isSleepGuardEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(isSleepGuardEnabled, forKey: "battery_sleep_guard_enabled")
        }
    }

    @Published public var sleepGuardTurnOffBluetooth: Bool = true {
        didSet {
            UserDefaults.standard.set(sleepGuardTurnOffBluetooth, forKey: "battery_sleep_guard_bt")
        }
    }

    /// What happened during the last sleep. Only numbers are stored; the sentence is built at display time so it
    /// always follows the current language (a stored sentence would stay in the language it was written in).
    public struct SleepRecord: Codable, Equatable, Sendable {
        public var seconds: Int
        public var from: Int
        public var to: Int
    }
    @Published public var lastSleepRecord: SleepRecord?

    public var lastSleepReport: String {
        guard let r = lastSleepRecord else { return "" }
        return Self.sleepSummary(r)
    }

    static func sleepSummary(_ r: SleepRecord) -> String {
        let hours = r.seconds / 3600
        let mins = (r.seconds % 3600) / 60
        return tr("Slept \(hours)h\(mins)m • \(sleepDrainText(from: r.from, to: r.to))")
    }

    static func sleepDrainText(from: Int, to: Int) -> String {
        let delta = to - from
        return delta >= 0 ? tr("Battery drain: 0%") : tr("Battery drain: \(abs(delta))% (\(from)% → \(to)%)")
    }

    private var sleepDate: Date? = nil
    private var sleepBatteryLevel: Int = 0
    /// Persisted in UserDefaults so that if the app dies while the Mac sleeps, Bluetooth is still turned back on at the next launch.
    private var wasBluetoothTurnedOffBySleepGuard: Bool {
        get { UserDefaults.standard.bool(forKey: "battery_bt_off_by_guard") }
        set { UserDefaults.standard.set(newValue, forKey: "battery_bt_off_by_guard") }
    }

    /// Turns Bluetooth back on if Sleep Guard itself turned it off. Safe to call repeatedly.
    public func restoreBluetoothIfNeeded() {
        guard wasBluetoothTurnedOffBySleepGuard else { return }
        if bluetooth.isAvailable {
            bluetooth.isPowerOn = true
        }
        wasBluetoothTurnedOffBySleepGuard = false
    }

    // Calibration State Machine
    public enum CalibrationState: String, CaseIterable {
        case idle = "idle"
        case discharging = "discharging"
        case charging = "charging"
        case resting = "resting"
        case completed = "completed"
    }

    @Published public var calibrationState: CalibrationState = .idle
    @Published public var calibrationMessage: String = ""
    /// The adapter is cut through the SMC (CHIE) to discharge the battery while plugged in.
    private var adapterDisabledByApp = false
    private var adapterCommandInFlight = false
    private var dischargeUnsupported = false
    private var restingTimer: Timer?

    // Auto-Scheduled Calibration
    @Published public var isAutoCalibrationEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(isAutoCalibrationEnabled, forKey: "battery_auto_calibration_enabled")
        }
    }

    @Published public var calibrationIntervalDays: Int = 30 {
        didSet {
            UserDefaults.standard.set(calibrationIntervalDays, forKey: "battery_calibration_interval_days")
        }
    }

    @Published public var lastCalibrationDate: Date? = nil {
        didSet {
            if let date = lastCalibrationDate {
                UserDefaults.standard.set(date.timeIntervalSince1970, forKey: "battery_last_calibration_timestamp")
            }
        }
    }

    public var nextScheduledCalibrationDate: Date {
        let base = lastCalibrationDate ?? Date()
        return Calendar.current.date(byAdding: .day, value: calibrationIntervalDays, to: base) ?? Date()
    }

    public var daysRemainingUntilCalibration: Int {
        let now = Date()
        let next = nextScheduledCalibrationDate
        let diff = Calendar.current.dateComponents([.day], from: now, to: next).day ?? 0
        return max(0, diff)
    }

    public var tempAlertThreshold: Double = 38.0 // Warning at 38°C
    private var lastTempAlertDate: Date? = nil
    private var lastExtDisplayAlertDate: Date? = nil
    private var lastLowBatteryAlertLevel: Int? = nil
    private var hasAlertedBypassThisSession: Bool = false

    private var timer: Timer?
    private var timerInterval: TimeInterval = 0
    private var isPopoverVisible: Bool = false
    private let services: BatteryServices
    private nonisolated var helper: HelperGateway { services.helper }
    private let bluetooth: BluetoothControlling
    private let ceiling: ChargeCeilingControlling
    private let powerObserver: PowerSourceObserving
    private var appNapActivityToken: NSObjectProtocol?
    private var lastAppliedInhibitState: Bool? = nil
    private var lastAppliedLimit: Int = 0
    private var lastSMCWriteDate: Date = .distantPast
    private var consecutiveChargeSpikes: Int = 0

    package init(services: BatteryServices) {
        self.services = services
        self.bluetooth = services.bluetoothFactory()
        self.ceiling = services.ceilingFactory()
        self.powerObserver = services.powerSourceObserverFactory()
        // Load preferences
        if UserDefaults.standard.object(forKey: "battery_protection_enabled") != nil {
            self.isProtectionEnabled = UserDefaults.standard.bool(forKey: "battery_protection_enabled")
        } else {
            self.isProtectionEnabled = false
        }

        if UserDefaults.standard.object(forKey: "battery_temp_alert_enabled") != nil {
            self.isTempAlertEnabled = UserDefaults.standard.bool(forKey: "battery_temp_alert_enabled")
        } else {
            self.isTempAlertEnabled = true
        }

        if UserDefaults.standard.object(forKey: "battery_smart_alerts_enabled") != nil {
            self.isSmartAlertsEnabled = UserDefaults.standard.bool(forKey: "battery_smart_alerts_enabled")
        } else {
            self.isSmartAlertsEnabled = true
        }

        if UserDefaults.standard.object(forKey: "battery_sleep_guard_enabled") != nil {
            self.isSleepGuardEnabled = UserDefaults.standard.bool(forKey: "battery_sleep_guard_enabled")
        } else {
            self.isSleepGuardEnabled = true
        }

        if UserDefaults.standard.object(forKey: "battery_sleep_guard_bt") != nil {
            self.sleepGuardTurnOffBluetooth = UserDefaults.standard.bool(forKey: "battery_sleep_guard_bt")
        } else {
            self.sleepGuardTurnOffBluetooth = true
        }

        // The old key held a finished sentence in whatever language was active at the time; drop it.
        UserDefaults.standard.removeObject(forKey: "battery_last_sleep_report")
        self.lastSleepRecord = UserDefaults.standard.data(forKey: "battery_last_sleep_record")
            .flatMap { try? JSONDecoder().decode(SleepRecord.self, from: $0) }

        let savedLimit = UserDefaults.standard.integer(forKey: "battery_charge_limit")
        if savedLimit >= 50 && savedLimit <= 100 {
            self.chargeLimit = savedLimit
        } else {
            self.chargeLimit = 80
        }

        self.isTopUpActive = UserDefaults.standard.bool(forKey: "battery_top_up_active")

        // Off by default: automatic calibration manipulates charging/discharging and has little benefit on modern batteries.
        self.isAutoCalibrationEnabled = UserDefaults.standard.bool(forKey: "battery_auto_calibration_enabled")

        let savedInterval = UserDefaults.standard.integer(forKey: "battery_calibration_interval_days")
        if savedInterval >= 15 && savedInterval <= 120 {
            self.calibrationIntervalDays = savedInterval
        } else {
            self.calibrationIntervalDays = 30
        }

        let lastCalTimestamp = UserDefaults.standard.double(forKey: "battery_last_calibration_timestamp")
        if lastCalTimestamp > 0 {
            self.lastCalibrationDate = Date(timeIntervalSince1970: lastCalTimestamp)
        } else {
            let now = Date()
            self.lastCalibrationDate = now
            UserDefaults.standard.set(now.timeIntervalSince1970, forKey: "battery_last_calibration_timestamp")
        }

        // Setup Sleep & Real-Time IOPowerSources Observers
        setupSleepObservers()
        setupPowerSourceNotifications()
        updateAppNapProtection()

        // Initial check
        checkHelperStatus()
        refreshBatteryInfo()
        checkSMCBypassStatus()
        evaluatePowerManagement()

        // Start background polling timer
        startPolling()
    }

    deinit {
        timer?.invalidate()
        restingTimer?.invalidate()
        if let token = appNapActivityToken {
            ProcessInfo.processInfo.endActivity(token)
        }
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    // MARK: - Real-Time Hardware Power Notifications & App Nap Prevention

    private func setupPowerSourceNotifications() {
        powerObserver.start { [weak self] in
            guard let self else { return }
            self.refreshBatteryInfo()
            self.checkSMCBypassStatus()
            self.evaluatePowerManagement()
            self.updateAppNapProtection()
            self.syncPollingTimer()
        }
    }

    /// System is asleep: stop timers and the App Nap token so Dark Wake / Power Nap are not prolonged by LeanMac.
    private var systemAsleep = false

    /// Every command to the privileged helper goes through this one serial queue so a charge-on can never
    /// overtake a charge-off. Work on it must never wait for the main thread (`queue.sync` is used from main).
    private let helperQueue = DispatchQueue(label: "com.local.leanmac.helper", qos: .utility)

    private func updateAppNapProtection() {
        // Only hold the App Nap token while plugged in AND charging up to the limit or calibrating.
        // On battery (!isPluggedIn) or once bypass is locked (isBypassActive),
        // release the token at once so macOS can coalesce timers and save energy.
        let needsActiveMonitoring = !systemAsleep && (calibrationState != .idle ||
            (isPluggedIn && ((isProtectionEnabled && !isBypassActive) || isTopUpActive)))
        if needsActiveMonitoring {
            if appNapActivityToken == nil {
                appNapActivityToken = ProcessInfo.processInfo.beginActivity(
                    options: .userInitiatedAllowingIdleSystemSleep,
                    reason: "LeanMac Active Charging Limiter"
                )
            }
        } else if let token = appNapActivityToken {
            ProcessInfo.processInfo.endActivity(token)
            appNapActivityToken = nil
        }
    }

    // MARK: - Sleep Guard Lifecycle

    private func setupSleepObservers() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleWillSleep(_:)),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleDidWake(_:)),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    @objc private func handleWillSleep(_ notification: Notification) {
        // 0. Stop all background activity while asleep (after the charge limit below has been written)
        defer {
            systemAsleep = true
            syncPollingTimer()
            updateAppNapProtection()
        }
        // 0b. Never sleep with the adapter cut by a calibration discharge; wake re-evaluates and re-engages it.
        if adapterDisabledByApp && isHelperInstalled {
            adapterDisabledByApp = false
            _ = helperQueue.sync { helper.run(.dischargeOff) }
        }
        // 1. Always enforce battery charge limit before sleep (even if Sleep Guard BT feature is off)
        if isProtectionEnabled && !isTopUpActive && calibrationState == .idle {
            if ceiling.isSupported && chargeLimit >= 80 {
                _ = ceiling.setLimit(chargeLimit)
            }
            if isHelperInstalled {
                if currentLevel >= chargeLimit {
                    _ = helperQueue.sync { helper.run(.chargeOff(ChargeLimit(clamping: chargeLimit))) }
                } else {
                    _ = helperQueue.sync { helper.run(.chargeOn(ChargeLimit(clamping: chargeLimit))) }
                }
            }
        }

        // 2. Sleep Guard Bluetooth & drain tracking
        guard isSleepGuardEnabled else { return }
        self.sleepDate = Date()
        self.sleepBatteryLevel = self.currentLevel

        // Turn off Bluetooth if configured to prevent phantom Dark Wake drain
        if sleepGuardTurnOffBluetooth && bluetooth.isAvailable && bluetooth.isPowerOn {
            self.wasBluetoothTurnedOffBySleepGuard = true
            bluetooth.isPowerOn = false
        }
    }

    @objc private func handleDidWake(_ notification: Notification) {
        systemAsleep = false
        syncPollingTimer()
        // 1. Always refresh battery state and re-enforce SMC limit immediately upon wake
        lastAppliedInhibitState = nil
        refreshBatteryInfo()
        checkSMCBypassStatus()
        evaluatePowerManagement()

        // 2. Sleep Guard Bluetooth restoration & report (always turn it back on, even if the guard was just switched off)
        restoreBluetoothIfNeeded()
        guard isSleepGuardEnabled else { return }

        // Calculate sleep duration & battery delta
        if let sDate = sleepDate {
            let elapsed = Date().timeIntervalSince(sDate)
            let hours = Int(elapsed) / 3600
            let mins = (Int(elapsed) % 3600) / 60
            let record = SleepRecord(seconds: Int(elapsed), from: sleepBatteryLevel, to: currentLevel)
            let drainText = Self.sleepDrainText(from: record.from, to: record.to)
            self.lastSleepRecord = record
            UserDefaults.standard.set(try? JSONEncoder().encode(record), forKey: "battery_last_sleep_record")

            if isSmartAlertsEnabled {
                sendNotification(
                    title: tr("Sleep Guard: sleep report"),
                    body: tr("The Mac slept for \(hours)h\(mins)m. \(drainText).")
                )
            }
            self.sleepDate = nil
        }
    }

    // MARK: - Polling Timer (Dynamic & Energy-Aware)

    public func setPopoverVisible(_ visible: Bool) {
        isPopoverVisible = visible
        if visible {
            offerHelperUpdateIfNeeded()
            refreshBatteryInfo()
            checkSMCBypassStatus()
            evaluatePowerManagement()
            updateAppNapProtection()
        }
        syncPollingTimer()
    }

    public func startPolling() {
        syncPollingTimer()
    }

    private func syncPollingTimer() {
        let desiredInterval: TimeInterval
        if !hasBattery {
            desiredInterval = 0
        } else if isPopoverVisible {
            desiredInterval = 3.5
        } else if calibrationState != .idle || (isPluggedIn && (isProtectionEnabled || isTopUpActive)) {
            // With the popover closed and the charger plugged in, only check in-process every 20 s (no child process);
            // plug/unplug/percentage changes are already reported instantly by IOPSNotification.
            desiredInterval = 20.0
        } else {
            // On battery or with protection off while the popover is closed: no timer wakeups, relying entirely on IOPSNotification + didWake.
            desiredInterval = 0
        }

        if desiredInterval <= 0 || systemAsleep {
            timer?.invalidate()
            timer = nil
            timerInterval = 0
            return
        }

        guard timer == nil || timerInterval != desiredInterval else { return }
        timer?.invalidate()
        timerInterval = desiredInterval
        let t = Timer(timeInterval: desiredInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.refreshBatteryInfo()
                self.checkSMCBypassStatus()
                self.checkAutoCalibrationSchedule()
                self.evaluatePowerManagement()
                self.updateAppNapProtection()
                self.syncPollingTimer()
            }
        }
        t.tolerance = desiredInterval >= 15.0 ? 4.0 : 0.5
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func setIfChanged<T: Equatable>(_ target: inout T, _ newValue: T) {
        if target != newValue {
            target = newValue
        }
    }

    // MARK: - IOKit Battery Status Query

    public func refreshBatteryInfo() {
        let result = services.reader.read()
        switch result {
        case .noBattery:
            // Desktop Macs (Mac mini, Mac Studio, iMac, Mac Pro) have no internal battery.
            setIfChanged(&self.hasBattery, false)
            setIfChanged(&self.isPluggedIn, true)
            setIfChanged(&self.isCharging, false)
            setIfChanged(&self.isFullyCharged, true)
            setIfChanged(&self.currentLevel, 100)
            setIfChanged(&self.statusMessage, tr("Direct AC Power (Desktop Mac)"))
            syncPollingTimer()
            updateAppNapProtection()
            return
        case .unavailable:
            setIfChanged(&self.hasBattery, true)
            return
        case .snapshot(let reading):
            apply(reading)
        }
    }

    private func apply(_ reading: BatterySnapshot) {
        setIfChanged(&self.hasBattery, true)

        setIfChanged(&self.currentLevel, reading.currentCapacity ?? self.currentLevel)
        setIfChanged(&self.maxCapacityPercent, reading.maxCapacity ?? 100)
        setIfChanged(&self.nominalCapacity, reading.nominalChargeCapacity ?? self.nominalCapacity)
        setIfChanged(&self.designCapacity, reading.designCapacity ?? self.designCapacity)
        setIfChanged(&self.cycleCount, reading.cycleCount ?? self.cycleCount)
        let rawCharging = reading.isCharging
        setIfChanged(&self.isPluggedIn, reading.isExternalConnected)
        setIfChanged(&self.isFullyCharged, reading.isFullyCharged)
        setIfChanged(&self.timeRemaining, reading.timeRemaining)

        // If not physically plugged in or protection is disabled, bypass cannot be active
        if !self.isPluggedIn || !self.isProtectionEnabled {
            setIfChanged(&self.isBypassActive, false)
        }

        // Newer macOS no longer reports "Temperature" here: ThermalManager (SMC/HID) supplies it when missing.
        self.hasIOKitTemperature = reading.temperatureCelsius != nil
        if let t = reading.temperatureCelsius, abs(self.temperature - t) >= 0.05 { self.temperature = t }
        if let v = reading.voltage, abs(self.voltage - v) >= 0.01 { self.voltage = v }

        // Signed: negative = discharging, positive = charging, 0 = bypass
        if let amps = reading.amperageMilliamps {
            setIfChanged(&self.amperage, amps)
        }

        // Live Wattage = Voltage (V) * abs(Amperage (A))
        let newWattage = (self.voltage * Double(abs(self.amperage))) / 1000.0
        if abs(self.wattage - newWattage) >= 0.05 {
            self.wattage = newWattage
        }

        // Responsive charging detection: even if macOS IsCharging flag is delayed, positive current means charging
        let nextCharging = rawCharging || (self.isPluggedIn && self.amperage > 50)
        setIfChanged(&self.isCharging, nextCharging)

        // Adapter details (only valid when plugged in)
        if self.isPluggedIn {
            if let watts = reading.adapterWatts {
                setIfChanged(&self.adapterWatts, watts)
                setIfChanged(&self.adapterDescription, reading.adapterDescription ?? "USB-C PD")
                setIfChanged(&self.adapterSerial, reading.adapterSerial ?? "")
            }
        } else {
            setIfChanged(&self.adapterWatts, 0)
            setIfChanged(&self.adapterDescription, "")
            setIfChanged(&self.adapterSerial, "")
        }

        setIfChanged(&self.batterySerial, reading.serial ?? self.batterySerial)
        setIfChanged(&self.gasGaugeChip, reading.deviceName ?? self.gasGaugeChip)

        if self.designCapacity > 0 && self.nominalCapacity > 0 {
            let ratio = Double(self.nominalCapacity) / Double(self.designCapacity) * 100.0
            if abs(self.exactHealthPercent - ratio) >= 0.01 {
                self.exactHealthPercent = ratio
            }
            setIfChanged(&self.healthPercent, min(100, Int(round(ratio))))
        }

        if isPopoverVisible {
            self.lastUpdated = Date()
        }
        checkTemperatureAlert()
        checkSmartSafetyAlerts()
    }

    // MARK: - Smart Safety & Anti-Wear Alerts

    private func checkSmartSafetyAlerts() {
        guard isSmartAlertsEnabled && hasBattery else { return }

        // 1. Alert: External display active but running on battery (not plugged in)
        let hasExtDisplay = DisplayManager.shared.monitors.contains(where: { !$0.isBuiltIn && $0.isConnected })
        if hasExtDisplay && !isPluggedIn {
            let now = Date()
            if lastExtDisplayAlertDate == nil || now.timeIntervalSince(lastExtDisplayAlertDate!) > 900 { // 15 mins
                lastExtDisplayAlertDate = now
                sendNotification(
                    title: tr("External display in use on battery"),
                    body: tr("An external display drains the battery faster and heats the Mac. Plug in to run on AC power.")
                )
            }
        } else if isPluggedIn {
            lastExtDisplayAlertDate = nil
        }

        // 2. Alert: Low battery warning to prevent deep discharge (<20% and <10%)
        if !isPluggedIn {
            if currentLevel <= 10 {
                if lastLowBatteryAlertLevel != 10 {
                    lastLowBatteryAlertLevel = 10
                    sendNotification(
                        title: tr("Battery at 10%"),
                        body: tr("Plug in now to avoid an abrupt shutdown that can damage the battery.")
                    )
                }
            } else if currentLevel <= 20 {
                if lastLowBatteryAlertLevel != 20 {
                    lastLowBatteryAlertLevel = 20
                    sendNotification(
                        title: tr("Low battery (20%)"),
                        body: tr("Plug in to avoid deep discharge that wears the battery.")
                    )
                }
            } else {
                lastLowBatteryAlertLevel = nil
            }
        } else {
            lastLowBatteryAlertLevel = nil
        }

        // 3. Informational Alert: Reached limit with AC Bypass active
        if isPluggedIn && isBypassActive && currentLevel >= chargeLimit {
            if !hasAlertedBypassThisSession {
                hasAlertedBypassThisSession = true
                sendNotification(
                    title: tr("Charge locked at \(chargeLimit)%"),
                    body: tr("The battery stopped charging; the Mac runs directly on AC power to protect it.")
                )
            }
        } else if !isPluggedIn || currentLevel < (chargeLimit - 4) {
            hasAlertedBypassThisSession = false
        }
    }

    // MARK: - Temperature Safety Alerts

    private func checkTemperatureAlert() {
        guard isTempAlertEnabled && temperature >= tempAlertThreshold else { return }

        let now = Date()
        if let last = lastTempAlertDate, now.timeIntervalSince(last) < 600 {
            return // Wait at least 10 minutes between alerts
        }
        lastTempAlertDate = now

        let tempStr = String(format: "%.1f°C", temperature)
        sendNotification(
            title: tr("Battery is hot (\(tempStr))"),
            body: tr("Give the Mac some airflow or pause heavy tasks. See Hardware → Monitor for details.")
        )
    }

    private func sendNotification(title: String, body: String) {
        Notifier.send(title: title, body: body)
    }

    /// Reads the SMC charge-lock state directly in-process through IOKit AppleSMC (no child process, no sudo).
    /// Returns `nil` when the device has no SMC key at all (then fall back to PowerUI MCL).
    private func readHardwareBypassInProcess() -> Bool? {
        SMCChargeState.isBypassed(services.smc)
    }

    public func checkSMCBypassStatus() {
        // If protection is disabled by user, bypass is NEVER active
        guard isProtectionEnabled else {
            setIfChanged(&self.isBypassActive, false)
            return
        }

        // 1. Read directly from IOKit AppleSMC in-process (no child process, no sudo)
        if let smcBypassed = readHardwareBypassInProcess() {
            // If the level is at/over the limit while the charge current stays above 120 mA, the hardware was reset (MagSafe/USB-C PD replugged)
            if currentLevel >= chargeLimit && amperage > 120 {
                consecutiveChargeSpikes += 1
            } else {
                consecutiveChargeSpikes = 0
            }
            let activelyChargingPastLimit = isPluggedIn && (currentLevel >= chargeLimit) && (isCharging || consecutiveChargeSpikes >= 2)
            setIfChanged(&self.isBypassActive, smcBypassed && isPluggedIn && !activelyChargingPastLimit)
            return
        }

        // 2. Fallback when SMC register is unavailable (Native PowerUI only)
        if ceiling.isSupported && chargeLimit >= 80 {
            let enabled = ceiling.isCurrentlyEnabled()
            let limit = ceiling.currentLimit()
            if enabled && limit <= self.chargeLimit && self.currentLevel >= self.chargeLimit && !self.isCharging {
                setIfChanged(&self.isBypassActive, self.isPluggedIn)
                return
            }
        }
        setIfChanged(&self.isBypassActive, false)
    }

    // MARK: - Power & Limiter Evaluation

    public func evaluatePowerManagement() {
        guard hasBattery else {
            setIfChanged(&self.isBypassActive, false)
            setIfChanged(&statusMessage, tr("Direct AC Power (Desktop Mac)"))
            return
        }
        guard isHelperInstalled || (ceiling.isSupported && chargeLimit >= 80) else {
            setIfChanged(&statusMessage, tr("Permission needed for SMC power protection"))
            return
        }

        // 1. Calibration (the decision lives in CalibrationMachine; here we only execute the effects)
        if calibrationState != .idle && calibrationState != .completed {
            let step = CalibrationMachine.step(CalibrationInput(
                phase: CalibrationPhase(rawValue: calibrationState.rawValue) ?? .idle,
                level: currentLevel, isPluggedIn: isPluggedIn, isHelperInstalled: isHelperInstalled,
                adapterDisabledByApp: adapterDisabledByApp, adapterCommandInFlight: adapterCommandInFlight,
                dischargeUnsupported: dischargeUnsupported))
            apply(step)
            return
        }

        // 2. Normal power state
        if !isPluggedIn {
            setIfChanged(&self.isBypassActive, false)
            // Keep firmware ceiling armed even while on battery if protection is enabled,
            // so plugging in while asleep won't overshoot the limit
            if isProtectionEnabled && !isTopUpActive && ceiling.isSupported && chargeLimit >= 80 {
                if !ceiling.isCurrentlyEnabled() || ceiling.currentLimit() != chargeLimit {
                    _ = ceiling.setLimit(chargeLimit)
                }
            }
            setIfChanged(&statusMessage, tr("On battery (\(currentLevel)%)"))
            return
        }

        // Plugged in: pure decision from ChargePolicy
        let d = ChargePolicy.decide(ChargeInput(
            isProtectionEnabled: isProtectionEnabled, isTopUpActive: isTopUpActive, level: currentLevel,
            limit: chargeLimit, isBypassActive: isBypassActive, isCharging: isCharging, amperage: amperage))
        setChargingInhibited(d.inhibit, forceImmediate: d.forceImmediate)
        if d.finishTopUp { isTopUpActive = false }
        let lvl = currentLevel, lim = chargeLimit
        switch d.status {
        case .topUpDone: setIfChanged(&statusMessage, tr("Fully charged 100%"))
        case .topUpInProgress: setIfChanged(&statusMessage, tr("Temporary top-up (\(lvl)%)"))
        case .lockedAtLimit: setIfChanged(&statusMessage, tr("Direct AC Power (Locked at \(lim)% to protect battery)"))
        case .rechargingToLimit: setIfChanged(&statusMessage, tr("Recharging up to \(lim)% (\(lvl)%)"))
        case .holdDirectAC: setIfChanged(&statusMessage, tr("Direct AC Power (\(lvl)%)"))
        case .chargingToLimit: setIfChanged(&statusMessage, tr("Charging to \(lim)% (\(lvl)%)"))
        case .standardCharging:
            setIfChanged(&statusMessage, isFullyCharged ? tr("Fully charged 100%") : tr("Standard charging (\(lvl)%)"))
        }
    }

    /// Executes the effects requested by CalibrationMachine.
    private func apply(_ step: CalibrationStep) {
        if let phase = CalibrationState(rawValue: step.phase.rawValue) { calibrationState = phase }
        let lvl = currentLevel
        switch step.message {
        case .drainingOnAdapter: calibrationMessage = tr("Step 1/3: Discharging battery to 20% (Currently: \(lvl)%)")
        case .unplugAndDischarge: calibrationMessage = tr("Step 1/3: Unplug and discharge to 20% (Currently: \(lvl)%)")
        case .dischargingOnBattery: calibrationMessage = tr("Step 1/3: Discharging battery to 20% (Currently: \(lvl)%)")
        case .charging: calibrationMessage = tr("Step 2/3: Charging to 100% (Currently: \(lvl)%)")
        case .resting: calibrationMessage = tr("Step 3/3: Holding 100% for 15 min to stabilize chemistry...")
        case .none: break
        }
        for action in step.actions {
            switch action {
            case .setChargingInhibited(let inhibit, let force):
                setChargingInhibited(inhibit, forceImmediate: force)
            case .engageAdapterDisable:
                engageAdapterDisable()
            case .releaseAdapterThenCharge:
                releaseAdapter { [weak self] in self?.setChargingInhibited(false, forceImmediate: true) }
            case .notifyReached20(let continuous):
                sendNotification(
                    title: tr("Calibration: reached 20%"),
                    body: continuous
                        ? tr("Now charging to 100%.")
                        : tr("Plug in the charger so LeanMac can charge to 100%, then lock back at \(chargeLimit)%."))
            case .notifyReached100:
                sendNotification(
                    title: tr("Calibration: reached 100%"),
                    body: tr("Holding 100% for 15 minutes."))
            case .startRestTimer(let seconds):
                restingTimer?.invalidate()
                restingTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(seconds), repeats: false) { [weak self] _ in
                    Task { @MainActor [weak self] in self?.completeCalibration() }
                }
            }
        }
    }

    // MARK: - SMC Charging Inhibit Control

    public func setChargingInhibited(_ inhibit: Bool, forceImmediate: Bool = false) {
        let now = Date()
        let cooldownElapsed = now.timeIntervalSince(lastSMCWriteDate) >= 10.0
        let stateOrLimitChanged = (lastAppliedInhibitState != inhibit) || (lastAppliedLimit != chargeLimit)
        let shouldWriteSMC = stateOrLimitChanged || (forceImmediate && cooldownElapsed)

        if !inhibit {
            setIfChanged(&self.isBypassActive, false)
            // Determine whether we are recharging up to `chargeLimit` (keep ceiling armed!)
            // vs. completely unlocking to 100% (Protection OFF, Top-Up 100%, or Calibration charging)
            let keepCeilingArmed = isProtectionEnabled && !isTopUpActive && (calibrationState == .idle)

            if keepCeilingArmed {
                // Keep firmware ceiling (CHLT / PowerUI) armed at `chargeLimit` so Mac stops at `chargeLimit` even during Sleep!
                if ceiling.isSupported && chargeLimit >= 80 {
                    if stateOrLimitChanged || !ceiling.isCurrentlyEnabled() || ceiling.currentLimit() != chargeLimit {
                        _ = ceiling.setLimit(chargeLimit)
                    }
                }
            } else {
                // Full 100% unlock: disable native macOS PowerUI MCL
                if ceiling.isSupported {
                    if stateOrLimitChanged || ceiling.isCurrentlyEnabled() {
                        _ = ceiling.disable()
                    }
                }
            }

            // Only run the sudo helper right after a state change / unlock, or when the SMC read shows the switch is still closed
            let hardwareStillInhibited = (readHardwareBypassInProcess() == true)
            if isHelperInstalled && (shouldWriteSMC || (hardwareStillInhibited && cooldownElapsed)) {
                lastAppliedInhibitState = false
                lastAppliedLimit = chargeLimit
                lastSMCWriteDate = now
                let targetCeiling = keepCeilingArmed ? chargeLimit : 100
                helperQueue.async {
                    let (_, _) = self.helper.run(.chargeOn(ChargeLimit(clamping: targetCeiling)))
                    DispatchQueue.main.async {
                        self.setIfChanged(&self.isBypassActive, false)
                        self.refreshBatteryInfo()
                    }
                }
            }
            return
        }

        // Inhibit = true (Lock charging at specified limit & switch to Direct AC Power)
        // Layer 1: Arm Native PowerUI / CHLT firmware ceiling (for macOS 15+ / sleep persistence)
        var nativeSuccess = false
        if ceiling.isSupported && chargeLimit >= 80 {
            if !ceiling.isCurrentlyEnabled() || ceiling.currentLimit() != chargeLimit {
                nativeSuccess = ceiling.setLimit(chargeLimit)
            } else {
                nativeSuccess = true
            }
        }

        // Layer 2: ALWAYS enforce SMC hardware cut-off switches (CHTE / CH0B / bfF0 / BCLM) via root helper
        // when state/limit changes or in-process read detects bypass is missing / still charging (0 background spam when already locked!).
        if isHelperInstalled {
            let needsLockWrite = shouldWriteSMC || (!isBypassActive && cooldownElapsed) || ((isCharging || amperage > 120) && cooldownElapsed)
            if needsLockWrite {
                lastAppliedInhibitState = true
                lastAppliedLimit = chargeLimit
                lastSMCWriteDate = now
                let limitToLock = chargeLimit
                let command = HelperCommand.chargeOff(ChargeLimit(clamping: limitToLock))
                helperQueue.async {
                    let (out, code) = self.helper.run(command)
                    DispatchQueue.main.async {
                        if code == 0 {
                            self.setIfChanged(&self.isBypassActive, self.isPluggedIn)
                            self.updateAppNapProtection()
                        } else if !nativeSuccess {
                            appLog("⚠️ setChargingInhibited(true) failed with code \(code): \(out)")
                        }
                    }
                }
            }
        } else if nativeSuccess {
            setIfChanged(&self.isBypassActive, self.isPluggedIn)
        }
    }

    /// Called synchronously on quit (`applicationWillTerminate`) to release the hardware switches `CHTE`/`CH0B`,
    /// so the Mac is not left with charging cut after LeanMac quits, while keeping the `CHLT` ceiling if protection is on.
    public func restoreOnTerminateSync() {
        restoreBluetoothIfNeeded()
        guard hasBattery else { return }
        if adapterDisabledByApp {
            adapterDisabledByApp = false
            _ = helperQueue.sync { helper.run(.dischargeOff) }
        }
        let keepCeiling = isProtectionEnabled && !isTopUpActive && (calibrationState == .idle)
        if keepCeiling {
            if ceiling.isSupported && chargeLimit >= 80 {
                _ = ceiling.setLimit(chargeLimit)
            }
            if isHelperInstalled {
                _ = helperQueue.sync { helper.run(.chargeOn(ChargeLimit(clamping: chargeLimit))) }
            }
        } else {
            if ceiling.isSupported {
                _ = ceiling.disable()
            }
            if isHelperInstalled {
                _ = helperQueue.sync { helper.run(.chargeOn(ChargeLimit(clamping: 100))) }
            }
        }
    }

    // MARK: - Battery Calibration API & Auto-Scheduler

    public func checkAutoCalibrationSchedule() {
        guard isAutoCalibrationEnabled && calibrationState == .idle && isHelperInstalled else { return }
        guard let last = lastCalibrationDate else {
            lastCalibrationDate = Date()
            return
        }

        let now = Date()
        let daysPassed = Calendar.current.dateComponents([.day], from: last, to: now).day ?? 0

        if daysPassed >= calibrationIntervalDays {
            // Reached schedule!
            if currentLevel <= 25 && isPluggedIn {
                // Battery is already low and plugged in -> go straight to step 2 (charge to 100%)
                calibrationState = .charging
                calibrationMessage = tr("Step 2/3: Charging to 100% (Currently: \(currentLevel)%)")
                setChargingInhibited(false)
                sendNotification(
                    title: tr("Calibration: started (Automatic)"),
                    body: tr("Battery is at \(currentLevel)%. LeanMac will charge to 100%, hold for 15 min, then lock at \(chargeLimit)%.")
                )
            } else if calibrationState == .idle {
                startCalibration(isAutomatic: true)
            }
        }
    }

    public func startCalibration(isAutomatic: Bool = false) {
        guard isHelperInstalled else {
            statusMessage = tr("SMC Helper required for calibration")
            return
        }

        if currentLevel <= 22 {
            // Battery is already low -> start the balancing charge immediately
            calibrationState = .charging
            calibrationMessage = tr("Step 2/3: Charging to 100% (Currently: \(currentLevel)%)")
            setChargingInhibited(false)
            sendNotification(
                title: tr("Calibration: started"),
                body: tr("Battery is at \(currentLevel)%. LeanMac will charge to 100%, hold for 15 min, then lock at \(chargeLimit)%.")
            )
            return
        }

        calibrationState = .discharging
        dischargeUnsupported = false
        calibrationMessage = tr("Step 1/3: Discharging battery to 20% (Currently: \(currentLevel)%)")
        setChargingInhibited(true)
        if isPluggedIn { engageAdapterDisable() }

        let reason = isAutomatic ? tr("Scheduled every \(calibrationIntervalDays) days") : tr("Manual")
        sendNotification(
            title: tr("Calibration: started (\(reason))"),
            body: tr("LeanMac will drain to 20%, charge to 100%, hold for 15 min, then lock at \(chargeLimit)%.")
        )
    }

    public func cancelCalibration() {
        calibrationState = .idle
        calibrationMessage = ""
        restingTimer?.invalidate()
        restingTimer = nil
        releaseAdapter { [weak self] in self?.evaluatePowerManagement() }
    }

    // MARK: - Discharge through the SMC (CHIE) while plugged in

    private func engageAdapterDisable() {
        guard isHelperInstalled, !adapterCommandInFlight else { return }
        adapterCommandInFlight = true
        helperQueue.async {
            let (out, code) = self.helper.run(.dischargeOn)
            DispatchQueue.main.async {
                self.adapterCommandInFlight = false
                if code == 0 {
                    self.adapterDisabledByApp = true
                    appLog("🔋 Calibration: adapter disabled (discharging while plugged in)")
                } else {
                    self.dischargeUnsupported = true
                    appLog("⚠️ Calibration: discharge-on failed (\(code)): \(out)")
                }
                self.refreshBatteryInfo()
            }
        }
    }

    /// Releases the adapter (if the app cut it), then runs `then`. `then` always runs on main.
    private func releaseAdapter(then: (() -> Void)? = nil) {
        guard adapterDisabledByApp else { then?(); return }
        adapterDisabledByApp = false
        helperQueue.async {
            let (out, code) = self.helper.run(.dischargeOff)
            if code != 0 { appLog("⚠️ discharge-off failed (\(code)): \(out)") }
            DispatchQueue.main.async {
                self.refreshBatteryInfo()
                then?()
            }
        }
    }

    /// Called at launch: if the previous run died during a discharge, release the adapter right away.
    public func releaseAdapterOnLaunch() {
        guard helper.isBinaryPresent else { return }
        helperQueue.async {
            _ = self.helper.run(.dischargeOff)
        }
    }

    private func completeCalibration() {
        calibrationState = .completed
        self.lastCalibrationDate = Date()
        calibrationMessage = tr("🎉 Calibration complete! Next schedule in \(calibrationIntervalDays) days.")
        setChargingInhibited(true)
        sendNotification(
            title: tr("Calibration: complete"),
            body: tr("The battery is calibrated. Charge locked again at \(chargeLimit)%.")
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            if self?.calibrationState == .completed {
                self?.calibrationState = .idle
                self?.calibrationMessage = ""
                self?.evaluatePowerManagement()
            }
        }
    }

    // MARK: - Helper Installation Check & Prompt

    public func checkHelperStatus(completion: ((Bool) -> Void)? = nil) {
        let exists = helper.isBinaryPresent
        guard exists else {
            self.isHelperInstalled = false
            self.helperVersion = 0
            if self.isProtectionEnabled {
                self.checkSMCBypassStatus()
                self.evaluatePowerManagement()
            }
            completion?(false)
            return
        }
        helperQueue.async {
            let (out, code) = self.helper.run(.version)
            let ver = PrivilegedHelper.parseVersion(output: out, exitCode: code)
            let isRealReady = (ver == PrivilegedHelper.requiredVersion)
            DispatchQueue.main.async {
                self.helperVersion = ver
                self.isHelperInstalled = isRealReady
                self.offerHelperUpdateIfNeeded()
                if self.isProtectionEnabled {
                    self.lastAppliedInhibitState = nil
                    self.checkSMCBypassStatus()
                    self.evaluatePowerManagement()
                }
                completion?(isRealReady)
            }
        }
    }

    /// A newer app can need a newer helper. When that is detected, tell the user once per helper version and, while the
    /// popover is open (the user is present), start the normal install, which asks for the administrator password.
    /// If the user cancels, the Settings row keeps an "Update" button; nothing nags again for this helper version.
    private func offerHelperUpdateIfNeeded() {
        guard isHelperOutdated, !isInstallingHelper else { return }
        let key = "helper_update_offered_version"
        guard UserDefaults.standard.integer(forKey: key) != PrivilegedHelper.requiredVersion else { return }
        guard isPopoverVisible else {
            sendNotification(title: tr("LeanMac helper needs an update"),
                             body: tr("Open LeanMac to update the charge-limit helper."))
            return
        }
        UserDefaults.standard.set(PrivilegedHelper.requiredVersion, forKey: key)
        installHelper()
    }

    public func installHelper(completion: ((Bool) -> Void)? = nil) {
        guard !isInstallingHelper else { return }
        isInstallingHelper = true

        let helper = services.helper
        let installer = services.installer
        DispatchQueue.global(qos: .userInitiated).async {
            let ver = installer.install(using: helper)
            let success = (ver == PrivilegedHelper.requiredVersion)

            DispatchQueue.main.async {
                self.isInstallingHelper = false
                self.helperVersion = ver
                self.isHelperInstalled = success
                if success {
                    self.isProtectionEnabled = true
                    self.checkSMCBypassStatus()
                    self.evaluatePowerManagement()
                }
                completion?(success)
            }
        }
    }
}
