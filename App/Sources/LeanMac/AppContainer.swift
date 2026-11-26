// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import LeanDomain
import LeanPlatform

/// Composition root: the only place that creates platform adapters and hands them to the rest of the app.
///
/// Created once, before the application starts. Services that are still reached through a global
/// injection point (`Shell`, `Notifier`, `BatteryServices.current`) are installed here so nothing runs
/// against the defaults.
@MainActor
final class AppContainer {
    /// Contributor mode: read the hardware, never write to it (no SMC writes, no helper, no Bluetooth changes).
    /// Enabled with `LEANMAC_DEV=1` (`Scripts/build.sh --dev` does that).
    static let isReadOnlyMode = ProcessInfo.processInfo.environment["LEANMAC_DEV"] == "1"

    let notifications: NotificationManager

    init() {
        // Language first: strings built while the services start must already use the saved language.
        _ = LanguageManager.shared
        let shell = ProcessShellRunner()
        Shell.runner = shell
        notifications = NotificationManager()
        Notifier.sender = notifications

        if Self.isReadOnlyMode {
            appLog("Read-only mode (LEANMAC_DEV=1): hardware writes are disabled")
            BatteryServices.current = BatteryServices(
                reader: IOKitBatteryReader(),
                smc: AppleSMCClient(),
                helper: ReadOnlyHelperGateway(),
                installer: ReadOnlyHelperInstaller(),
                bluetoothFactory: { ReadOnlyBluetooth() },
                ceilingFactory: { ReadOnlyChargeCeiling() },
                powerSourceObserverFactory: { IOPSObserver() }
            )
        } else {
            BatteryServices.current = BatteryServices(
                reader: IOKitBatteryReader(),
                smc: AppleSMCClient(),
                helper: SudoHelperGateway(shell: shell),
                installer: HelperInstaller(),
                bluetoothFactory: { BluetoothManager() },
                ceilingFactory: { PowerUICeilingClient() },
                powerSourceObserverFactory: { IOPSObserver() }
            )
        }
    }
}
