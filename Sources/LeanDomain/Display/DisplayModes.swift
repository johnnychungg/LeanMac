// SPDX-License-Identifier: GPL-3.0-only
import CoreGraphics

package struct DisplayResolution: Hashable, Identifiable, Sendable {
    package let width: Int
    package let height: Int
    package let pixelWidth: Int
    package let pixelHeight: Int

    package init(width: Int, height: Int, pixelWidth: Int, pixelHeight: Int) {
        self.width = width
        self.height = height
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }
    package var id: Self { self }
    package var isHiDPI: Bool { pixelWidth > width || pixelHeight > height }
    package var title: String { "\(width) × \(height)" + (isHiDPI ? " · HiDPI" : "") }
}

package struct DisplayModeOption: Identifiable, Equatable, Sendable {
    package let id: Int32
    package let resolution: DisplayResolution
    /// Preserve fractional refresh rates, e.g. 59.94 versus 60 Hz. Zero means unspecified.
    package let milliHertz: Int
    package var refreshTitle: String {
        guard milliHertz > 0 else { return tr("System default") }
        let value = Double(milliHertz) / 1000
        let number = String(format: "%.3f", value).replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\.$", with: "", options: .regularExpression)
        return number + " Hz"
    }
    package init(id: Int32, resolution: DisplayResolution, milliHertz: Int) {
        self.id = id; self.resolution = resolution; self.milliHertz = max(0, milliHertz)
    }
    package init(_ mode: CGDisplayMode) {
        self.init(id: mode.ioDisplayModeID,
                  resolution: .init(width: mode.width, height: mode.height, pixelWidth: mode.pixelWidth, pixelHeight: mode.pixelHeight),
                  milliHertz: mode.refreshRate.isFinite && mode.refreshRate > 0 ? Int((mode.refreshRate * 1000).rounded()) : 0)
    }
}

package struct DisplayModeCatalog: Equatable, Sendable {
    package let current: DisplayModeOption
    package let modes: [DisplayModeOption]
    package let isMirrored: Bool

    package init(current: DisplayModeOption, modes: [DisplayModeOption], isMirrored: Bool = false) {
        self.current = current
        self.isMirrored = isMirrored
        // Current first: retain its exact mode ID when duplicate encodings exist.
        var unique: [DisplayModeOption] = []
        for mode in [current] + modes where mode.resolution.width > 0 && mode.resolution.height > 0 {
            if !unique.contains(where: { $0.resolution == mode.resolution && $0.milliHertz == mode.milliHertz }) {
                unique.append(mode)
            }
        }
        self.modes = unique
    }
    package var resolutions: [DisplayResolution] {
        Array(Set(modes.map(\.resolution))).sorted {
            if $0.width != $1.width { return $0.width < $1.width }
            if $0.height != $1.height { return $0.height < $1.height }
            if $0.pixelWidth != $1.pixelWidth { return $0.pixelWidth > $1.pixelWidth }
            return $0.pixelHeight > $1.pixelHeight
        }
    }
    package func rates(for resolution: DisplayResolution) -> [DisplayModeOption] {
        modes.filter { $0.resolution == resolution }.sorted { $0.milliHertz > $1.milliHertz }
    }
    package func preferredMode(for resolution: DisplayResolution) -> DisplayModeOption? {
        let options = rates(for: resolution)
        // Keep the refresh rate when possible, otherwise choose the closest supported rate.
        return options.first(where: { $0.milliHertz == current.milliHertz }) ?? options.min {
            abs($0.milliHertz - current.milliHertz) < abs($1.milliHertz - current.milliHertz)
        }
    }
}

package protocol DisplayModeBackend: Sendable {
    func catalog(for display: CGDirectDisplayID) -> DisplayModeCatalog?
    func apply(_ option: DisplayModeOption, to display: CGDirectDisplayID) -> CGError
}
