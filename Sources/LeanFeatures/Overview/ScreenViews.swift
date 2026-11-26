// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import LeanDesignSystem
import LeanDomain

// MARK: - Display card

struct DisplayCard: View {
    let monitor: DisplayInfo
    @ObservedObject var displayManager: DisplayManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: monitor.isBuiltIn ? "laptopcomputer" : "display")
                    .font(.system(size: 20)).foregroundStyle(Pal.accent).frame(width: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(monitor.name).font(.system(size: 13, weight: .medium)).foregroundStyle(Pal.ink).lineLimit(1)
                    Text("\(monitor.resolution) · " + (monitor.isBuiltIn ? tr("Built-in") : tr("External")))
                        .font(.system(size: 12)).foregroundStyle(Pal.ink3).lineLimit(1)
                }
                Spacer(minLength: 4)
                Text("\(Int(round(monitor.brightness * 100)))%")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(Pal.ink)
            }
            if monitor.isConnected {
                HStack(spacing: 8) {
                    Image(systemName: "sun.min").font(.system(size: 12)).foregroundStyle(Pal.ink3)
                    Slider(value: Binding(get: { monitor.brightness }, set: { displayManager.setBrightness($0, for: monitor) }), in: 0...1)
                        .tint(Pal.accent)
                        .controlSize(.small)
                    Image(systemName: "sun.max").font(.system(size: 13)).foregroundStyle(Pal.ink3)
                }
                DisplayModeControls(displayID: monitor.id, manager: .shared) { EmptyView() }
            } else {
                Text(tr("Display is off")).font(.system(size: 12)).foregroundStyle(Pal.ink3)
            }
        }
        .jCard()
    }
}

// MARK: - System permissions strip

struct PermissionsStrip: View {
    @ObservedObject var permissionsManager: PermissionsManager
    var alwaysOpen: Bool = false
    @ObservedObject private var ui = UIState.shared

    private struct Item: Identifiable {
        let id: String
        let title: String
        let required: Bool
        let granted: Bool
        let action: () -> Void
        var actionTitle: String
    }

    private var items: [Item] {
        [
            Item(id: "ax", title: tr("Accessibility"), required: true, granted: permissionsManager.hasAccessibility,
                 action: { permissionsManager.openAccessibilitySettings() }, actionTitle: tr("Open")),
            Item(id: "sc", title: tr("Screen recording"), required: false, granted: permissionsManager.hasScreenCapture,
                 action: { permissionsManager.openScreenCaptureSettings() }, actionTitle: tr("Open")),
            Item(id: "smc", title: tr("SMC power (charge limit)"), required: false, granted: permissionsManager.hasSMCHelper,
                 action: { permissionsManager.installSMCHelper() }, actionTitle: tr("Install")),
            Item(id: "bt", title: "Bluetooth (Sleep Guard)", required: false, granted: permissionsManager.hasBluetooth,
                 action: { permissionsManager.openBluetoothSettings() }, actionTitle: tr("Open"))
        ]
    }

    var body: some View {
        let missing = items.filter { !$0.granted }
        let allOK = missing.isEmpty
        VStack(spacing: 0) {
            if !alwaysOpen {
            Button { withAnimation(.easeOut(duration: 0.15)) { ui.permissionsOpen.toggle() } } label: {
                HStack(spacing: 8) {
                    Image(systemName: allOK ? "checkmark.shield" : "exclamationmark.shield").font(.system(size: 14))
                    Text(allOK
                         ? tr("All permissions granted")
                         : tr("Permissions \(items.count - missing.count)/\(items.count), missing \(missing.map { $0.title.components(separatedBy: " (").first ?? $0.title }.joined(separator: ", "))"))
                        .font(.system(size: 12))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(2)
                    Image(systemName: ui.permissionsOpen ? "chevron.up" : "chevron.down").font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(allOK ? Pal.ok : Pal.warn)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(allOK ? Pal.okBg : Pal.warnBg))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            }

            if alwaysOpen || ui.permissionsOpen {
                VStack(spacing: 0) {
                    ForEach(items) { item in
                        HStack(spacing: 10) {
                            Circle().fill(item.granted ? Pal.ok : Pal.warn).frame(width: 8, height: 8)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(item.title).font(.system(size: 13)).foregroundStyle(Pal.ink)
                                if item.required {
                                    Text(tr("Required")).font(.system(size: 11)).foregroundStyle(Pal.ink3)
                                }
                            }
                            Spacer()
                            if item.granted {
                                Text(tr("Granted")).font(.system(size: 12)).foregroundStyle(Pal.ink3)
                            } else {
                                JChip(text: item.actionTitle, selected: true, action: item.action)
                            }
                        }
                        .padding(.vertical, 8)
                        if item.id != items.last?.id { JDivider() }
                    }
                    JDivider()
                    HStack {
                        Spacer()
                        JChip(text: permissionsManager.isProbing ? tr("Scanning…") : tr("Rescan"), icon: "arrow.clockwise") {
                            permissionsManager.runDeepProbe()
                        }
                    }
                    .padding(.top, 8)
                }
                .padding(.horizontal, 12).padding(.vertical, 4)
                .padding(.bottom, 4)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Pal.card))
                .padding(.top, 8)
            }
        }
    }
}

