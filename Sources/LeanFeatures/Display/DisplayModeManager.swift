// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import CoreGraphics
import Combine
import LeanDomain
import LeanPlatform

@MainActor
final class DisplayModeManager: ObservableObject {
    static let shared = DisplayModeManager()
    @Published private(set) var catalogs: [CGDirectDisplayID: DisplayModeCatalog] = [:]
    @Published private(set) var errors: [CGDirectDisplayID: String] = [:]
    @Published private(set) var previous: [CGDirectDisplayID: DisplayModeOption] = [:]
    @Published private(set) var applyingDisplay: CGDirectDisplayID?
    /// Result of the last display check (empty until the user runs it).
    @Published private(set) var verdicts: [DisplayVerdict] = []
    @Published private(set) var checkRan = false
    /// Set while a batch of changes waits for the user to keep it; it is reverted when the countdown ends.
    @Published private(set) var pendingRevert: PendingRevert?
    @Published private(set) var batchError: String?
    private var countdown: Task<Void, Never>?
    private var terminateObserver: NSObjectProtocol?
    /// Seconds the user has to confirm; a screen that became unreadable still goes back by itself.
    static let confirmSeconds = 15

    struct PendingRevert: Equatable {
        let originals: [CGDirectDisplayID: DisplayModeOption]
        var secondsLeft: Int
    }
    private let backend: any DisplayModeBackend
    private let queue = DispatchQueue(label: "com.jmac.display-modes", qos: .userInitiated)
    private var connectedIDs: Set<CGDirectDisplayID> = []

    init(backend: any DisplayModeBackend = CoreGraphicsDisplayModeBackend()) {
        self.backend = backend
        // Never leave an unconfirmed change behind when the app quits.
        terminateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.revertNow(wait: true) }
        }
    }

    // MARK: - Display check (recommend, apply with automatic revert)

    func runCheck(names: [CGDirectDisplayID: (name: String, isBuiltIn: Bool)]) {
        let inputs: [DisplayCheckInput] = connectedIDs.sorted().compactMap { id in
            guard let catalog = catalogs[id] else { return nil }
            let size = CGDisplayScreenSize(id)
            return DisplayCheckInput(id: id, name: names[id]?.name ?? tr("Display"), isBuiltIn: names[id]?.isBuiltIn ?? (CGDisplayIsBuiltin(id) != 0),
                                     widthMM: size.width.isFinite ? Double(size.width) : 0, catalog: catalog)
        }
        verdicts = DisplayCheck.evaluate(inputs)
        checkRan = true
        batchError = nil
    }

    var recommendedChanges: [DisplayVerdict] { verdicts.filter { $0.recommended != nil } }

    /// Applies every recommendation, then asks the user to keep it. Any failure puts everything back.
    func applyRecommendations() {
        guard pendingRevert == nil, applyingDisplay == nil else { return }
        let changes = recommendedChanges.compactMap { v -> (CGDirectDisplayID, DisplayModeOption, DisplayModeOption)? in
            guard let new = v.recommended, let old = catalogs[v.id]?.current else { return nil }
            return (v.id, old, new)
        }
        guard !changes.isEmpty else { return }
        batchError = nil
        applyingDisplay = changes[0].0
        let backend = self.backend
        queue.async { [weak self] in
            var applied: [(CGDirectDisplayID, DisplayModeOption)] = []
            var failure: CGError = .success
            for (id, old, new) in changes {
                let r = backend.apply(new, to: id)
                if r == .success { applied.append((id, old)) } else { failure = r; break }
            }
            if failure != .success { for (id, old) in applied.reversed() { _ = backend.apply(old, to: id) } }
            DispatchQueue.main.async {
                guard let self else { return }
                self.applyingDisplay = nil
                self.refresh(displays: Array(self.connectedIDs))
                if failure != .success {
                    self.batchError = tr("Could not change a display (code \(failure.rawValue)). Everything was put back.")
                    return
                }
                self.pendingRevert = PendingRevert(originals: Dictionary(uniqueKeysWithValues: applied), secondsLeft: Self.confirmSeconds)
                self.runCheckAfterChange()
                self.startCountdown()
            }
        }
    }

    private func runCheckAfterChange() {
        verdicts = []
        checkRan = false
    }

    private func startCountdown() {
        countdown?.cancel()
        countdown = Task { @MainActor [weak self] in
            while let self, let left = self.pendingRevert?.secondsLeft, left > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                self.pendingRevert?.secondsLeft -= 1
            }
            if !Task.isCancelled { self?.revertNow() }
        }
    }

    func keepChanges() {
        countdown?.cancel(); countdown = nil
        pendingRevert = nil
    }

    func revertNow(wait: Bool = false) {
        countdown?.cancel(); countdown = nil
        guard let pending = pendingRevert else { return }
        pendingRevert = nil
        let backend = self.backend
        for id in pending.originals.keys { previous[id] = nil }
        let work = { for (id, old) in pending.originals { _ = backend.apply(old, to: id) } }
        if wait { work(); return }
        applyingDisplay = pending.originals.keys.first
        queue.async { [weak self] in
            work()
            DispatchQueue.main.async {
                self?.applyingDisplay = nil
                self?.refresh(displays: Array(self?.connectedIDs ?? []))
            }
        }
    }

    func refresh(displays: [CGDirectDisplayID]) {
        connectedIDs = Set(displays)
        var next: [CGDirectDisplayID: DisplayModeCatalog] = [:]
        for id in displays { next[id] = backend.catalog(for: id) }
        if catalogs != next { catalogs = next }
        errors = errors.filter { connectedIDs.contains($0.key) }
        previous = previous.filter { id, option in next[id]?.modes.contains(option) == true }
    }

    func selectResolution(_ resolution: DisplayResolution, for display: CGDirectDisplayID) {
        guard let option = catalogs[display]?.preferredMode(for: resolution) else { return }
        select(option, for: display)
    }

    func select(_ option: DisplayModeOption, for display: CGDirectDisplayID, undoing: Bool = false) {
        guard pendingRevert == nil, applyingDisplay == nil, let catalog = catalogs[display], catalog.modes.contains(option) else { return }
        guard option != catalog.current else { return }
        let original = catalog.current
        applyingDisplay = display
        errors[display] = nil
        let backend = self.backend
        queue.async { [weak self] in
            let result = backend.apply(option, to: display)
            DispatchQueue.main.async {
                guard let self else { return }
                self.applyingDisplay = nil
                self.refresh(displays: Array(self.connectedIDs))
                guard self.connectedIDs.contains(display) else { return }
                if result == .success, let actual = self.catalogs[display]?.current,
                   actual.resolution == option.resolution && actual.milliHertz == option.milliHertz {
                    self.previous[display] = !undoing && self.catalogs[display]?.modes.contains(original) == true ? original : nil
                    if !undoing {
                        self.pendingRevert = PendingRevert(originals: [display: original], secondsLeft: Self.confirmSeconds)
                        self.startCountdown()
                    }
                } else {
                    self.errors[display] = result == .success
                        ? tr("macOS did not apply that mode. Try another mode.")
                        : tr("Could not change display mode (code \(result.rawValue)). Try again.")
                }
            }
        }
    }

    func undo(for display: CGDirectDisplayID) {
        if pendingRevert?.originals[display] != nil {
            revertNow()
            return
        }
        guard let option = previous[display] else { return }
        select(option, for: display, undoing: true)
    }
}
