// SPDX-License-Identifier: GPL-3.0-only
import CoreGraphics

/// One original frame per window, preserved across successive LeanMac operations.
/// Tokens also prevent delayed AX retries from overwriting a newer snap/restore.
package struct WindowFrameHistory<Key: Hashable> {
    private struct Entry {
        package var original: CGRect?
        package var lastApplied: CGRect
        package var token: UInt64
        package var settled = false
    }
    private var entries: [Key: Entry] = [:]
    private var serial: UInt64 = 0
    private let capacity: Int
    package init(capacity: Int = 128) { self.capacity = max(1, capacity) }

    package mutating func begin(_ key: Key, current: CGRect, target: CGRect, restoring: Bool = false) -> UInt64 {
        var original = entries[key]?.original
        if restoring {
            original = nil
        } else if original == nil || (entries[key]?.settled == true && !Self.nearlyEqual(current, entries[key]!.lastApplied)) {
            // A manual move/resize starts a new sequence from the user's new frame.
            original = current
        }
        serial &+= 1
        entries[key] = Entry(original: original, lastApplied: target, token: serial)
        if entries.count > capacity, let oldest = entries.min(by: { $0.value.token < $1.value.token })?.key {
            entries.removeValue(forKey: oldest)
        }
        return serial
    }
    package func original(for key: Key) -> CGRect? { entries[key]?.original }
    package func isCurrent(_ key: Key, token: UInt64) -> Bool { entries[key]?.token == token }
    package mutating func settle(_ key: Key, token: UInt64, actual: CGRect) {
        guard isCurrent(key, token: token) else { return }
        entries[key]?.lastApplied = actual
        entries[key]?.settled = true
    }
    private static func nearlyEqual(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX-b.minX) <= 2 && abs(a.minY-b.minY) <= 2 &&
        abs(a.width-b.width) <= 2 && abs(a.height-b.height) <= 2
    }

    /// Keep the original frame where possible; fit onto an available screen after
    /// a display disconnect or workspace change instead of restoring off-screen.
    package static func visibleRestoreFrame(_ original: CGRect, screens: [CGRect], fallback: CGRect) -> CGRect {
        if screens.contains(where: { $0.contains(original) }) { return original }
        func overlap(_ frame: CGRect) -> CGFloat {
            let intersection = frame.intersection(original)
            return intersection.isNull ? 0 : intersection.width * intersection.height
        }
        let best = screens.max(by: { overlap($0) < overlap($1) })
        let visible = best.flatMap { overlap($0) > 0 ? $0 : nil } ?? fallback
        let width = min(original.width, visible.width), height = min(original.height, visible.height)
        return CGRect(x: max(visible.minX, min(original.minX, visible.maxX-width)),
                      y: max(visible.minY, min(original.minY, visible.maxY-height)), width: width, height: height)
    }
}
