// SPDX-License-Identifier: GPL-3.0-only
import CoreGraphics

/// What the display check needs to know about one connected display.
package struct DisplayCheckInput: Sendable {
    package let id: CGDirectDisplayID
    package let name: String
    package let isBuiltIn: Bool
    /// Physical width of the visible panel in millimetres (0 when macOS does not know it).
    package let widthMM: Double
    package let catalog: DisplayModeCatalog

    package init(id: CGDirectDisplayID, name: String, isBuiltIn: Bool, widthMM: Double, catalog: DisplayModeCatalog) {
        self.id = id; self.name = name; self.isBuiltIn = isBuiltIn; self.widthMM = widthMM; self.catalog = catalog
    }
}

/// The result of the check for one display.
package struct DisplayVerdict: Identifiable, Equatable, Sendable {
    package let id: CGDirectDisplayID
    package let name: String
    /// UI points per physical inch now, or nil when the physical size is unknown.
    package let currentPtPerInch: Double?
    /// UI points per inch every display is matched to (the reference display's current value).
    package let targetPtPerInch: Double?
    /// The mode to switch to, or nil when the current mode is already the best choice.
    package let recommended: DisplayModeOption?
    /// UI points per inch after the change (equals `currentPtPerInch` when nothing changes).
    package let resultPtPerInch: Double?
    package let isReference: Bool
    /// The panel has too few pixels to reach the target size, so this is as close as it gets.
    package let isPanelLimited: Bool
    /// The current mode is rendered at a different size than the panel and then resized (slightly softer text).
    package let isCurrentScaled: Bool
    /// The closest pixel-exact mode, shown as information when the current mode is scaled.
    package let sharpest: DisplayModeOption?
    /// Why nothing is recommended for this display (mirrored or unknown size).
    package let skipped: Bool
}

/// Chooses, for every display, the mode that makes the UI the same physical size on all of them, using each
/// display's own best refresh rate and preferring modes that are not resized. Pure logic: it never changes anything.
///
/// "Matching" is measured in UI points per physical inch (`width / widthInInches`). The reference is the built-in
/// display (its current mode is the user's choice), or the sharpest external when there is no built-in display.
package enum DisplayCheck {
    /// A mode that is resized by macOS is slightly softer, so it must be this much closer to the target to win.
    package static let scaledPenalty = 0.04
    /// Do not change resolution for an improvement smaller than this (avoids needless flicker).
    package static let minimumGain = 0.03

    package static func ptPerInch(width: Int, widthMM: Double) -> Double? {
        guard widthMM >= 20, width > 0 else { return nil }
        return Double(width) / (widthMM / 25.4)
    }

    /// Native pixel size of the panel: the largest mode that is not HiDPI.
    package static func nativePixels(of catalog: DisplayModeCatalog) -> (width: Int, height: Int)? {
        catalog.modes.map(\.resolution).filter { !$0.isHiDPI }
            .max { $0.pixelWidth * $0.pixelHeight < $1.pixelWidth * $1.pixelHeight }
            .map { ($0.pixelWidth, $0.pixelHeight) }
    }

    package static func isScaled(_ resolution: DisplayResolution, native: (width: Int, height: Int)?) -> Bool {
        guard let native else { return false }
        return resolution.pixelWidth != native.width
    }

    private static func bestRate(_ catalog: DisplayModeCatalog, for resolution: DisplayResolution) -> DisplayModeOption? {
        catalog.rates(for: resolution).first
    }

    package static func evaluate(_ inputs: [DisplayCheckInput]) -> [DisplayVerdict] {
        let reference = inputs.first(where: { $0.isBuiltIn && !$0.catalog.isMirrored })
            ?? inputs.filter { !$0.catalog.isMirrored }.max {
                (ptPerInch(width: $0.catalog.current.resolution.width, widthMM: $0.widthMM) ?? 0)
                    < (ptPerInch(width: $1.catalog.current.resolution.width, widthMM: $1.widthMM) ?? 0)
            }
        let target = reference.flatMap { ptPerInch(width: $0.catalog.current.resolution.width, widthMM: $0.widthMM) }

        return inputs.map { input in
            let catalog = input.catalog
            let current = catalog.current
            let currentDensity = ptPerInch(width: current.resolution.width, widthMM: input.widthMM)
            let native = nativePixels(of: catalog)
            let currentScaled = isScaled(current.resolution, native: native)
            let isRef = input.id == reference?.id

            func verdict(recommended: DisplayModeOption?, result: Double?, limited: Bool = false,
                         sharpest: DisplayModeOption? = nil, skipped: Bool = false) -> DisplayVerdict {
                DisplayVerdict(id: input.id, name: input.name, currentPtPerInch: currentDensity, targetPtPerInch: target,
                               recommended: recommended, resultPtPerInch: result, isReference: isRef,
                               isPanelLimited: limited, isCurrentScaled: currentScaled, sharpest: sharpest, skipped: skipped)
            }

            // Mirrored displays share a mode with their group; unknown sizes cannot be compared.
            guard !catalog.isMirrored, let currentDensity, let target else {
                return verdict(recommended: nil, result: currentDensity, skipped: true)
            }

            func score(_ resolution: DisplayResolution) -> Double? {
                guard let d = ptPerInch(width: resolution.width, widthMM: input.widthMM) else { return nil }
                return abs(d - target) / target + (isScaled(resolution, native: native) ? scaledPenalty : 0)
            }

            // The reference keeps its resolution; every other display goes to the closest-size mode.
            var chosen = current.resolution
            if !isRef, let currentScore = score(current.resolution) {
                let candidates = catalog.resolutions.filter { $0.width >= 640 }
                if let best = candidates.compactMap({ r in score(r).map { (r, $0) } }).min(by: { $0.1 < $1.1 }),
                   best.0 != current.resolution, currentScore - best.1 >= minimumGain {
                    chosen = best.0
                }
            }

            // Best refresh rate for the chosen resolution.
            let top = bestRate(catalog, for: chosen)
            let mode: DisplayModeOption? = {
                guard let top else { return nil }
                if chosen == current.resolution && top.milliHertz <= current.milliHertz { return nil }
                return top
            }()

            let result = ptPerInch(width: chosen.width, widthMM: input.widthMM)
            let largest = catalog.resolutions.map(\.width).max() ?? 0
            let limited = !isRef && (result ?? 0) < target * 0.9
                && chosen.width >= (catalog.resolutions.filter { !$0.isHiDPI }.map(\.width).max() ?? largest)

            // Information only: the pixel-exact mode closest to the target size.
            let exact = catalog.resolutions.filter {
                !isScaled($0, native: native) && $0.width >= 640 && $0.isHiDPI == current.resolution.isHiDPI
            }
            let sharpest = currentScaled
                ? exact.min {
                    abs((ptPerInch(width: $0.width, widthMM: input.widthMM) ?? 0) - target)
                        < abs((ptPerInch(width: $1.width, widthMM: input.widthMM) ?? 0) - target)
                }.flatMap { bestRate(catalog, for: $0) }
                : nil

            return verdict(recommended: mode, result: result, limited: limited, sharpest: sharpest)
        }
    }
}
