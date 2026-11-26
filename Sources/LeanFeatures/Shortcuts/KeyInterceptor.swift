// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import CoreGraphics
import AppKit
import LeanDomain

// Apple standard definitions from ev_keymap.h:
private let NX_SYSDEFINED: UInt32 = 14
private let NX_KEYTYPE_BRIGHTNESS_UP: Int32 = 2
private let NX_KEYTYPE_BRIGHTNESS_DOWN: Int32 = 3

// Fast lock-free flags for eventTapCallback
public var gIsAltTabEnabled: Bool = true
public var gIsAltTabVisible: Bool = false
public var gIsCursorBasedBrightnessEnabled: Bool = true
public var gIsScreenshotEnabled: Bool = true
public var gIsScreenshotActive: Bool = false
public var gIsScreenshotEditingText: Bool = false
public var gIsSpacePressed: Bool = false
private var gActiveModifierMask: CGEventFlags? = nil
private var gCurrentTap: CFMachPort? = nil
private var gLastSnapArrowKey: Int64 = 0
private var gLastSnapArrowTime: TimeInterval = 0



// MARK: - Event Tap Callback (Session level, zero main-sync)
//
// The tap only borrows `event` from WindowServer — always hand it back with
// passUnretained. passRetained adds an extra retain that is never balanced, so
// every key/mouse event (plus its HIDEvent) leaks and memory grows forever.

