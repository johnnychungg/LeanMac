// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import LeanDomain

/// A top-level tab of the popover. To add a feature tab, append one entry to
/// `FeatureRegistry.mainTabs`; the tab bar and the content switch are built from it.
struct FeatureModule: Identifiable {
    /// Stable identifier (never shown, never localized).
    let id: String
    /// SF Symbol name.
    let icon: String
    /// English source title; localized at render time through `tr`.
    let title: () -> String
    /// Builds the tab content.
    let makeView: @MainActor (FeatureContext) -> AnyView
}

/// Dependencies a tab may need. Kept small on purpose: it is the seam that will replace `.shared`.
struct FeatureContext {
    let displayManager: DisplayManager
    let batteryManager: BatteryManager
    let thermalManager: ThermalManager
    let cleanerManager: SystemCleanerManager
    let permissionsManager: PermissionsManager
}

enum FeatureRegistry {
    /// Order here is the order in the bottom tab bar.
    static let mainTabs: [FeatureModule] = [
        FeatureModule(id: "overview", icon: "gauge.with.dots.needle.67percent",
                      title: { tr("Overview") },
                      makeView: { c in
            AnyView(OverviewTabView(displayManager: c.displayManager, permissionsManager: c.permissionsManager,
                                    batteryManager: c.batteryManager, thermalManager: c.thermalManager))
        }),
        FeatureModule(id: "hardware", icon: "cpu",
                      title: { tr("Hardware") },
                      makeView: { c in
            AnyView(HardwareTabView(batteryManager: c.batteryManager, thermalManager: c.thermalManager,
                                    displayManager: c.displayManager))
        }),
        FeatureModule(id: "tools", icon: "wrench.and.screwdriver",
                      title: { tr("Tools") },
                      makeView: { _ in AnyView(ToolsTabView()) }),
        FeatureModule(id: "cleaner", icon: "sparkles",
                      title: { tr("Cleaner") },
                      makeView: { c in AnyView(CleanerTabView(cleanerManager: c.cleanerManager)) })
    ]

    /// Tab index for an id; falls back to the first tab.
    static func index(of id: String) -> Int {
        mainTabs.firstIndex { $0.id == id } ?? 0
    }
}
