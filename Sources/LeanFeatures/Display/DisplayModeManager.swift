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
    private let backend: any DisplayModeBackend
    private let queue = DispatchQueue(label: "com.jmac.display-modes", qos: .userInitiated)
    private var connectedIDs: Set<CGDirectDisplayID> = []

    init(backend: any DisplayModeBackend = CoreGraphicsDisplayModeBackend()) { self.backend = backend }

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
        guard applyingDisplay == nil, let catalog = catalogs[display], catalog.modes.contains(option) else { return }
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
                } else {
                    self.errors[display] = result == .success
                        ? tr("macOS did not apply that mode. Try another mode.")
                        : tr("Could not change display mode (code \(result.rawValue)). Try again.")
                }
            }
        }
    }

    func undo(for display: CGDirectDisplayID) {
        guard let option = previous[display] else { return }
        select(option, for: display, undoing: true)
    }
}
