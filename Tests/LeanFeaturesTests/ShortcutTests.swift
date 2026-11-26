// SPDX-License-Identifier: GPL-3.0-only
import Testing
import AppKit
import SwiftUI
@testable import LeanFeatures
import LeanDomain

extension ScreenshotAnnotationTests {
    @MainActor private func shortcutStore() -> (ShortcutManager, UserDefaults, String) {
        let name = "LeanMac.ShortcutTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        return (ShortcutManager(defaults: defaults, publishRuntime: false), defaults, name)
    }
    @Test func shortcutExactModifiersAndKeyboardFlags() {
        let config = ShortcutConfiguration()
        #expect(config.match(18, flags: [.maskCommand, .maskShift])?.action == .screenshot)
        #expect(config.match(18, flags: [.maskCommand, .maskShift, .maskAlternate]) == nil)
        #expect(config.match(18, flags: [.maskCommand, .maskShift, .maskAlphaShift, .maskSecondaryFn])?.action == .screenshot)
        #expect(config.match(131, flags: [])?.action == .screenshot)
        #expect(config.match(123, flags: [.maskControl, .maskAlternate, .maskNumericPad])?.action == .leftHalf)
        #expect(config.match(8, flags: .maskCommand) == nil)
    }
    @Test func switchingReverseAndConflictReservation() {
        var config = ShortcutConfiguration()
        let trigger = ShortcutBinding(40, [.maskControl, .maskAlternate])
        config.bindings[.switchWindows] = [trigger]
        #expect(config.match(40, flags: [.maskControl, .maskAlternate, .maskShift])?.reversed == true)
        #expect(config.match(40, flags: [.maskControl, .maskAlternate])?.binding.holdFlags == [.maskControl, .maskAlternate])
        #expect(config.match(48, flags: .maskCommand) == nil)
        #expect(config.conflict(for: .init(40, [.maskControl, .maskAlternate, .maskShift]), action: .screenshot, replacing: 0) == .switchWindows)
        #expect(ShortcutConfiguration.invalidReason(.init(40, .maskShift), action: .switchWindows) != nil)
        #expect(ShortcutConfiguration.invalidReason(.init(40, [.maskCommand, .maskShift]), action: .switchWindows) != nil)
    }
    @Test @MainActor func shortcutMigrationPersistenceAndDisable() throws {
        let (_, defaults, name) = shortcutStore()
        defer { defaults.removePersistentDomain(forName: name) }
        let manager = ShortcutManager(defaults: defaults, publishRuntime: false)
        let custom = ShortcutBinding(17, [.maskCommand, .maskControl])
        #expect(manager.set(custom, action: .screenshot, index: 0) == nil)
        #expect(manager.configuration.match(18, flags: [.maskCommand, .maskShift]) == nil)
        // Secondary F4 remains visible/editable until explicitly removed.
        manager.remove(.screenshot, index: 1)
        #expect(manager.configuration.match(118, flags: []) == nil)
        manager.disable(.center)
        let reloaded = ShortcutManager(defaults: defaults, publishRuntime: false)
        #expect(reloaded.configuration.match(17, flags: [.maskCommand, .maskControl])?.action == .screenshot)
        #expect(reloaded.configuration.bindings[.center] == [])
        #expect(reloaded.restore(.screenshot) == nil)
        #expect(reloaded.configuration.match(118, flags: [])?.action == .screenshot)
        reloaded.restoreAll()
        #expect(reloaded.configuration.bindings == ShortcutConfiguration().bindings)
    }
    @Test @MainActor func shortcutConflictsDoNotOverwriteBindings() {
        let (manager, defaults, name) = shortcutStore()
        defer { defaults.removePersistentDomain(forName: name) }
        let before = manager.configuration.bindings
        // ⌃⌥8 already belongs to "center": assigning it to screenshot must be rejected and leave the configuration unchanged
        #expect(manager.set(.init(8, [.maskControl, .maskAlternate]), action: .screenshot, index: 0) != nil)
        #expect(manager.configuration.bindings == before)
        manager.disable(.center)
        #expect(manager.set(.init(8, [.maskControl, .maskAlternate]), action: .screenshot, index: 0) == nil)
        #expect(manager.restore(.center) != nil)
        #expect(manager.configuration.bindings[.center] == [])
        #expect(manager.set(.init(0, []), action: .center, index: nil) != nil)
        #expect(manager.set(.init(8, .maskCommand), action: .center, index: nil) != nil)
        #expect(manager.set(.init(49, [.maskCommand, .maskControl]), action: .center, index: nil) == nil)
        #expect(ShortcutConfiguration.systemWarning(.init(49, .maskCommand)) != nil)
        #expect(ShortcutConfiguration.systemWarning(.init(18, [.maskCommand, .maskShift])) == nil)
    }
    @Test @MainActor func corruptShortcutPreferencesFallBackSafely() {
        let (_, defaults, name) = shortcutStore()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(Data("invalid json".utf8), forKey: ShortcutManager.preferencesKey)
        let manager = ShortcutManager(defaults: defaults, publishRuntime: false)
        #expect(manager.configuration.bindings == ShortcutConfiguration().bindings)
    }
    @Test @MainActor func shortcutFeatureTogglePassesDisabledKeysThrough() {
        let original = gShortcutConfiguration, enabled = gIsScreenshotEnabled, snap = gIsWindowSnapEnabled
        defer { gShortcutConfiguration = original; gIsScreenshotEnabled = enabled; gIsWindowSnapEnabled = snap }
        gShortcutConfiguration = ShortcutConfiguration()
        gIsScreenshotEnabled = false
        #expect(configuredShortcutMatch(18, flags: [.maskCommand, .maskShift]) == nil)
        gIsScreenshotEnabled = true
        #expect(configuredShortcutMatch(18, flags: [.maskCommand, .maskShift])?.action == .screenshot)
        gIsWindowSnapEnabled = false
        #expect(configuredShortcutMatch(123, flags: [.maskControl, .maskAlternate]) == nil)
        gIsWindowSnapEnabled = true
        #expect(configuredShortcutMatch(123, flags: [.maskControl, .maskAlternate])?.action == .leftHalf)
        #expect(gShortcutConfiguration.usesDefaultArrowChords)
        gShortcutConfiguration.bindings[.topLeft] = []
        #expect(!gShortcutConfiguration.usesDefaultArrowChords)
    }
    @Test @MainActor func shortcutRecorderSaveCancelRepeatAndFocusLoss() throws {
        let (manager, defaults, name) = shortcutStore()
        let recorder = ShortcutRecorder.shared
        defer { recorder.cancel(); defaults.removePersistentDomain(forName: name) }
        recorder.begin(.screenshot, index: 0, manager: manager)
        #expect(gIsRecordingShortcut)
        recorder.receive(8, flags: [.maskControl, .maskAlternate])
        #expect(recorder.error != nil)
        #expect(!recorder.canSave)
        recorder.receive(17, flags: [.maskCommand, .maskControl])
        #expect(recorder.canSave)
        recorder.receive(18, flags: [], repeated: true)
        #expect(recorder.candidate == .init(17, [.maskCommand, .maskControl]))
        recorder.save()
        #expect(!gIsRecordingShortcut)
        #expect(manager.configuration.match(17, flags: [.maskCommand, .maskControl])?.action == .screenshot)
        let saved = manager.configuration.bindings
        recorder.begin(.center, index: 0, manager: manager)
        recorder.receive(53, flags: [])
        #expect(!gIsRecordingShortcut)
        #expect(manager.configuration.bindings == saved)
        recorder.begin(.center, index: 0, manager: manager)
        recorder.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification))
        #expect(!gIsRecordingShortcut)
        #expect(manager.configuration.bindings == saved)
    }
    @Test @MainActor func shortcutSettingsAndRecordingPreview() throws {
        guard let directory = ProcessInfo.processInfo.environment["JMAC_SHORTCUT_QA_OUT"] else { return }
        let (manager, defaults, name) = shortcutStore()
        defer { ShortcutRecorder.shared.cancel(); defaults.removePersistentDomain(forName: name) }
        func snapshot<V: View>(_ root: V, size: CGSize, name: String) throws {
            let view = NSHostingView(rootView: root.preferredColorScheme(.dark))
            view.frame = CGRect(origin: .zero, size: size)
            let window = NSWindow(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.contentView = view
            window.layoutIfNeeded()
            let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try #require(bitmap.representation(using: .png, properties: [:]))
                .write(to: URL(fileURLWithPath: directory).appendingPathComponent(name + ".png"))
            window.contentView = nil
        }
        try snapshot(ShortcutSettingsView(manager: manager), size: CGSize(width: 480, height: 650), name: "jmac-shortcuts-settings")
        let recorder = ShortcutRecorder.shared
        recorder.begin(.screenshot, index: 0, manager: manager)
        recorder.receive(8, flags: [.maskControl, .maskAlternate])
        try snapshot(ShortcutRecorderView(recorder: recorder), size: CGSize(width: 400, height: 270), name: "jmac-shortcuts-conflict")
        recorder.receive(17, flags: [.maskCommand, .maskControl])
        try snapshot(ShortcutRecorderView(recorder: recorder), size: CGSize(width: 400, height: 270), name: "jmac-shortcuts-valid")
    }
}
