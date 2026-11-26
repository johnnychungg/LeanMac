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

    @State private var expanded = false
    @State private var showDetails = false

    private var summary: String {
        if modes.pendingRevert != nil { return tr("Waiting for your confirmation") }
        guard modes.checkRan else { return tr("Match UI size and refresh rate") }
        let n = modes.recommendedChanges.count
        return n == 0 ? tr("All displays are set up well") : tr("\(n) changes suggested")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { withAnimation(.easeOut(duration: 0.15)) { expanded.toggle() } } label: {
                HStack(spacing: 10) {
                    JIcon(name: "checkmark.seal")
                    VStack(alignment: .leading, spacing: 1) {
                        Text(tr("Display check")).font(.system(size: 13, weight: .medium)).foregroundStyle(Pal.ink)
                        Text(summary).font(.system(size: 12))
                            .foregroundStyle(modes.checkRan && modes.recommendedChanges.isEmpty ? Pal.ok : Pal.ink3)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down").font(.system(size: 11, weight: .medium)).foregroundStyle(Pal.ink3)
                        .rotationEffect(.degrees(expanded || modes.pendingRevert != nil ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded || modes.pendingRevert != nil {
                content
            }
        }
        .jCard()
    }

    @ViewBuilder private var content: some View {
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
                VStack(spacing: 6) { ForEach(modes.verdicts) { verdict in row(verdict) } }
                if showDetails {
                    Text(tr("Colors and brightness are not changed: matching them needs a hardware calibrator."))
                        .font(.system(size: 11)).foregroundStyle(Pal.ink3).fixedSize(horizontal: false, vertical: true)
                }
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
                if modes.checkRan {
                    JChip(text: showDetails ? tr("Hide details") : tr("Details"), selected: false) { showDetails.toggle() }
                }
                if modes.applyingDisplay != nil { ProgressView().controlSize(.small) }
            }
        }
    }

    /// One short line per display; the long explanations appear under "Details".
    private func status(_ v: DisplayVerdict) -> (text: String, color: Color) {
        if v.skipped { return (tr("Skipped"), Pal.ink3) }
        if let recommended = v.recommended { return (tr("Switch to \(modeText(recommended))"), Pal.accent) }
        if v.isReference { return (tr("Reference"), Pal.ink3) }
        if v.isPanelLimited { return (tr("Panel limit"), Pal.ink3) }
        return (tr("Best match"), Pal.ok)
    }

    @ViewBuilder private func row(_ v: DisplayVerdict) -> some View {
        let st = status(v)
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(v.name).font(.system(size: 12, weight: .medium)).foregroundStyle(Pal.ink).lineLimit(1)
                Spacer(minLength: 4)
                Text(st.text).font(.system(size: 11)).foregroundStyle(st.color).lineLimit(1)
                Text(v.skipped ? "–" : density(v.currentPtPerInch) + (v.recommended != nil && v.resultPtPerInch != nil
                        ? " → " + density(v.resultPtPerInch) : ""))
                    .font(.system(size: 12)).monospacedDigit().foregroundStyle(Pal.ink2).lineLimit(1)
            }
            if showDetails {
                if v.skipped {
                    Text(tr("Mirrored displays share one mode, or macOS does not report the size."))
                        .font(.system(size: 11)).foregroundStyle(Pal.ink3).fixedSize(horizontal: false, vertical: true)
                } else if v.isPanelLimited {
                    Text(tr("Already the closest this panel can get: it has too few pixels for a larger match."))
                        .font(.system(size: 11)).foregroundStyle(Pal.ink3).fixedSize(horizontal: false, vertical: true)
                } else if v.isReference {
                    Text(tr("Reference: other displays are matched to this size.")).font(.system(size: 11)).foregroundStyle(Pal.ink3)
                }
                if v.isCurrentScaled, let sharpest = v.sharpest {
                    Text(tr("This mode is resized by macOS, so text is slightly softer. Sharpest option: \(modeText(sharpest)), but the UI changes size."))
                        .font(.system(size: 11)).foregroundStyle(Pal.ink3).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
