// SPDX-License-Identifier: GPL-3.0-only
// Native hover/focus/pressed/disabled states; selection is immediate, with no async loading.
import SwiftUI
import LeanDesignSystem
import LeanDomain

struct WindowDisplayTransferModeView: View {
    @ObservedObject var settings: WindowDisplayTransferSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tr("When moving to another display"))
                .font(.system(size: FS.label, weight: .medium))
            Picker(tr("Window size when moving across displays"), selection: $settings.mode) {
                Text(tr("Keep window size"))
                    .tag(WindowDisplayTransferMode.keepSize)
                Text(tr("Scale with display"))
                    .tag(WindowDisplayTransferMode.proportional)
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            .font(.system(size: FS.body))
            .accessibilityIdentifier("windowDisplayTransferMode")
            Text(settings.mode == .keepSize
                 ? tr("Keep ordinary window sizes, shrinking only to fit. Edge-spanning or maximized windows adapt to the destination.")
                 : tr("Scale width and height with the destination display. Keep half-screen and corner layouts."))
                .font(.system(size: FS.caption))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(tr("Saved automatically · Applies on the next display move"))
                .font(.system(size: FS.caption))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
