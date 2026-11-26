// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import AppKit
import LeanDesignSystem
import LeanDomain

// MARK: - Main frame: header + content + bottom tab bar

public struct MainView: View {
    @ObservedObject package var displayManager: DisplayManager
    @ObservedObject package var batteryManager: BatteryManager = BatteryManager.shared
    @ObservedObject package var thermalManager: ThermalManager = ThermalManager.shared
    @ObservedObject package var cleanerManager: SystemCleanerManager = SystemCleanerManager.shared
    @ObservedObject package var languageManager: LanguageManager = LanguageManager.shared
    @ObservedObject package var permissionsManager: PermissionsManager = PermissionsManager.shared
    @ObservedObject package var appearance: AppearanceManager = AppearanceManager.shared
    @ObservedObject package var ui: UIState = UIState.shared

    public init(displayManager: DisplayManager) {
        self.displayManager = displayManager
    }

    public var body: some View {
        VStack(spacing: 0) {
            HeaderBar(batteryManager: batteryManager, thermalManager: thermalManager, displayManager: displayManager)

            Group {
                if ui.settingsOpen {
                    SettingsView(permissionsManager: permissionsManager, batteryManager: batteryManager)
                } else {
                    let tabs = FeatureRegistry.mainTabs
                    let tab = tabs[min(max(ui.selectedMainTab, 0), tabs.count - 1)]
                    tab.makeView(FeatureContext(displayManager: displayManager, batteryManager: batteryManager,
                                                thermalManager: thermalManager, cleanerManager: cleanerManager,
                                                permissionsManager: permissionsManager))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            BottomTabBar(selected: Binding(
                get: { ui.settingsOpen ? -1 : ui.selectedMainTab },
                set: { ui.selectedMainTab = $0; ui.settingsOpen = false }
            ))
        }
        .id(languageManager.currentLanguage)
        .preferredColorScheme(appearance.colorScheme)
        .frame(width: 380, height: 600)
        .background(Pal.bg)
        .alert(isPresented: Binding<Bool>(
            get: { displayManager.showAlert },
            set: { displayManager.showAlert = $0 }
        )) {
            Alert(
                title: Text(tr("Notice")),
                message: Text(displayManager.alertMessage ?? ""),
                dismissButton: .default(Text(tr("OK")))
            )
        }
    }
}

// MARK: - Header

struct HeaderBar: View {
    @ObservedObject private var ui = UIState.shared
    @ObservedObject var batteryManager: BatteryManager
    @ObservedObject var thermalManager: ThermalManager
    @ObservedObject var displayManager: DisplayManager
    @ObservedObject var languageManager: LanguageManager = LanguageManager.shared

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                // Same colored logo as the menu bar (the L follows the light/dark text color, the leaf stays mint).
                Image(nsImage: LeanLogo.menuBarImage(size: 24))
                    .resizable()
                    .frame(width: 24, height: 24)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Pal.accentBg))
                Text("LeanMac").font(.system(size: 14, weight: .medium)).foregroundStyle(Pal.ink)
                    .lineLimit(1).fixedSize()
                Text(UpdateManager.shared.currentVersion).font(.system(size: 11)).foregroundStyle(Pal.ink3)
                    .lineLimit(1).fixedSize().padding(.top, 2)
            }

            Spacer(minLength: 4)

            JStatusChip(text: statusText, icon: statusIcon, kind: statusKind).fixedSize()

            Button { withAnimation(.easeOut(duration: 0.15)) { UIState.shared.settingsOpen.toggle() } } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(ui.settingsOpen ? Pal.accent : Pal.ink2)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help(tr("Settings"))

            Button { NSApplication.shared.terminate(nil) } label: {
                Image(systemName: "power")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Pal.ink3)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help(tr("Quit LeanMac"))
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var isLocked: Bool {
        batteryManager.isProtectionEnabled && batteryManager.isBypassActive && batteryManager.isPluggedIn
    }
    private var statusText: String {
        isLocked ? tr("Lock \(batteryManager.chargeLimit)%") : "\(batteryManager.currentLevel)%"
    }
    private var statusIcon: String {
        if isLocked { return "lock.shield" }
        if batteryManager.isCharging { return "bolt.fill" }
        if batteryManager.isPluggedIn { return "powerplug" }
        return "battery.50"
    }
    private var statusKind: JStatusChip.Kind {
        if isLocked { return .ok }
        if !batteryManager.isPluggedIn && batteryManager.currentLevel <= 20 { return .warn }
        return .neutral
    }
}

// MARK: - Bottom tab bar

struct BottomTabBar: View {
    @Binding var selected: Int

    private var items: [(String, String)] {
        FeatureRegistry.mainTabs.map { ($0.icon, $0.title()) }
    }

    var body: some View {
        VStack(spacing: 0) {
            JDivider()
            HStack(spacing: 4) {
                ForEach(items.indices, id: \.self) { i in
                    Button { selected = i } label: {
                        VStack(spacing: 2) {
                            Image(systemName: items[i].0).font(.system(size: 17))
                            Text(items[i].1).font(.system(size: 11)).lineLimit(1)
                        }
                        .foregroundStyle(selected == i ? Pal.accent : Pal.ink2)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(selected == i ? Pal.accentBg : Color.clear))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8).padding(.top, 6).padding(.bottom, 8)
        }
    }
}

/// Shared shell of every tab: a fixed sub-tab bar on top, scrolling content below.
struct TabScaffold<Content: View>: View {
    var subItems: [String]? = nil
    var selection: Binding<Int>? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 10) {
            if let subItems, let selection {
                JSegmented(items: subItems, selection: selection)
                    .padding(.horizontal, 14)
            }
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 10) { content() }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
            }
        }
        .padding(.top, 2)
    }
}
