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

// MARK: - Overview tab (read-only; cards are clickable and jump to the right place)

struct OverviewTabView: View {
    @ObservedObject var displayManager: DisplayManager
    @ObservedObject var permissionsManager: PermissionsManager
    @ObservedObject var batteryManager: BatteryManager
    @ObservedObject var thermalManager: ThermalManager
    @ObservedObject private var monitor = SystemMonitorManager.shared
    @ObservedObject private var caffeine = CaffeinateManager.shared
    @ObservedObject private var snap = WindowSnapManager.shared
    @ObservedObject private var windows = WindowManager.shared
    @ObservedObject private var shots = ScreenshotManager.shared
    @ObservedObject private var finder = FinderCutPasteManager.shared
    @ObservedObject private var ui = UIState.shared

    private func go(_ tab: Int, sub: Int? = nil) {
        if let sub { ui.hardwareSub = sub }
        UIState.shared.selectedMainTab = tab
    }

    private func pct(_ v: Double) -> String { "\(Int(v.rounded()))%" }
    private func temp(_ v: Double) -> String { v > 0 ? String(format: "%.0f°", v) : "–" }

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

    private var activeChips: [(String, String)] {
        var list: [(String, String)] = []
        if batteryManager.hasBattery && batteryManager.isProtectionEnabled {
            list.append(("lock", tr("Charge limit \(batteryManager.chargeLimit)%")))
        }
        if batteryManager.isSleepGuardEnabled { list.append(("moon.stars", "Sleep Guard")) }
        if caffeine.isActive {
            list.append(("cup.and.saucer", caffeine.remainingFormatted.isEmpty ? tr("Keep awake")
                         : tr("Keep awake \(caffeine.remainingFormatted)")))
        }
        if snap.isSnapEnabled { list.append(("rectangle.split.2x1", tr("Snapping"))) }
        if windows.isAltTabEnabled { list.append(("macwindow.on.rectangle", tr("Switcher"))) }
        if shots.isScreenshotEnabled { list.append(("camera.viewfinder", tr("Screenshots"))) }
        if finder.isEnabled { list.append(("scissors", tr("Finder cut/paste"))) }
        let pins = [monitor.showCPUMenuBar, monitor.showRAMMenuBar, monitor.showGPUMenuBar && monitor.hasGPU, thermalManager.showMenuBarMetrics].filter { $0 }.count
        if pins > 0 { list.append(("pin", tr("\(pins) in menu bar"))) }
        return list
    }

