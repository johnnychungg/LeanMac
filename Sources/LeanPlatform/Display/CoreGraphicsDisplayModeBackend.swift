// SPDX-License-Identifier: GPL-3.0-only
import CoreGraphics
import LeanDomain

package struct CoreGraphicsDisplayModeBackend: DisplayModeBackend {
    package init() {}

    private func modes(for display: CGDirectDisplayID) -> [CGDisplayMode] {
        CGDisplayCopyAllDisplayModes(display, [kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary) as? [CGDisplayMode] ?? []
    }
    package func catalog(for display: CGDirectDisplayID) -> DisplayModeCatalog? {
        guard CGDisplayIsOnline(display) != 0, CGDisplayIsActive(display) != 0,
              let current = CGDisplayCopyDisplayMode(display) else { return nil }
        return DisplayModeCatalog(current: .init(current), modes: modes(for: display)
            .filter { $0.isUsableForDesktopGUI() }.map(DisplayModeOption.init),
            isMirrored: CGDisplayIsInMirrorSet(display) != 0)
    }
    package func apply(_ option: DisplayModeOption, to display: CGDirectDisplayID) -> CGError {
        guard CGDisplayIsOnline(display) != 0, CGDisplayIsActive(display) != 0 else { return .invalidConnection }
        // Resolve again immediately before applying: display modes can change after hot-plug/mirroring.
        guard let mode = modes(for: display).first(where: {
            $0.isUsableForDesktopGUI() && DisplayModeOption($0) == option
        }) else { return .illegalArgument }
        var config: CGDisplayConfigRef?
        let begin = CGBeginDisplayConfiguration(&config)
        guard begin == .success else { return begin }
        let configure = CGConfigureDisplayWithDisplayMode(config, display, mode, nil)
        guard configure == .success else {
            _ = CGCancelDisplayConfiguration(config)
            return configure
        }
        return CGCompleteDisplayConfiguration(config, .permanently)
    }
}
