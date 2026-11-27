// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

// MARK: - Shared UI state (sub-tabs)

@MainActor
package final class UIState: ObservableObject {
    package static let shared = UIState()
    /// Hardware: 0 Battery, 1 Display, 2 Thermals
    @Published package var hardwareSub: Int = 0
    /// Main tab: 0 Overview, 1 Hardware, 2 Tools, 3 Cleaner
    @Published package var selectedMainTab: Int = 0
    /// Tools: 0 Utilities, 1 Startup, 2 Processes
    @Published package var toolsSub: Int = 0
    /// The Settings page (opened from the gear) is showing
    @Published package var settingsOpen: Bool = false
    var openPermissionDetails = false
    @Published package var permissionsOpen: Bool = false
}
