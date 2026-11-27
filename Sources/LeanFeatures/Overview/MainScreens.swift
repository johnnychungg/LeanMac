// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import LeanDesignSystem
import LeanDomain
import LeanPlatform

func groupCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
    VStack(spacing: 0) { content() }
        .padding(.horizontal, 12).padding(.vertical, 2)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Pal.card))
}

// MARK: - Overview

struct OverviewTabView: View {
    @ObservedObject var displayManager: DisplayManager
    @ObservedObject var permissionsManager: PermissionsManager
    @ObservedObject var batteryManager: BatteryManager
    @ObservedObject var thermalManager: ThermalManager
    @ObservedObject private var monitor = SystemMonitorManager.shared
    @ObservedObject private var caffeine = CaffeinateManager.shared
    @ObservedObject private var shots = ScreenshotManager.shared
    @ObservedObject private var ui = UIState.shared

    private func go(_ tab: Int, sub: Int? = nil) {
        if let sub { ui.hardwareSub = sub }
        UIState.shared.selectedMainTab = tab
    }

    private func pct(_ v: Double) -> String { "\(Int(v.rounded())) %" }
    private func temp(_ v: Double) -> String { v > 0 ? String(format: "%.0f °C", v) : "–" }

    /// Clickable card: content + a small arrow in the corner.
    private func linkCard<C: View>(_ action: @escaping () -> Void, @ViewBuilder _ content: () -> C) -> some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 8) {
                content()
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .medium)).foregroundStyle(Pal.ink3)
            }
            .contentShape(Rectangle())
            .jCard()
        }
        .buttonStyle(.plain)
    }

    private func metric(_ title: String, _ value: String, _ level: MonLevel, memory: Bool = false, thermal: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).foregroundStyle(Pal.ink2)
            Text(value).font(.headline).monospacedDigit()
            Text(value == "–" ? "–" : (thermal ? level.temperatureLabel : (memory ? level.pressureLabel : level.loadLabel)))
        }
        .font(.caption).foregroundStyle(memory && level == .normal ? Pal.info : level.color)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var body: some View {
        TabScaffold {
            // Warnings: only shown when something is abnormal
            if !permissionsManager.hasAccessibility {
                JBanner(icon: "exclamationmark.triangle", text: tr("Accessibility missing, shortcuts are off"),
                        chevron: "chevron.right") { ui.openPermissionDetails = true; ui.settingsOpen = true }
            }
            if !batteryManager.isHelperInstalled && batteryManager.hasBattery {
                let old = batteryManager.helperVersion > 0 && batteryManager.helperVersion != PrivilegedHelper.requiredVersion
                JBanner(icon: "exclamationmark.shield",
                        text: old ? tr("SMC Helper update required") : tr("SMC Helper not installed"),
                        actionTitle: batteryManager.isInstallingHelper ? tr("Installing…") : (old ? tr("Update") : tr("Install")),
                        action: batteryManager.isInstallingHelper ? nil : { batteryManager.installHelper() })
            }
            if thermalManager.thermalLevel == .hot {
                JBanner(icon: "thermometer.high", text: tr("Mac is running hot"), chevron: "chevron.right") { go(1, sub: 2) }
            }
            if batteryManager.isAutoCalibrationEnabled && batteryManager.calibrationState == .idle && batteryManager.daysRemainingUntilCalibration <= 0 {
                JBanner(icon: "calendar.badge.exclamationmark", text: tr("Battery calibration is due"), chevron: "chevron.right") { go(1, sub: 0) }
            }

            if batteryManager.hasBattery {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label(tr("Battery"), systemImage: "battery.75percent")
                        Spacer()
                        Text(batteryManager.isPluggedIn ? tr("Plugged in") : tr("On battery"))
                    }.font(.caption)
                    HStack(alignment: .firstTextBaseline) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("\(batteryManager.currentLevel)").font(.system(size: 36, weight: .semibold))
                            Text("%").font(.title3)
                        }.monospacedDigit()
                        Spacer()
                        Text(batteryManager.calibrationState == .idle ? batteryManager.statusMessage : batteryManager.calibrationMessage)
                            .font(.caption).multilineTextAlignment(.trailing)
                    }
                    ProgressView(value: Double(batteryManager.currentLevel), total: 100).tint(Pal.accent)
                    HStack {
                        Button(batteryManager.isTopUpActive ? tr("Cancel top-up") : tr("Charge to 100 %")) {
                            batteryManager.isTopUpActive.toggle()
                        }.buttonStyle(.borderedProminent).tint(Pal.accent)
                            .disabled(!batteryManager.isHelperInstalled || !batteryManager.isProtectionEnabled || batteryManager.calibrationState != .idle)
                        Spacer()
                        Button(tr("Battery details")) { go(1, sub: 0) }
                    }.controlSize(.small)
                }
                .foregroundStyle(Pal.ink).padding(12)
                .background(LinearGradient(colors: [Pal.heroStart, Pal.heroEnd], startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: 12))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(tr("Quick actions")).font(.headline)
                HStack {
                    Label(tr("Keep awake"), systemImage: "cup.and.saucer")
                    Spacer()
                    if caffeine.isActive { Text(caffeine.remainingFormatted).font(.caption) }
                    Button(caffeine.isActive ? tr("Stop") : tr("Start 30 min")) {
                        if caffeine.isActive { caffeine.disable() } else { caffeine.enable(duration: .min30) }
                    }
                }
                JDivider()
                HStack {
                    Label(tr("Annotated screenshots"), systemImage: "camera.viewfinder")
                    Spacer()
                    Button(tr("Capture now")) { shots.startCapture() }.disabled(!shots.isScreenshotEnabled)
                }
            }.controlSize(.small).jCard()

            linkCard({ go(1, sub: 2) }) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(tr("Monitor")).font(.headline)
                    HStack {
                        metric("CPU", pct(monitor.cpuUsagePercent), MonLevel.percent(monitor.cpuUsagePercent))
                        metric("RAM", monitor.memoryStats == nil ? "–" : pct(monitor.ramUsagePercent), monitor.memoryPressure == .critical ? .danger : (monitor.memoryPressure == .warning ? .warn : .normal), memory: true)
                        metric(tr("Temperature"), temp(thermalManager.displayTemp), MonLevel.temp(thermalManager.displayTemp), thermal: true)
                    }
                }
            }.onAppear { monitor.beginPreview() }.onDisappear { monitor.endPreview() }

            if !displayManager.monitors.isEmpty {
                linkCard({ go(1, sub: 1) }) {
                    Label(tr("Displays"), systemImage: "display")
                    Spacer()
                    Text("\(displayManager.monitors.count)").monospacedDigit()
                }
            }
        }
    }
}

