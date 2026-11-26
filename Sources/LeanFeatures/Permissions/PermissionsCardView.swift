// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import AppKit
import LeanDesignSystem
import LeanDomain

// MARK: - Permissions Card View (Centralized Permission Control Hub)

public struct PermissionsCardView: View {
    @ObservedObject var permissionsManager: PermissionsManager

    public init(permissionsManager: PermissionsManager) {
        self.permissionsManager = permissionsManager
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar (Clickable to toggle collapse/expand)
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    permissionsManager.isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill((permissionsManager.allGranted ? Tone.good : Tone.warn).opacity(0.14))
                            .frame(width: 28, height: 28)

                        Image(systemName: permissionsManager.allGranted ? "checkmark.shield" : "exclamationmark.shield")
                            .font(.system(size: FS.title, weight: .regular))
                            .foregroundStyle(permissionsManager.allGranted ? Tone.good : Tone.warn)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 5) {
                            Text(tr("Permissions Hub"))
                                .font(.system(size: FS.label, weight: .semibold))
                                .foregroundStyle(.primary)

                            if !permissionsManager.allGranted {
                                Text(tr("(\(permissionsManager.missingCount) missing)"))
                                    .font(.system(size: FS.caption, weight: .semibold))
                                    .foregroundStyle(Tone.warn)
                            }
                        }