private func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    // 0. Synthetic event bypass: allow LeanMac-synthesized events (e.g. Cmd+C, Opt+Cmd+V) to pass through without interception
    if gIsSynthesizingEvent {
        return Unmanaged.passUnretained(event)
    }

    // 1. Safety handler for system tap disable
    if type == .tapDisabledByUserInput {
        // User revoked permission in System Settings -> STOP cleanly! Do NOT fight WindowServer!
        appLog("⚠️ EventTap was disabled by user/system in Accessibility settings. Stopping.")
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                KeyInterceptor.shared.stop()
            }
        }
        return Unmanaged.passUnretained(event)
    }

    if type == .tapDisabledByTimeout {
        // Timeout from macOS -> Re-enable safely
        if let tap = gCurrentTap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        // Key-up events may have been missed while the tap was off: drop any half-finished HUD interaction
        // so the switcher cannot stay open waiting for a modifier release that already happened.
        if gIsAltTabVisible {
            gIsAltTabVisible = false
            gActiveModifierMask = nil
            DispatchQueue.main.async { WindowManager.shared.cancel() }
        }
        return Unmanaged.passUnretained(event)
    }

    // Recording owns keyboard events before any global shortcuts or HUD navigation.
    if gIsRecordingShortcut {
        if type == .keyDown {
            let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            let flags = event.flags
            let repeated = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            DispatchQueue.main.async { ShortcutRecorder.shared.receive(code, flags: flags, repeated: repeated) }
            return nil
        }
        if type == .keyUp || type == .flagsChanged { return nil }
    }

    // Let the native text editor receive typing, Space, IME, clipboard and undo keys.
    // Escape/Return are handled by the editor; mouse events still follow the normal tap path.
    if gIsScreenshotActive && gIsScreenshotEditingText &&
        (type == .keyDown || type == .keyUp || type == .flagsChanged) {
        return Unmanaged.passUnretained(event)
    }

    if type == .flagsChanged {
        let flags = event.flags
        if !flags.contains(.maskControl) || !flags.contains(.maskAlternate) {
            gLastSnapArrowKey = 0
            gLastSnapArrowTime = 0
        }
    }

    // One shared, exact-match registry drives all configurable global shortcuts.
    if type == .keyDown && !gIsScreenshotActive,
       let match = configuredShortcutMatch(UInt16(event.getIntegerValueField(.keyboardEventKeycode)), flags: event.flags) {
        if match.action == .switchWindows {
            gActiveModifierMask = match.binding.holdFlags
            gIsAltTabVisible = true
            DispatchQueue.main.async { WindowManager.shared.handleShortcut(isShift: match.reversed) }
        } else {
            var action = match.action
            let key = Int64(match.binding.keyCode)
            if gShortcutConfiguration.usesDefaultArrowChords && (123...126).contains(key) &&
                match.binding.flags == [.maskControl, .maskAlternate] {
                let now = Date().timeIntervalSince1970
                if now - gLastSnapArrowTime <= 0.65 && gLastSnapArrowKey != key {
                    let pair = Set([gLastSnapArrowKey, key])
                    if pair == Set([123,126]) { action = .topLeft }
                    else if pair == Set([124,126]) { action = .topRight }
                    else if pair == Set([123,125]) { action = .bottomLeft }
                    else if pair == Set([124,125]) { action = .bottomRight }
                }
                gLastSnapArrowKey = action == match.action ? key : 0
                gLastSnapArrowTime = now
            } else { gLastSnapArrowKey = 0 }
            // Holding a trigger should not repeatedly toggle a panel on/off.
            let repeats = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            if !repeats || action.snapAction != nil {
                let requested = action
                DispatchQueue.main.async { ShortcutManager.shared.perform(requested) }
            }
        }
        return nil
    }

    // 3. AltTab Window Switching (Command + Tab or Option + Tab)
    if gIsAltTabEnabled && !gIsScreenshotActive {
        if type == .flagsChanged {
            let flags = event.flags
            if let activeMask = gActiveModifierMask {
                let isStillHeld = flags.intersection(activeMask) == activeMask

                if !isStillHeld {
                    gActiveModifierMask = nil
                    if gIsAltTabVisible {
                        gIsAltTabVisible = false
                        DispatchQueue.main.async {
                            WindowManager.shared.handleModifierReleased()
                        }
                    }
                }
            }
        }

        if type == .keyDown {
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

            // Keyboard navigation when AltTab HUD is active
            if gIsAltTabVisible {
                if keyCode == 53 { // Esc
                    gIsAltTabVisible = false
                    gActiveModifierMask = nil
                    DispatchQueue.main.async {
                        WindowManager.shared.cancel()
                    }
                    return nil
                } else if keyCode == 50 { // ` or ~ (Tilde) -> cycle backward
                    DispatchQueue.main.async {
                        WindowManager.shared.selectPrevious()
                    }
                    return nil
                } else if keyCode == 123 { // Left Arrow
                    DispatchQueue.main.async {
                        WindowManager.shared.selectPrevious()
                    }
                    return nil
                } else if keyCode == 124 { // Right Arrow
                    DispatchQueue.main.async {
                        WindowManager.shared.selectNext()
                    }
                    return nil
                } else if keyCode == 126 { // Up Arrow -> Move to row above
                    DispatchQueue.main.async {
                        WindowManager.shared.selectUp()
                    }
                    return nil
                } else if keyCode == 125 { // Down Arrow -> Move to row below
                    DispatchQueue.main.async {
                        WindowManager.shared.selectDown()
                    }
                    return nil
                } else if keyCode == 13 { // W key (Close window)
                    DispatchQueue.main.async {
                        WindowManager.shared.closeSelectedWindow()
                    }
                    return nil
                } else if keyCode == 12 { // Q key (Quit app)
                    DispatchQueue.main.async {
                        WindowManager.shared.quitSelectedApp()
                    }
                    return nil
                }
            }
        }
    }

    // 4. Media Keys (Brightness UP/DOWN F1/F2)
    if type.rawValue == NX_SYSDEFINED {
        guard let nsEvent = NSEvent(cgEvent: event) else {
            return Unmanaged.passUnretained(event)
        }

        if nsEvent.subtype.rawValue == 8 {
            let data1 = nsEvent.data1
            let keyCode = Int32((data1 & 0xFFFF0000) >> 16)
            let keyFlags = (data1 & 0x0000FFFF)
            let keyState = (((keyFlags & 0xFF00) >> 8)) == 0x0A

            if keyState && (keyCode == NX_KEYTYPE_BRIGHTNESS_UP || keyCode == NX_KEYTYPE_BRIGHTNESS_DOWN) {
                // If cursor-based brightness is disabled, do NOT intercept! Pass through to macOS native.
                if !gIsCursorBasedBrightnessEnabled {
                    return Unmanaged.passUnretained(event)
                }
                let isUp = (keyCode == NX_KEYTYPE_BRIGHTNESS_UP)
                DispatchQueue.main.async {
                    _ = DisplayManager.shared.handleBrightnessKey(isUp: isUp)
                }
                // Return nil if external monitor was targeted or pass to macOS
                return nil
            }
        }
    }

    // 5. Spacebar tracking for Screenshot Mode (Holding Space to Move Selection)
    if type == .keyDown || type == .keyUp {
        let keycode = event.getIntegerValueField(.keyboardEventKeycode)
        if keycode == 49 { // Space
            let isDown = (type == .keyDown)
            if gIsSpacePressed != isDown {
                gIsSpacePressed = isDown
                DispatchQueue.main.async {
                    ScreenshotManager.shared.isSpaceHeld = isDown
                }
            }
            if gIsScreenshotActive {
                return nil // Swallow Space in screenshot mode
            }
        }
    }

    // 6. Standard F1/F2 KeyDowns & Window Snapping
    if type == .keyDown {
        let keycode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        // Screenshot Active Hotkeys (LightShot Mode: Esc to cancel, ⌘C to copy, ⌘V/⌘S to save, ⌘Z to undo)
        if gIsScreenshotActive {
            let hasCmd = flags.contains(.maskCommand)
            let hasCtrl = flags.contains(.maskControl)
            let hasAlt = flags.contains(.maskAlternate)
            let hasShift = flags.contains(.maskShift)

            // Esc (keycode 53) -> Cancel capture
            if keycode == 53 && !hasCmd && !hasCtrl && !hasAlt && !hasShift {
                DispatchQueue.main.async {
                    ScreenshotManager.shared.cancelCapture()
                }
                return nil
            }

            // ⌘C (keycode 8) -> Copy high-res cropped screenshot to clipboard
            if hasCmd && !hasCtrl && !hasAlt && !hasShift && keycode == 8 {
                DispatchQueue.main.async {
                    ScreenshotManager.shared.copyToClipboard()
                }
                return nil
            }

            // ⌘V (keycode 9) -> Save high-res screenshot to Downloads/Screenshots
            if hasCmd && !hasCtrl && !hasAlt && !hasShift && keycode == 9 {
                DispatchQueue.main.async {
                    ScreenshotManager.shared.saveToDownloads()
                }
                return nil
            }

            // ⌘S (keycode 1) -> Save high-res screenshot to Downloads/Screenshots
            if hasCmd && !hasCtrl && !hasAlt && !hasShift && keycode == 1 {
                DispatchQueue.main.async {
                    ScreenshotManager.shared.saveToDownloads()
                }
                return nil
            }

            // ⌘Z (keycode 6) -> Undo last stroke
            if hasCmd && !hasCtrl && !hasAlt && !hasShift && keycode == 6 {
                DispatchQueue.main.async {
                    ScreenshotManager.shared.undoLastStroke()
                }
                return nil
            }

            // Tab (keycode 48) -> Switch to next screen if multiple displays connected
            if !hasCmd && !hasCtrl && !hasAlt && !hasShift && keycode == 48 {
                DispatchQueue.main.async {
                    ScreenshotManager.shared.switchScreen()
                }
                return nil
            }

            // In screenshot mode, swallow all other bare typing to prevent accidental shortcuts
            return nil
        }

        // F1/F2 Brightness
        if keycode == 145 || keycode == 120 || keycode == 144 || keycode == 122 {
            // If cursor-based brightness is disabled, do NOT intercept! Pass through to macOS native.
            if !gIsCursorBasedBrightnessEnabled {
                return Unmanaged.passUnretained(event)
            }
            let isUp = (keycode == 145 || keycode == 120)
            DispatchQueue.main.async {
                _ = DisplayManager.shared.handleBrightnessKey(isUp: isUp)
            }
            return nil
        }

        // Finder Cut & Paste (Windows-style ⌘X ➔ ⌘V)
        if gIsFinderCutPasteEnabled {
            let hasCmd = flags.contains(.maskCommand)
            let hasCtrl = flags.contains(.maskControl)
            let hasAlt = flags.contains(.maskAlternate)
            let hasShift = flags.contains(.maskShift)

            // Esc (keycode 53) -> Cancel pending cut in Finder
            if keycode == 53 && gIsFinderCutActive && !hasCmd && !hasCtrl && !hasAlt {
                if FinderCutPasteManager.isFinderFrontmost() {
                    DispatchQueue.main.async {
                        FinderCutPasteManager.shared.cancelCut(quiet: false)
                    }
                    return nil
                }
            }

            // Command-only shortcuts (no Option, no Control, no Shift)
            if hasCmd && !hasCtrl && !hasAlt && !hasShift {
                // ⌘X (keycode 7) -> Cut file(s) in Finder
                if keycode == 7 {
                    if FinderCutPasteManager.isFinderFrontmost() {
                        if !FinderCutPasteManager.isFinderEditingText() {
                            DispatchQueue.main.async {
                                FinderCutPasteManager.shared.triggerCut()
                            }
                            return nil // Swallow ⌘X so macOS doesn't beep
                        }
                    }
                }

                // ⌘V (keycode 9) -> Paste/Move cut file(s) in Finder
                if keycode == 9 && gIsFinderCutActive {
                    if FinderCutPasteManager.isFinderFrontmost() {
                        if !FinderCutPasteManager.isFinderEditingText() {
                            DispatchQueue.main.async {
                                FinderCutPasteManager.shared.triggerPaste()
                            }
                            return nil // Swallow ⌘V
                        }
                    }
                }

                // ⌘C (keycode 8) -> Manual copy cancels any cut state
                if keycode == 8 && gIsFinderCutActive {
                    DispatchQueue.main.async {
                        FinderCutPasteManager.shared.cancelCut(quiet: true)
                    }
                }
            }
        }

    }

    return Unmanaged.passUnretained(event)
}

