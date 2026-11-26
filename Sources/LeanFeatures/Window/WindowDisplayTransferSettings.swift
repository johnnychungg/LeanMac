// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Combine
import LeanDomain

/// One persisted preference, read only when a transfer is requested. No background monitoring.
@MainActor
final class WindowDisplayTransferSettings: ObservableObject {
    static let shared = WindowDisplayTransferSettings()
    static let preferencesKey = "window_snap_display_transfer_mode"
    private let defaults: UserDefaults

    @Published var mode: WindowDisplayTransferMode {
        didSet { defaults.set(mode.rawValue, forKey: Self.preferencesKey) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        mode = defaults.string(forKey: Self.preferencesKey)
            .flatMap(WindowDisplayTransferMode.init(rawValue:)) ?? .keepSize
    }
}