// MARK: - Key bindings (embedded in the popover)

struct ShortcutMapView: View {
    @ObservedObject var manager: ShortcutManager

    private let groups: [(String, [ShortcutAction])] = [
        (tr("Open features"), [.screenshot, .switchWindows]),
        (tr("Arrange windows"), [.leftHalf, .rightHalf, .topHalf, .bottomHalf, .maximize, .center, .restoreWindow, .topLeft, .topRight, .bottomLeft, .bottomRight]),
        (tr("Displays"), [.nextDisplay, .previousDisplay])
    ]

    var body: some View {
        ForEach(groups, id: \.0) { group in
            VStack(alignment: .leading, spacing: 0) {
                Text(group.0).font(.system(size: 13, weight: .medium)).foregroundStyle(Pal.ink).padding(.vertical, 8)
                ForEach(group.1) { action in
                    JDivider()
                    row(action)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Pal.card))
        }

        if let message = manager.settingsMessage {
            Text(message).font(.system(size: 12)).foregroundStyle(Pal.warn)
                .frame(maxWidth: .infinity, alignment: .leading)
        }

        Button { manager.restoreAll(); manager.settingsMessage = nil } label: {
            HStack(spacing: 6) { Image(systemName: "arrow.counterclockwise"); Text(tr("Restore defaults")) }
        }
        .buttonStyle(JButtonStyle(kind: .ghost))
        .disabled(manager.configuration.bindings == ShortcutConfiguration().bindings)
    }

    private func row(_ action: ShortcutAction) -> some View {
        let values = manager.configuration.bindings[action] ?? []
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(action.title).font(.system(size: 13)).foregroundStyle(Pal.ink)
                Spacer()
                Button { ShortcutRecorder.shared.begin(action, index: nil, manager: manager) } label: {
                    Image(systemName: "plus").font(.system(size: 12, weight: .medium)).foregroundStyle(Pal.ink2)
                }
                .buttonStyle(.plain)
                .help(tr("Add shortcut"))
                Menu {
                    Button(tr("Disable shortcuts for this action")) { manager.disable(action); manager.settingsMessage = nil }
                    Button(tr("Restore defaults")) { manager.settingsMessage = manager.restore(action) }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 12)).foregroundStyle(Pal.ink2)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 20)
            }
            if values.isEmpty {
                Text(tr("Disabled")).font(.system(size: 12)).foregroundStyle(Pal.ink3)
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(Array(values.enumerated()), id: \.offset) { index, binding in
                        HStack(spacing: 4) {
                            Button { ShortcutRecorder.shared.begin(action, index: index, manager: manager) } label: {
                                Text(binding.title).font(.system(size: 12, weight: .medium, design: .monospaced)).foregroundStyle(Pal.ink)
                            }
                            .buttonStyle(.plain)
                            .help(tr("Click to change"))
                            Button { manager.remove(action, index: index); manager.settingsMessage = nil } label: {
                                Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Pal.ink3)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Pal.bg)
                                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Pal.lineStrong, lineWidth: 0.5))
                        )
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }
}
