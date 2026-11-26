// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import LeanDesignSystem
import LeanDomain

/// The "Updates" block of the settings page: current version, automatic check, and the install button.
struct UpdateSettingsCard: View {
    @ObservedObject var updates: UpdateManager

    private var statusText: String {
        switch updates.state {
        case .idle: return tr("Version \(updates.currentVersion) (build \(updates.currentBuild))")
        case .checking: return tr("Checking for updates…")
        case .upToDate: return tr("You are up to date (version \(updates.currentVersion)).")
        case .available(let m): return tr("Version \(m.version) is available.")
        case .needsNewerSystem(let m): return tr("Version \(m.version) needs a newer macOS.")
        case .downloading: return tr("Downloading…")
        case .installing: return tr("Installing and restarting…")
        case .failed(let message): return message
        }
    }

    var body: some View {
        groupCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    JIcon(name: "arrow.down.circle")
                    Text(statusText).font(.system(size: 13, weight: .medium)).foregroundStyle(Pal.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if updates.isAvailableInThisBuild, !hasWideButtons { actionButtons }
                }
                // Messages with two buttons would squeeze the text, so the buttons get their own row.
                if updates.isAvailableInThisBuild, hasWideButtons {
                    HStack(spacing: 8) { Spacer(minLength: 0); actionButtons }
                }
                if updates.isAvailableInThisBuild {
                    JDivider()
                    JToggleRow(icon: "clock.arrow.circlepath", title: tr("Check for updates automatically"),
                               isOn: Binding(get: { updates.autoCheckEnabled }, set: { updates.autoCheckEnabled = $0 }))
                }
            }
            .padding(.vertical, 8)
        }
    }

    private var hasWideButtons: Bool {
        switch updates.state {
        case .failed, .available: return true
        default: return false
        }
    }

    @ViewBuilder private var actionButtons: some View {
        switch updates.state {
        case .available:
            if updates.installBlocker == nil {
                JChip(text: tr("Install"), selected: true) { updates.installAvailable() }
            } else {
                JChip(text: tr("Open release page"), selected: true) { updates.openReleasePage() }
            }
            JChip(text: tr("Skip"), selected: false) { updates.skipAvailableVersion() }
        case .needsNewerSystem:
            JChip(text: tr("Open release page"), selected: false) { updates.openReleasePage() }
        case .checking, .downloading, .installing:
            ProgressView().controlSize(.small)
        case .failed:
            JChip(text: tr("Check now"), selected: false) { updates.checkNow() }
            JChip(text: tr("Open release page"), selected: false) { updates.openReleasePage() }
        default:
            JChip(text: tr("Check now"), selected: false) { updates.checkNow() }
        }
    }
}