// Kept separate from dispatch so matching/feature toggles can be tested without moving windows.
func configuredShortcutMatch(_ key: UInt16, flags: CGEventFlags) -> ShortcutMatch? {
    guard let match = gShortcutConfiguration.match(key, flags: flags) else { return nil }
    let enabled: Bool
    switch match.action {
    case .screenshot: enabled = gIsScreenshotEnabled
    case .switchWindows: enabled = gIsAltTabEnabled
    default: enabled = gIsWindowSnapEnabled
    }
    return enabled ? match : nil
}

// MARK: - KeyInterceptor Singleton

@MainActor
public class KeyInterceptor {
    public static let shared = KeyInterceptor()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    public var currentTap: CFMachPort? {
        return eventTap
    }

    private init() {}

    public func updateSettings() {
        gIsAltTabEnabled = (UserDefaults.standard.object(forKey: "alttab_enabled") as? Bool) ?? true
        gIsFinderCutPasteEnabled = (UserDefaults.standard.object(forKey: "finder_cut_paste_enabled") as? Bool) ?? true
        gShortcutConfiguration = ShortcutManager.shared.configuration
        gIsWindowSnapEnabled = (UserDefaults.standard.object(forKey: "window_snap_enabled") as? Bool) ?? true
        gIsCursorBasedBrightnessEnabled = (UserDefaults.standard.object(forKey: "cursor_based_brightness") as? Bool) ?? true
        gIsScreenshotEnabled = (UserDefaults.standard.object(forKey: "screenshot_enabled") as? Bool) ?? true
    }

