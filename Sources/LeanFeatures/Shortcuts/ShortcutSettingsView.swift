// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import SwiftUI
import LeanDesignSystem
import LeanDomain

// Native focus/pressed/disabled states; recording, conflict, warning and saved states.
struct ShortcutSettingsCard: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "keyboard").foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 3) {
                Text(tr("Customize shortcuts")).font(.system(size: FS.body, weight: .semibold))
                Text(tr("Change, add or disable key combinations"))
                    .font(.system(size: FS.caption)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Button(tr("Customize…")) { ShortcutSettingsWindow.shared.show() }
                .controlSize(.small)
        }.padding(10).cardBackground()
    }
}

@MainActor
final class ShortcutSettingsWindow: NSObject, NSWindowDelegate {
    static let shared = ShortcutSettingsWindow()
    private var window: NSWindow?
    func show() {
        if let window { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 650),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = tr("LeanMac shortcuts")
        window.contentMinSize = NSSize(width: 400, height: 400)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: ShortcutSettingsView(manager: .shared))
        self.window = window
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
    func windowWillClose(_ notification: Notification) { ShortcutRecorder.shared.cancel(); window = nil }
}

struct ShortcutSettingsView: View {
    @ObservedObject var manager: ShortcutManager
    private let groups: [(String, [ShortcutAction])] = [
        (tr("Open features"), [.screenshot, .switchWindows]),
        (tr("Arrange windows"), [.leftHalf, .rightHalf, .topHalf, .bottomHalf, .maximize, .center, .restoreWindow, .topLeft, .topRight, .bottomLeft, .bottomRight]),
        (tr("Displays"), [.nextDisplay, .previousDisplay])
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(tr("Your shortcuts")).font(.system(size: FS.value, weight: .semibold))
            Text(tr("Click a combination to change it. Use + to add, × to remove. Shortcuts work when their feature is enabled."))
                .font(.system(size: FS.body)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(groups, id: \.0) { group in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(group.0).font(.system(size: FS.title, weight: .semibold)).foregroundStyle(.secondary)
                            ForEach(group.1) { action in row(action) }
                        }
                    }
                    Text(tr("Window switching: hold modifiers, add Shift to cycle backward, release modifiers to select. ⌘C, ⌘Z, Esc and editor navigation stay unchanged."))
                        .font(.system(size: FS.caption)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Text(tr("LeanMac checks its own bindings and warns about common macOS shortcuts. Other apps may still use the same keys."))
                        .font(.system(size: FS.caption)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.padding(.trailing, 4)
            }
            if let message = manager.settingsMessage { Text(message).font(.system(size: FS.body)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
            Divider()
            HStack {
                Text(tr("Saved automatically")).font(.system(size: FS.caption)).foregroundStyle(.secondary)
                Spacer()
                Button(tr("Restore all defaults")) { manager.restoreAll(); manager.settingsMessage = nil }
                    .disabled(manager.configuration.bindings == ShortcutConfiguration().bindings)
            }
        }.padding(18).frame(minWidth: 360, minHeight: 360)
    }
    private func row(_ action: ShortcutAction) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(action.title).font(.system(size: FS.body, weight: .medium))
                Spacer()
                Button { ShortcutRecorder.shared.begin(action, index: nil, manager: manager) } label: { Image(systemName: "plus") }
                    .help(tr("Add shortcut")).accessibilityLabel(tr("Add shortcut for \(action.title)"))
                Menu {
                    Button(tr("Disable shortcuts for this action")) { manager.disable(action); manager.settingsMessage = nil }
                    Button(tr("Restore defaults")) { manager.settingsMessage = manager.restore(action) }
                } label: { Image(systemName: "ellipsis") }
                .menuStyle(.borderlessButton).frame(width: 22)
                .accessibilityLabel(tr("Options for \(action.title)"))
            }
            let values = manager.configuration.bindings[action] ?? []
            if values.isEmpty {
                Text(tr("Shortcut disabled")).font(.system(size: FS.caption)).foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), alignment: .leading)], alignment: .leading, spacing: 6) {
                    ForEach(Array(values.enumerated()), id: \.offset) { index, binding in
                        HStack(spacing: 2) {
                            Button(binding.title) { ShortcutRecorder.shared.begin(action, index: index, manager: manager) }
                                .font(.system(size: FS.body, weight: .medium, design: .monospaced))
                                .help(tr("Click to change shortcut"))
                                .accessibilityLabel("\(action.title): \(binding.title)")
                            Button { manager.remove(action, index: index); manager.settingsMessage = nil } label: { Image(systemName: "xmark") }
                                .accessibilityLabel(tr("Remove \(binding.title)"))
                        }.controlSize(.small)
                    }
                }
            }
            Divider()
        }
    }
}

@MainActor
final class ShortcutRecorder: NSObject, ObservableObject, NSWindowDelegate {
    static let shared = ShortcutRecorder()
    @Published private(set) var candidate: ShortcutBinding?
    @Published private(set) var error: String?
    @Published private(set) var action: ShortcutAction = .screenshot
    private var index: Int?
    private var manager: ShortcutManager?
    private var panel: NSPanel?
    private var monitor: Any?
    var warning: String? { candidate.flatMap(ShortcutConfiguration.systemWarning) }
    var canSave: Bool { candidate != nil && error == nil }
    func begin(_ action: ShortcutAction, index: Int?, manager: ShortcutManager) {
        cancel()
        self.action = action; self.index = index; self.manager = manager
        candidate = nil; error = nil
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 270),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = action.title
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: ShortcutRecorderView(recorder: self))
        self.panel = panel
        panel.center()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        gIsRecordingShortcut = true
        // Fallback for local keyboard input if Accessibility/event tap is unavailable.
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel?.isKeyWindow == true else { return event }
            self.receive(event.keyCode, flags: event.cgEvent?.flags ?? [], repeated: event.isARepeat)
            return nil
        }
    }
    func receive(_ code: UInt16, flags: CGEventFlags, repeated: Bool = false) {
        guard panel != nil, !repeated else { return }
        let binding = ShortcutBinding(code, flags)
        if code == 53 && binding.flags.isEmpty { cancel(); return }
        candidate = binding
        error = manager?.error(for: binding, action: action, index: index)
    }
    func save() {
        guard let candidate, canSave, let manager else { return }
        if let failure = manager.set(candidate, action: action, index: index) { error = failure; return }
        cancel()
    }
    func cancel() {
        gIsRecordingShortcut = false
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        let previous = panel
        panel = nil
        previous?.delegate = nil
        previous?.close()
        manager = nil
    }
    func windowWillClose(_ notification: Notification) { cancel() }
    func windowDidResignKey(_ notification: Notification) { cancel() }
}

struct ShortcutRecorderView: View {
    @ObservedObject var recorder: ShortcutRecorder
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(tr("Press a new key combination"))
                .font(.system(size: FS.subhead, weight: .semibold))
            Text(recorder.candidate?.title ?? tr("Waiting for keys…"))
                .font(.system(size: FS.display, weight: .medium, design: .monospaced))
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(RoundedRectangle(cornerRadius: Rad.md).fill(Color.primary.opacity(0.06)))
            Text(recorder.error ?? recorder.warning ?? tr("Press a combination, then click Save. Esc cancels."))
                .font(.system(size: FS.body))
                .foregroundStyle(recorder.error != nil || recorder.warning != nil ? Color.orange : Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .topLeading)
            HStack {
                Button(tr("Cancel")) { recorder.cancel() }
                Spacer()
                Button(tr("Save")) { recorder.save() }.disabled(!recorder.canSave)
            }
        }.padding(20).frame(width: 400)
    }
}