    var body: some View {
        TabScaffold {
            // Warnings: only shown when something is abnormal
            if !permissionsManager.hasAccessibility {
                JBanner(icon: "exclamationmark.triangle", text: tr("Accessibility missing, shortcuts are off"),
                        chevron: "chevron.right") { ui.settingsOpen = true }
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

            // Pin
            if batteryManager.hasBattery {
                linkCard({ go(1, sub: 0) }) {
                    ZStack {
                        Circle().stroke(Pal.lineStrong.opacity(0.5), lineWidth: 6)
                        Circle()
                            .trim(from: 0, to: CGFloat(min(max(batteryManager.currentLevel, 0), 100)) / 100)
                            .stroke(Pal.accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Text("\(batteryManager.currentLevel)%").font(.system(size: 14, weight: .medium)).foregroundStyle(Pal.ink)
                    }
                    .frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(batteryManager.calibrationState != .idle ? batteryManager.calibrationMessage : batteryManager.statusMessage)
                            .font(.system(size: 13, weight: .medium)).foregroundStyle(Pal.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 6) {
                            JStatusChip(text: tr("Health \(batteryManager.healthPercent)%"))
                            JStatusChip(text: tr("\(batteryManager.cycleCount) cycles"))
                        }
                    }
                    Spacer(minLength: 0)
                }
            }

            // Temperature + load
            linkCard({ go(1, sub: 2) }) {
                VStack(spacing: 8) {
                    HStack(spacing: 6) {
                        JTile(label: "CPU", value: pct(monitor.cpuUsagePercent))
                        JTile(label: "RAM", value: pct(monitor.ramUsagePercent))
                        JTile(label: "GPU", value: monitor.hasGPU ? pct(monitor.gpuUsagePercent) : "–")
                        JTile(label: tr("Temperature"), value: temp(thermalManager.displayTemp))
                    }
                }
            }
            .onAppear { monitor.beginPreview() }
            .onDisappear { monitor.endPreview() }

            // Display
            if !displayManager.monitors.isEmpty {
                linkCard({ go(1, sub: 1) }) {
                    VStack(spacing: 8) {
                        ForEach(displayManager.monitors) { m in
                            HStack(spacing: 8) {
                                Image(systemName: m.isBuiltIn ? "laptopcomputer" : "display").font(.system(size: 13)).foregroundStyle(Pal.accent).frame(width: 20)
                                Text(m.name).font(.system(size: 13)).foregroundStyle(Pal.ink).lineLimit(1)
                                Spacer(minLength: 4)
                                Text(m.resolution).font(.system(size: 12)).foregroundStyle(Pal.ink3).lineLimit(1)
                                Text("\(Int(round(m.brightness * 100)))%").font(.system(size: 13, weight: .medium)).foregroundStyle(Pal.ink)
                            }
                        }
                    }
                }
            }

            // Currently on
            VStack(alignment: .leading, spacing: 8) {
                Text(tr("Active")).font(.system(size: 13, weight: .medium)).foregroundStyle(Pal.ink)
                if activeChips.isEmpty {
                    Text(tr("Nothing enabled")).font(.system(size: 12)).foregroundStyle(Pal.ink3)
                } else {
                    FlowLayout(spacing: 6) {
                        ForEach(activeChips, id: \.1) { chip in JChip(text: chip.1, icon: chip.0, selected: true) }
                    }
                }
            }
            .jCard()
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

    var body: some View {
        TabScaffold(subItems: [tr("Utilities"), tr("Startup"), tr("Processes")],
                    selection: Binding(get: { ui.toolsSub }, set: { ui.toolsSub = $0 })) {
            switch ui.toolsSub {
            case 1: StartupItemsView()
            case 2: EnergyView()
            default: utilities
            }
        }
    }

    @ViewBuilder private var utilities: some View {
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
                JDivider()
                JToggleRow(icon: "camera.viewfinder", title: tr("Annotated screenshots"),
                           isOn: Binding(get: { shots.isScreenshotEnabled }, set: { shots.isScreenshotEnabled = $0 }),
                           trailing: AnyView(KeyCaps(keys: [shortcuts.primaryTitle(.screenshot)])))
                    .padding(.vertical, 8)
                JDivider()
                JToggleRow(icon: "scissors", title: tr("Finder cut and paste"),
                           isOn: Binding(get: { finder.isEnabled }, set: { finder.isEnabled = $0 }),
                           trailing: AnyView(KeyCaps(keys: ["⌘X", "⌘V"])))
                    .padding(.vertical, 8)
            }

            if shots.isScreenshotEnabled {
                Button { shots.startCapture() } label: {
                    HStack(spacing: 6) { Image(systemName: "camera.viewfinder"); Text(tr("Capture now")) }
                }
                .buttonStyle(JButtonStyle(kind: .ghost))
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
    @State private var showKeys = false

    private func section(_ title: String) -> some View {
        Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(Pal.ink3)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Button { withAnimation(.easeOut(duration: 0.15)) { ui.settingsOpen = false } } label: {
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
                    section(tr("General"))
                    groupCard {
                        HStack(spacing: 10) {
                            JIcon(name: "globe")
                            Text(tr("Language")).font(.system(size: 13, weight: .medium)).foregroundStyle(Pal.ink)
                            Spacer()
                            JSegmented(items: ["VI", "EN"], selection: Binding(
                                get: { language.currentLanguage == .vi ? 0 : 1 },
                                set: { language.switchLanguage(to: $0 == 0 ? .vi : .en) }
                            ))
                            .frame(width: 120)
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

                    section(tr("Updates"))
                    UpdateSettingsCard(updates: updates)

                    section(tr("Shortcuts"))
                    Button { withAnimation(.easeOut(duration: 0.15)) { showKeys.toggle() } } label: {
                        HStack(spacing: 10) {
                            JIcon(name: "command")
                            Text(tr("Assign keys to actions")).font(.system(size: 13, weight: .medium)).foregroundStyle(Pal.ink)
                            Spacer()
                            Image(systemName: showKeys ? "chevron.up" : "chevron.down").font(.system(size: 11, weight: .medium)).foregroundStyle(Pal.ink3)
                        }
                        .contentShape(Rectangle())
                        .jCard()
                    }
                    .buttonStyle(.plain)
                    if showKeys { ShortcutMapView(manager: shortcuts) }

                    section(tr("Permissions"))
                    PermissionsStrip(permissionsManager: permissionsManager, alwaysOpen: true)

                    section(tr("Advanced"))
                    groupCard {
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Helper SMC").font(.system(size: 13, weight: .medium)).foregroundStyle(Pal.ink)
                                // "Installed" means the helper answers with the version THIS app needs, so it matches the app version.
                                Text(batteryManager.isHelperInstalled
                                     ? tr("Version \(updates.currentVersion), installed")
                                     : (batteryManager.helperVersion > 0 ? tr("Outdated, reinstall needed") : tr("Not installed")))
                                    .font(.system(size: 12)).foregroundStyle(Pal.ink3)
                            }
                            Spacer()
                            JChip(text: batteryManager.isInstallingHelper ? tr("Installing…")
                                  : (batteryManager.isHelperInstalled ? tr("Reinstall") : tr("Install")),
                                  selected: !batteryManager.isHelperInstalled) {
                                if !batteryManager.isInstallingHelper { batteryManager.installHelper() }
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
            }
        }
        .padding(.top, 2)
    }
}