    private var tapRetryCount = 0

    public func start() {
        guard eventTap == nil else { return }

        updateSettings()

        // Listen for Media Keys, KeyDowns, KeyUps, FlagsChanged, and 
        let keyMask: UInt64 = (UInt64(1) << UInt64(NX_SYSDEFINED)) |
                              (UInt64(1) << UInt64(CGEventType.keyDown.rawValue)) |
                              (UInt64(1) << UInt64(CGEventType.keyUp.rawValue)) |
                              (UInt64(1) << UInt64(CGEventType.flagsChanged.rawValue))
        let mask: UInt64 = keyMask

        // EXCLUSIVELY use .cgSessionEventTap for user-session safety!
        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: eventTapCallback,
            userInfo: nil
        )

        guard let validTap = tap else {
            let trusted = AXIsProcessTrusted()
            // Back off (1.5s, 3s, … capped at 30s) and log only the first failure, so a missing permission
            // does not spam the log or wake the app every 1.5 seconds forever.
            if tapRetryCount == 0 {
                appLog("⚠️ KeyInterceptor: Could not create session CGEventTap (AXIsProcessTrusted=\(trusted)). Retrying with backoff.")
            }
            let delay = min(30.0, 1.5 * pow(2.0, Double(min(tapRetryCount, 5))))
            tapRetryCount += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.start()
            }
            return
        }

        tapRetryCount = 0
        self.eventTap = validTap
        gCurrentTap = validTap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, validTap, 0)
        self.runLoopSource = source

        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: validTap, enable: true)
        appLog("✅ KeyInterceptor: Active on Session level (Safe, no deadlocks).")
    }

    public func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            }
            self.eventTap = nil
            self.runLoopSource = nil
            gCurrentTap = nil
            appLog("⏹ KeyInterceptor stopped.")
        }
    }
}