// MARK: - Tools tab

struct ToolsTabView: View {
    @ObservedObject private var snap = WindowSnapManager.shared
    @ObservedObject private var windows = WindowManager.shared
    @ObservedObject private var shots = ScreenshotManager.shared
    @ObservedObject private var finder = FinderCutPasteManager.shared
    @ObservedObject private var shortcuts = ShortcutManager.shared
    @ObservedObject private var caffeine = CaffeinateManager.shared
    @ObservedObject private var ui = UIState.shared
    @ObservedObject private var secureInput = SecureInputWatcher.shared

    var body: some View {
        TabScaffold(subItems: [tr("Utilities"), tr("Startup"), tr("Processes")],
                    selection: Binding(get: { ui.toolsSub }, set: { ui.toolsSub = $0 })) {
            switch ui.toolsSub {
            case 1: StartupItemsView()
            case 2: EnergyView()
            default: utilities
            }
        }
        .onAppear { SecureInputWatcher.shared.start() }
        .onDisappear { SecureInputWatcher.shared.stop() }
    }

    @ViewBuilder private var utilities: some View {
            if let holder = secureInput.holder {
                JBanner(icon: "keyboard.badge.ellipsis",
                        text: tr("\(holder.name) is blocking keyboard shortcuts (Secure Input). Quit it to restore them."),
                        actionTitle: tr("Quit")) { secureInput.quitHolder() }
            }
            VStack(alignment: .leading, spacing: 10) {
                JToggleRow(icon: "cup.and.saucer", title: tr("Keep awake"),
                           subtitle: caffeine.isActive && !caffeine.remainingFormatted.isEmpty ? tr("\(caffeine.remainingFormatted) left") : nil,
                           isOn: Binding(get: { caffeine.isActive }, set: { _ in caffeine.toggle() }))
                HStack(spacing: 6) {
                    ForEach(CaffeinateDuration.allCases) { d in
                        JChip(text: d.title, selected: caffeine.selectedDuration == d) { caffeine.setDuration(d) }
                    }
                }
            }
            .jCard()

            EffectsCard()

            groupCard {
                JToggleRow(icon: "rectangle.split.2x1", title: tr("Window snapping"),
                           isOn: Binding(get: { snap.isSnapEnabled }, set: { snap.isSnapEnabled = $0 }),
                           trailing: AnyView(KeyCaps(keys: ["⌃", "⌥", "←"])))
                    .padding(.vertical, 8)
                JDivider()
                JToggleRow(icon: "macwindow.on.rectangle", title: tr("Window switcher"),
                           isOn: Binding(get: { windows.isAltTabEnabled }, set: { windows.isAltTabEnabled = $0 }),
                           trailing: AnyView(KeyCaps(keys: [shortcuts.primaryTitle(.switchWindows)])))
                    .padding(.vertical, 8)
                if windows.isAltTabEnabled {
                    JDivider()
                    JToggleRow(icon: "display", title: tr("Only windows on current display"),
                               isOn: Binding(get: { windows.showOnlyCurrentScreenWindows }, set: { windows.showOnlyCurrentScreenWindows = $0 }))
                        .padding(.vertical, 8)
                        .padding(.leading, 22)
                    if !windows.hasScreenRecording {
                        JDivider()
                        HStack {
                            Text(tr("Screen recording needed for thumbnails"))
                                .font(.system(size: 12)).foregroundStyle(Pal.warn)
                            Spacer()
                            JChip(text: tr("Grant"), selected: true) { windows.requestScreenRecordingPermission() }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }

            groupCard {
                JToggleRow(icon: "camera.viewfinder", title: tr("Annotated screenshots"),
                           isOn: Binding(get: { shots.isScreenshotEnabled }, set: { shots.isScreenshotEnabled = $0 }),
                           trailing: AnyView(KeyCaps(keys: [shortcuts.primaryTitle(.screenshot)])))
                    .padding(.vertical, 8)
                if shots.isScreenshotEnabled {
                    Button { shots.startCapture() } label: {
                        HStack(spacing: 6) { Image(systemName: "camera.viewfinder"); Text(tr("Capture now")) }
                    }
                    .buttonStyle(JButtonStyle(kind: .ghost))
                }
                JDivider()
                JToggleRow(icon: "scissors", title: tr("Finder cut and paste"),
                           isOn: Binding(get: { finder.isEnabled }, set: { finder.isEnabled = $0 }),
                           trailing: AnyView(KeyCaps(keys: ["⌘X", "⌘V"])))
                    .padding(.vertical, 8)
            }
        }
    }

// MARK: - Settings (secondary page opened from the gear)

struct SettingsView: View {
    @ObservedObject var permissionsManager: PermissionsManager
    @ObservedObject var batteryManager: BatteryManager
    @ObservedObject private var ui = UIState.shared
    @ObservedObject private var login = LaunchAtLoginManager.shared
    @ObservedObject private var language = LanguageManager.shared
    @ObservedObject private var appearance = AppearanceManager.shared
    @ObservedObject private var shortcuts = ShortcutManager.shared
    @ObservedObject private var updates = UpdateManager.shared
    private enum Detail { case updates, shortcuts, permissions, about }
    @State private var detail: Detail?

    init(permissionsManager: PermissionsManager, batteryManager: BatteryManager) {
        self.permissionsManager = permissionsManager
        self.batteryManager = batteryManager
        _detail = State(initialValue: UIState.shared.openPermissionDetails ? .permissions : nil)
    }

    private func destination(_ title: String, icon: String, detail target: Detail) -> some View {
        Button { detail = target } label: {
            HStack {
                Label(title, systemImage: icon)
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(Pal.ink3)
            }.padding(.vertical, 8).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private func section(_ title: String) -> some View {
        Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(Pal.ink3)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Button { if detail != nil { detail = nil } else { ui.settingsOpen = false } } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left").font(.system(size: 12, weight: .semibold))
                        Text(tr("Back")).font(.system(size: 13))
                    }
                    .foregroundStyle(Pal.accent)
                }
                .buttonStyle(.plain)
                Spacer()
                Text(tr("Settings")).font(.system(size: 14, weight: .medium)).foregroundStyle(Pal.ink)
                Spacer()
                Color.clear.frame(width: 56, height: 1)
            }
            .padding(.horizontal, 14)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 10) {
                    switch detail {
                    case .updates:
                        UpdateSettingsCard(updates: updates)
                    case .shortcuts:
                        ShortcutMapView(manager: shortcuts)
                    case .permissions:
                        PermissionsStrip(permissionsManager: permissionsManager, alwaysOpen: true)
                    case .about:
                        VStack(spacing: 8) {
                            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 58, height: 58)
                            Text("LeanMac " + updates.currentVersion).font(.headline)
                            Text("GPL-3.0").font(.caption)
                            Button(tr("Quit LeanMac")) { NSApp.terminate(nil) }
                        }.frame(maxWidth: .infinity).jCard()
                    case nil:
                        section(tr("General"))
                        groupCard {
                            HStack(spacing: 10) {
                                JIcon(name: "globe")
                                Text(tr("Language")).font(.system(size: 13, weight: .medium)).foregroundStyle(Pal.ink)
                                Spacer()
                                Menu {
                                    ForEach(AppLanguage.allCases) { option in
                                        Button { language.switchLanguage(to: option) } label: {
                                            if option == language.currentLanguage {
                                                Label(option.displayName, systemImage: "checkmark")
                                            } else { Text(option.displayName) }
                                        }
                                    }
                                } label: {
                                    Text(language.currentLanguage.displayName).font(.system(size: 12, weight: .medium)).lineLimit(1)
                                }
                                .menuStyle(.borderlessButton)
                                .fixedSize()
                                .accessibilityLabel(tr("Language"))
                            }
                            .padding(.vertical, 8)
                            JDivider()
                            HStack(spacing: 10) {
                                JIcon(name: "circle.lefthalf.filled")
                                Text(tr("Appearance")).font(.system(size: 13, weight: .medium)).foregroundStyle(Pal.ink)
                                    .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                                Spacer(minLength: 4)
                                JSegmented(items: [tr("Auto"), tr("Light"), tr("Dark")],
                                           selection: Binding(get: { appearance.mode }, set: { appearance.mode = $0 }))
                                    .frame(width: 168)
                            }
                            .padding(.vertical, 8)
                            JDivider()
                            JToggleRow(icon: "power.circle", title: tr("Launch at login"),
                                       isOn: Binding(get: { login.isEnabled }, set: { login.setEnabled($0) }))
                                .padding(.vertical, 8)
                        }

                        groupCard {
                            destination(tr("Permissions"), icon: "checkmark.shield", detail: .permissions)
                            JDivider()
                            destination(tr("Shortcuts"), icon: "command", detail: .shortcuts)
                            JDivider()
                            destination(tr("Updates"), icon: "arrow.down.circle", detail: .updates)
                            JDivider()
                            destination(tr("About LeanMac"), icon: "info.circle", detail: .about)
                        }

                        section(tr("Advanced"))
                        groupCard {
                            HStack {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("Helper SMC").font(.system(size: 13, weight: .medium)).foregroundStyle(Pal.ink)
                                    // No version number: "installed" already means it is the one this app needs.
                                    Text(batteryManager.isHelperInstalled ? tr("Installed")
                                         : (batteryManager.isHelperOutdated ? tr("Update needed") : tr("Not installed")))
                                        .font(.system(size: 12)).foregroundStyle(Pal.ink3)
                                }
                                Spacer()
                                JChip(text: batteryManager.isInstallingHelper ? tr("Installing…")
                                      : (batteryManager.isHelperInstalled ? tr("Reinstall")
                                         : (batteryManager.isHelperOutdated ? tr("Update") : tr("Install"))),
                                      selected: !batteryManager.isHelperInstalled) {
                                    if !batteryManager.isInstallingHelper { batteryManager.installHelper() }
                                }
                            }
                            .padding(.vertical, 8)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
            }
        }
        .padding(.top, 2)
    }
}
