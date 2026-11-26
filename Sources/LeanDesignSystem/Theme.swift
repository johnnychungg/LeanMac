// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import AppKit

/// Shared design tokens for the whole UI. Few steps on purpose, to keep the interface compact and consistent.
/// Convention: no font size below `FS.caption` (10pt); bold only for large numbers (>= `FS.value`).

/// Font sizes (pt).
package enum FS {
    package static let caption: CGFloat = 10   // captions, secondary hints
    package static let label: CGFloat = 11     // labels, small buttons, tags
    package static let body: CGFloat = 12      // main content
    package static let title: CGFloat = 13     // card title
    package static let subhead: CGFloat = 14   // section title
    package static let value: CGFloat = 16     // prominent numbers
    package static let display: CGFloat = 22   // large numbers
    package static let hero: CGFloat = 28
    package static let huge: CGFloat = 32
    package static let mega: CGFloat = 36
}

/// Corner radii.
package enum Rad {
    package static let sm: CGFloat = 6    // buttons, chips, small cells
    package static let md: CGFloat = 10   // cards
    package static let lg: CGFloat = 14   // large panels
}

/// Semantic colors: use color only when it carries meaning. Everything else uses the accent or gray.
package enum Tone {
    package static let accent = Color.accentColor   // on / selected / primary action
    /// Soft green (not the harsh systemGreen): slightly brighter in dark mode.
    package static let good = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.40, green: 0.70, blue: 0.50, alpha: 1)
            : NSColor(srgbRed: 0.20, green: 0.48, blue: 0.32, alpha: 1)
    })                                      // granted / OK / done
    package static let warn = Color.orange          // warning
    package static let bad = Color.red              // error / danger
    package static let muted = Color.secondary      // icons and secondary text (default for icons)
}

/// "Wrapping" layout: items move to the next line as whole items (text is never broken in the middle).
package struct FlowLayout: Layout {
    package var spacing: CGFloat = 6

    package init(spacing: CGFloat = 6) {
        self.spacing = spacing
    }

    package func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, width: CGFloat = 0
        for sub in subviews {
            let sz = sub.sizeThatFits(.unspecified)
            if x > 0 && x + sz.width > maxW { x = 0; y += rowH + spacing; rowH = 0 }
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
            width = max(width, x - spacing)
        }
        return CGSize(width: proposal.width ?? width, height: y + rowH)
    }

    package func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for sub in subviews {
            let sz = sub.sizeThatFits(.unspecified)
            if x > 0 && x + sz.width > bounds.width { x = 0; y += rowH + spacing; rowH = 0 }
            sub.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y), anchor: .topLeading, proposal: .unspecified)
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
    }
}

/// Two-column shortcut table: description on the left, keys on the right, columns aligned.
struct ShortcutGrid<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 14, alignment: .top), GridItem(.flexible(), alignment: .top)],
            alignment: .leading,
            spacing: 6
        ) { content() }
    }
}

/// The one card background for the whole app: same color, same corner radius, same thin border.
extension View {
    package func cardBackground() -> some View {
        background(
            RoundedRectangle(cornerRadius: Rad.md, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: Rad.md, style: .continuous)
                        .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                )
        )
    }
}
