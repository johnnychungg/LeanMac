// SPDX-License-Identifier: GPL-3.0-only
// Native hover/focus/pressed/disabled, inline applying/error states, and reversible success.
import SwiftUI
import CoreGraphics
import LeanDesignSystem
import LeanDomain

struct DisplayModeControls<Trailing: View>: View {
    let displayID: CGDirectDisplayID
    @ObservedObject var manager: DisplayModeManager
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                if let catalog = manager.catalogs[displayID] {
                    Menu {
                        ForEach(catalog.resolutions) { resolution in
                            Button { manager.selectResolution(resolution, for: displayID) } label: {
                                if resolution == catalog.current.resolution {
                                    Label(resolution.title, systemImage: "checkmark")
                                } else { Text(resolution.title) }
                            }
                        }
                    } label: {
                        Text("\(catalog.current.resolution.width) × \(catalog.current.resolution.height)").lineLimit(1)
                    }
                    .fixedSize()
                    .disabled(catalog.resolutions.count < 2 || manager.applyingDisplay != nil)
                    .help(catalog.current.resolution.title + " — " + tr("UI resolution; HiDPI provides sharper text."))
                    .accessibilityLabel(tr("Display resolution"))
                    .accessibilityValue(catalog.current.resolution.title)

                    Menu {
                        ForEach(catalog.rates(for: catalog.current.resolution)) { option in
                            Button { manager.select(option, for: displayID) } label: {
                                if option == catalog.current {
                                    Label(option.refreshTitle, systemImage: "checkmark")
                                } else { Text(option.refreshTitle) }
                            }
                        }
                    } label: {
                        Text(catalog.current.milliHertz == 0 ? tr("Auto") : catalog.current.refreshTitle).lineLimit(1)
                    }
                    .fixedSize()
                    .disabled(catalog.rates(for: catalog.current.resolution).count < 2 || manager.applyingDisplay != nil)
                    .help(tr("Refresh rate: only modes supported by macOS at this resolution are listed."))
                    .accessibilityLabel(tr("Display refresh rate"))
                    .accessibilityValue(catalog.current.refreshTitle)
                } else {
                    Text(tr("Display modes unavailable"))
                        .font(.system(size: FS.caption)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                trailing()
            }
            .controlSize(.mini)
            .font(.system(size: FS.caption, weight: .medium))
            if manager.catalogs[displayID]?.isMirrored == true {
                Text(tr("Mirroring: changes may affect other displays in this group."))
                    .font(.system(size: FS.caption)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if manager.applyingDisplay == displayID {
                HStack(spacing: 4) {
                    ProgressView().controlSize(.mini)
                    Text(tr("Applying display mode…"))
                        .font(.system(size: FS.caption))
                }
            }
            if let error = manager.errors[displayID] {
                Text(error).font(.system(size: FS.caption)).foregroundStyle(Tone.warn)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if manager.previous[displayID] != nil {
                Button(tr("Undo display mode change")) { manager.undo(for: displayID) }
                    .font(.system(size: FS.caption)).controlSize(.small)
                    .disabled(manager.applyingDisplay != nil)
            }
        }
    }
}
