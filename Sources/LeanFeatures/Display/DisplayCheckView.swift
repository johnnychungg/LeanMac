// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import CoreGraphics
import LeanDesignSystem
import LeanDomain

/// "Display check": matches the UI size of every display to the built-in screen, picks each display's best refresh
/// rate, and applies the result only after confirmation, with an automatic revert.
struct DisplayCheckCard: View {
    @ObservedObject var displayManager: DisplayManager
    @ObservedObject private var modes = DisplayModeManager.shared

    private func density(_ value: Double?) -> String { value.map { "\(Int($0.rounded())) pt/in" } ?? "–" }

    private func modeText(_ option: DisplayModeOption) -> String {
        "\(option.resolution.width) × \(option.resolution.height)" + (option.resolution.isHiDPI ? " HiDPI" : "")
            + (option.milliHertz > 0 ? " · \(option.refreshTitle)" : "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                JIcon(name: "checkmark.seal")
                VStack(alignment: .leading, spacing: 1) {
                    Text(tr("Display check")).font(.system(size: 13, weight: .medium)).foregroundStyle(Pal.ink)
                    Text(tr("Matches the UI size on every display to the built-in screen and uses each display's best refresh rate."))
                        .font(.system(size: 12)).foregroundStyle(Pal.ink3).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            if let pending = modes.pendingRevert {
                VStack(alignment: .leading, spacing: 8) {
                    Text(tr("Keep these display settings?")).font(.system(size: 13, weight: .medium)).foregroundStyle(Pal.ink)
                    Text(tr("Going back automatically in \(pending.secondsLeft) s if you do nothing."))
                        .font(.system(size: 12)).foregroundStyle(Pal.warn)
                    HStack(spacing: 8) {
                        JChip(text: tr("Keep"), selected: true) { modes.keepChanges() }
                        JChip(text: tr("Go back now"), selected: false) { modes.revertNow() }
                    }
                }
            } else {
                if modes.checkRan {
                    ForEach(modes.verdicts) { verdict in row(verdict) }
                    if modes.recommendedChanges.isEmpty {
                        Text(tr("No changes needed. Your displays are already set up well."))
                            .font(.system(size: 12, weight: .medium)).foregroundStyle(Pal.ok)
                    }
                    Text(tr("Colors and brightness are not changed: matching them needs a hardware calibrator."))
                        .font(.system(size: 11)).foregroundStyle(Pal.ink3).fixedSize(horizontal: false, vertical: true)
                }
                if let error = modes.batchError {
                    Text(error).font(.system(size: 12)).foregroundStyle(Pal.warn).fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 8) {
                    JChip(text: modes.checkRan ? tr("Check again") : tr("Check displays"), selected: !modes.checkRan) {
                        modes.refresh(displays: displayManager.monitors.filter(\.isConnected).map(\.id))
                        modes.runCheck(names: Dictionary(uniqueKeysWithValues: displayManager.monitors.map { ($0.id, ($0.name, $0.isBuiltIn)) }))
                    }
                    if !modes.recommendedChanges.isEmpty {
                        JChip(text: tr("Apply \(modes.recommendedChanges.count) changes"), selected: true) { modes.applyRecommendations() }
                    }
                    if modes.applyingDisplay != nil { ProgressView().controlSize(.small) }
                }
            }
        }
        .jCard()
    }

    @ViewBuilder private func row(_ v: DisplayVerdict) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(v.name).font(.system(size: 12, weight: .medium)).foregroundStyle(Pal.ink)
                Spacer(minLength: 4)
                Text(v.skipped ? tr("Skipped") : density(v.currentPtPerInch) + (v.recommended != nil && v.resultPtPerInch != nil
                        ? " → " + density(v.resultPtPerInch) : ""))
                    .font(.system(size: 12)).monospacedDigit().foregroundStyle(Pal.ink2)
            }
            if v.skipped {
                Text(tr("Mirrored displays share one mode, or macOS does not report the size."))
                    .font(.system(size: 11)).foregroundStyle(Pal.ink3)
            } else if let recommended = v.recommended {
                Text(tr("Switch to \(modeText(recommended))")).font(.system(size: 11)).foregroundStyle(Pal.accent)
            } else if v.isReference {
                Text(tr("Reference: other displays are matched to this size.")).font(.system(size: 11)).foregroundStyle(Pal.ink3)
            } else if v.isPanelLimited {
                Text(tr("Already the closest this panel can get: it has too few pixels for a larger match."))
                    .font(.system(size: 11)).foregroundStyle(Pal.ink3).fixedSize(horizontal: false, vertical: true)
            } else {
                Text(tr("Already the best match.")).font(.system(size: 11)).foregroundStyle(Pal.ink3)
            }
            if v.isCurrentScaled, let sharpest = v.sharpest {
                Text(tr("This mode is resized by macOS, so text is slightly softer. Sharpest option: \(modeText(sharpest)), but the UI changes size."))
                    .font(.system(size: 11)).foregroundStyle(Pal.ink3).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
