// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import CoreGraphics

public enum WindowDisplayTransferMode: String, CaseIterable, Identifiable {
    case keepSize
    case proportional
    public var id: String { rawValue }
}

package enum WindowDisplayTransfer {
    package static func isValid(_ rect: CGRect) -> Bool {
        rect.origin.x.isFinite && rect.origin.y.isFinite &&
        rect.width.isFinite && rect.height.isFinite && rect.width > 0 && rect.height > 0
    }

    /// Preserve ordinary window sizes in logical points, following source edge contacts.
    /// A window spanning an axis continues to span it. Three-edge windows moving between
    /// landscape and portrait keep their size and center along their anchored edge instead.
    package static func keepingSize(window: CGRect, source: CGRect, destination: CGRect) -> CGRect {
        guard isValid(window), isValid(source), isValid(destination) else { return window }
        let tolerance: CGFloat = 4
        let left = window.minX - source.minX <= tolerance
        let right = source.maxX - window.maxX <= tolerance
        let top = window.minY - source.minY <= tolerance
        let bottom = source.maxY - window.maxY <= tolerance
        let rotates = (source.width > source.height && destination.width < destination.height) ||
            (source.width < source.height && destination.width > destination.height)

        func axis(start: CGFloat, length: CGFloat, sourceStart: CGFloat, sourceLength: CGFloat,
                  targetStart: CGFloat, targetLength: CGFloat, nearStart: Bool, nearEnd: Bool,
                  centerSpanning: Bool) -> (CGFloat, CGFloat) {
            let startInset = max(0, start - sourceStart)
            let endInset = max(0, sourceStart + sourceLength - start - length)
            if nearStart && nearEnd {
                let first = min(startInset, targetLength / 2)
                let last = min(endInset, targetLength / 2)
                let span = targetLength - first - last
                if centerSpanning && length < span {
                    return (targetStart + (targetLength - length) / 2, length)
                }
                return (targetStart + first, span)
            }
            let size = min(length, targetLength)
            let slack = targetLength - size
            let offset: CGFloat
            if nearStart {
                offset = startInset
            } else if nearEnd {
                offset = slack - endInset
            } else {
                let centerFraction = (start + length / 2 - sourceStart) / sourceLength
                offset = centerFraction * targetLength - size / 2
            }
            return (targetStart + min(max(offset, 0), slack), size)
        }

        let x = axis(start: window.minX, length: window.width,
                     sourceStart: source.minX, sourceLength: source.width,
                     targetStart: destination.minX, targetLength: destination.width,
                     nearStart: left, nearEnd: right, centerSpanning: rotates && (top != bottom))
        let y = axis(start: window.minY, length: window.height,
                     sourceStart: source.minY, sourceLength: source.height,
                     targetStart: destination.minY, targetLength: destination.height,
                     nearStart: top, nearEnd: bottom, centerSpanning: rotates && (left != right))
        return CGRect(x: x.0, y: y.0, width: x.1, height: y.1)
    }
}