                        Text(permissionsManager.allGranted ? tr("All required system permissions granted") : tr("Click arrow for details & required reasons"))
                            .font(.system(size: FS.caption))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    // Re-scan Button
                    Button {
                        permissionsManager.runDeepProbe()
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: FS.caption))
                                .rotationEffect(.degrees(permissionsManager.isProbing ? 360 : 0))
                                .animation(permissionsManager.isProbing ? Animation.linear(duration: 0.8).repeatForever(autoreverses: false) : .default, value: permissionsManager.isProbing)
                            Text(permissionsManager.isProbing ? tr("Scanning...") : tr("Re-scan"))
                                .font(.system(size: FS.caption))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(RoundedRectangle(cornerRadius: Rad.sm).fill(Color.primary.opacity(0.06)))
                    }
                    .buttonStyle(.plain)
                    .disabled(permissionsManager.isProbing)

                    // Status Pill
                    HStack(spacing: 5) {
                        Circle()
                            .fill(permissionsManager.allGranted ? Tone.good : Tone.bad)
                            .frame(width: 6, height: 6)
                        Text(permissionsManager.allGranted ? tr("All granted") : tr("Missing"))
                            .font(.system(size: FS.caption, weight: .semibold))
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .foregroundStyle(permissionsManager.allGranted ? Tone.good : Tone.bad)

                    // Chevron Down / Up
                    Image(systemName: permissionsManager.isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: FS.caption, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 2)
                }
                .padding(9)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Expanded Permission Details
            if permissionsManager.isExpanded {
                VStack(spacing: 8) {
                    Divider()
                        .padding(.horizontal, 4)

                    // Warning Banner when any permission is missing or was skipped
                    if !permissionsManager.allGranted {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: FS.body))
                                .foregroundStyle(Tone.warn)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tr("Unauthenticated or skipped permissions detected!"))
                                    .font(.system(size: FS.caption, weight: .bold))
                                    .foregroundStyle(Tone.warn)
                                Text(tr("If you clicked 'Cancel' / 'Skip' on Touch ID or haven't enabled in System Settings, features (charge limit, AltTab) will not work. Please click grant buttons below."))
                                    .font(.system(size: FS.caption))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: Rad.sm).fill(Tone.warn.opacity(0.12)))
                    }

                    // 1. Accessibility - required
                    permissionRow(
                        title: tr("1. Accessibility Permission"),
                        tag: tr("REQUIRED"),
                        tagColor: .secondary,
                        icon: "hand.raised.fill",
                        iconColor: .secondary,
                        isGranted: permissionsManager.hasAccessibility,
                        reason: tr("Essential for window snapping (Rectangle), F1/F2 external brightness, AltTab switcher, and Finder Cut & Paste (⌘X ➔ ⌘V)."),
                        actionTitle: tr("Grant Now"),
                        action: {
                            permissionsManager.openAccessibilitySettings()
                        }
                    )

                    // 2. Screen Recording - recommended
                    permissionRow(
                        title: tr("2. Screen Recording Permission"),
                        tag: tr("RECOMMENDED"),
                        tagColor: .secondary,
                        icon: "record.circle",
                        iconColor: .secondary,
                        isGranted: permissionsManager.hasScreenCapture,
                        reason: tr("Used for sharp live window previews in ⌘+Tab. (Without this, AltTab still functions using app icons)."),
                        actionTitle: tr("Open Settings"),
                        action: {
                            permissionsManager.openScreenCaptureSettings()
                        }
                    )

                    // 3. SMC helper (80% charge lock) - hardware
                    let helperVer = BatteryManager.shared.helperVersion
                    let helperActionTitle = (helperVer > 0 && helperVer != PrivilegedHelper.requiredVersion)
                        ? tr("Update to v\(PrivilegedHelper.requiredVersion)")
                        : tr("Install Helper")

                    permissionRow(
                        title: tr("3. Power SMC Control (80% Lock)"),
                        tag: tr("HARDWARE"),
                        tagColor: .secondary,
                        icon: "bolt.batteryblock.fill",
                        iconColor: .secondary,
                        isGranted: permissionsManager.hasSMCHelper,
                        reason: tr("Direct SMC hardware access to hold the charge limit and run directly from the adapter. Requires a one-time admin password / Touch ID."),
                        actionTitle: helperActionTitle,
                        action: {
                            permissionsManager.installSMCHelper()
                        }
                    )

                    // 4. Bluetooth (Sleep Guard) - saves battery
                    permissionRow(
                        title: tr("4. Bluetooth (Sleep Guard)"),
                        tag: tr("BATTERY SAVER"),
                        tagColor: .secondary,
                        icon: "wave.3.forward.circle.fill",
                        iconColor: .secondary,
                        isGranted: permissionsManager.hasBluetooth,
                        reason: tr("Automatically turns off Bluetooth when lid is closed to eliminate overnight battery drain. Quit and reopen LeanMac after granting."),
                        actionTitle: tr("Open Settings"),
                        action: {
                            permissionsManager.openBluetoothSettings()
                        }
                    )
                }
                .padding(.horizontal, 9)
                .padding(.bottom, 9)
                .transition(.opacity)
            }
        }
        .cardBackground()
    }

    // MARK: - Single Permission Row Card

    private func permissionRow(
        title: String,
        tag: String,
        tagColor: Color,
        icon: String,
        iconColor: Color,
        isGranted: Bool,
        reason: String,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: FS.body, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: FS.label, weight: .semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(tag)
                    .font(.system(size: FS.caption, weight: .semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1.5)
                    .background(Capsule().fill(tagColor.opacity(0.12)))
                    .foregroundStyle(tagColor)

                Text(reason)
                    .font(.system(size: FS.caption))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Status / action column: fixed width to its content, no wrapping.
            Group {
                if isGranted {
                    HStack(spacing: 5) {
                        Circle().fill(Tone.good).frame(width: 6, height: 6)
                        Text(tr("Verified"))
                            .font(.system(size: FS.caption, weight: .semibold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(Tone.good)
                } else {
                    VStack(alignment: .trailing, spacing: 3) {
                        HStack(spacing: 4) {
                            Circle().fill(Tone.warn).frame(width: 5, height: 5)
                            Text(tr("Missing / Skipped"))
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Tone.warn)
                                .lineLimit(1)
                        }

                        Button {
                            action()
                        } label: {
                            HStack(spacing: 3) {
                                Text(actionTitle)
                                    .font(.system(size: FS.caption, weight: .semibold))
                                    .lineLimit(1)
                                Image(systemName: "arrow.up.forward.app")
                                    .font(.system(size: FS.caption))
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3.5)
                            .background(RoundedRectangle(cornerRadius: Rad.sm).fill(Color.accentColor))
                            .foregroundStyle(Color.white)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .fixedSize()
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: Rad.sm)
                .fill(isGranted ? Color.primary.opacity(0.02) : Tone.warn.opacity(0.09))
        )
        .overlay(alignment: .leading) {
            if !isGranted {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Tone.warn)
                    .frame(width: 3)
                    .padding(.vertical, 6)
            }
        }
    }
}
