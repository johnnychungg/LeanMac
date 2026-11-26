// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import LeanDomain
import AppKit

// MARK: - Adaptive light/dark palette

package enum Pal {
    private static func dyn(_ light: NSColor, _ dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
    private static func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
    }

    package static let bg        = dyn(rgb(0xFFFFFF), rgb(0x232323))
    package static let card      = dyn(rgb(0xEBEBE8), rgb(0x2F2F2F))
    package static let ink       = dyn(rgb(0x161615), rgb(0xEFEFEC))
    package static let ink2      = dyn(rgb(0x44443F), rgb(0xB0B0AB))
    package static let ink3      = dyn(rgb(0x66665F), rgb(0x9A9A95))
    package static let line      = dyn(NSColor(white: 0, alpha: 0.16), NSColor(white: 1, alpha: 0.10))
    package static let lineStrong = dyn(NSColor(white: 0, alpha: 0.42), NSColor(white: 1, alpha: 0.28))
    package static let accent    = dyn(rgb(0x1D5BD6), rgb(0x6EA2FF))
    package static let accentBg  = dyn(rgb(0x1D5BD6, 0.14), rgb(0x6EA2FF, 0.18))
    package static let ok        = dyn(rgb(0x2F7D4F), rgb(0x6FCF97))
    package static let okBg      = dyn(rgb(0x2F7D4F, 0.14), rgb(0x6FCF97, 0.16))
    package static let warn      = dyn(rgb(0x8A5A00), rgb(0xF2C46B))
    package static let warnBg    = dyn(rgb(0xE0A01E, 0.20), rgb(0xF2C46B, 0.16))
    package static let danger    = dyn(rgb(0xB3261E), rgb(0xF2918A))
    package static let button    = dyn(rgb(0x161615), rgb(0xEFEFEC))
    package static let buttonInk = dyn(rgb(0xFFFFFF), rgb(0x1B1B1A))
}

// MARK: - Card

extension View {
    /// Light gray card, radius 12.
    package func jCard(padding: CGFloat = 12) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Pal.card))
    }
}

package struct JDivider: View {
    package var body: some View { Rectangle().fill(Pal.line).frame(height: 0.5) }

    package init() {}
}

// MARK: - Switch

struct JSwitch: View {
    @Binding var isOn: Bool
    var body: some View {
        Button { withAnimation(.easeOut(duration: 0.12)) { isOn.toggle() } } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule().fill(isOn ? Pal.accent : Pal.lineStrong).frame(width: 34, height: 20)
                Circle().fill(Color.white).frame(width: 16, height: 16).padding(2)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(isOn ? "on" : "off")
    }
}

// MARK: - Icon in a colored tile

package struct JIcon: View {
    package let name: String

    package init(name: String) {
        self.name = name
    }
    package var body: some View {
        Image(systemName: name)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Pal.accent)
            .frame(width: 30, height: 30)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Pal.accentBg))
    }
}

// MARK: - Row with a switch

package struct JToggleRow: View {
    package let icon: String
    package let title: String
    package var subtitle: String? = nil
    @Binding package var isOn: Bool
    package var trailing: AnyView? = nil

    package init(icon: String, title: String, subtitle: String? = nil, isOn: Binding<Bool>, trailing: AnyView? = nil) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self._isOn = isOn
        self.trailing = trailing
    }

    package var body: some View {
        HStack(spacing: 10) {
            JIcon(name: icon)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(Pal.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle {
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(Pal.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 6)
            if let trailing { trailing }
            JSwitch(isOn: $isOn)
        }
    }
}

// MARK: - Info button (i)

package struct JInfoButton: View {
    package let text: String

    package init(text: String) {
        self.text = text
    }
    @State private var shown = false
    package var body: some View {
        Button { shown.toggle() } label: {
            Image(systemName: "info.circle").font(.system(size: 13)).foregroundStyle(Pal.ink3)
        }
        .buttonStyle(.plain)
        .help(text)
        .popover(isPresented: $shown, arrowEdge: .bottom) {
            Text(text).font(.system(size: 12)).foregroundStyle(Pal.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 240, alignment: .leading).padding(12)
        }
    }
}

// MARK: - Segmented

package struct JSegmented: View {
    package let items: [String]
    @Binding package var selection: Int

    package init(items: [String], selection: Binding<Int>) {
        self.items = items
        self._selection = selection
    }
    package var body: some View {
        HStack(spacing: 2) {
            ForEach(items.indices, id: \.self) { i in
                Button { selection = i } label: {
                    Text(items[i])
                        .font(.system(size: 12, weight: selection == i ? .medium : .regular))
                        .foregroundStyle(selection == i ? Pal.ink : Pal.ink2)
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(selection == i ? Pal.bg : Color.clear)
                                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(selection == i ? Pal.line : Color.clear, lineWidth: 0.5))
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Pal.card))
    }
}

// MARK: - Chip

package struct JChip: View {
    package let text: String
    package var icon: String? = nil
    package var selected: Bool = false
    package var action: (() -> Void)? = nil

    package init(text: String, icon: String? = nil, selected: Bool = false, action: (() -> Void)? = nil) {
        self.text = text
        self.icon = icon
        self.selected = selected
        self.action = action
    }

    package var body: some View {
        let label = HStack(spacing: 4) {
            if let icon { Image(systemName: icon).font(.system(size: 11)) }
            Text(text).font(.system(size: 12)).lineLimit(1)
        }
        .foregroundStyle(selected ? Pal.accent : Pal.ink2)
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(Capsule().fill(selected ? Pal.accentBg : Pal.card))
        if let action {
            Button(action: action) { label }.buttonStyle(.plain)
        } else {
            label
        }
    }
}

/// Colored status chip (ok / warning) for the header.
package struct JStatusChip: View {
    package enum Kind { case neutral, ok, warn, accent }
    package let text: String
    package var icon: String? = nil
    package var kind: Kind = .neutral

    package init(text: String, icon: String? = nil, kind: Kind = .neutral) {
        self.text = text
        self.icon = icon
        self.kind = kind
    }
    package var body: some View {
        let (fg, bg): (Color, Color) = {
            switch kind {
            case .neutral: return (Pal.ink2, Pal.card)
            case .ok: return (Pal.ok, Pal.okBg)
            case .warn: return (Pal.warn, Pal.warnBg)
            case .accent: return (Pal.accent, Pal.accentBg)
            }
        }()
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon).font(.system(size: 11, weight: .medium)) }
            Text(text).font(.system(size: 12)).lineLimit(1)
        }
        .foregroundStyle(fg)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(Capsule().fill(bg))
    }
}

// MARK: - Key cap

struct KeyCap: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(Pal.ink2)
            .frame(minWidth: 22, minHeight: 22)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Pal.bg)
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Pal.lineStrong, lineWidth: 0.5))
            )
    }
}

package struct KeyCaps: View {
    package let keys: [String]

    package init(keys: [String]) {
        self.keys = keys
    }
    package var body: some View {
        HStack(spacing: 3) { ForEach(keys.indices, id: \.self) { KeyCap(keys[$0]) } }
    }
}

// MARK: - Checkbox (3 states)

package struct JCheck: View {
    package enum State { case off, on, mixed }
    package let state: State
    package var locked: Bool = false
    package var action: () -> Void

    package init(state: State, locked: Bool = false, action: @escaping () -> Void) {
        self.state = state
        self.locked = locked
        self.action = action
    }

    package var body: some View {
        Button(action: { if !locked { action() } }) {
            ZStack {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(state == .off ? Color.clear : Pal.accent)
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(state == .off ? Pal.lineStrong : Pal.accent, lineWidth: 1.5)
                if state != .off {
                    Image(systemName: state == .on ? "checkmark" : "minus")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.white)
                }
            }
            .frame(width: 18, height: 18)
            .opacity(locked ? 0.4 : 1)
            .padding(6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(-6)
        .disabled(locked)
    }
}

// MARK: - Button

package struct JButtonStyle: ButtonStyle {
    package enum Kind { case primary, ghost }
    package var kind: Kind = .primary

    package init(kind: Kind = .primary) {
        self.kind = kind
    }
    @Environment(\.isEnabled) private var enabled

    package func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(background)
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(kind == .ghost && enabled ? Pal.lineStrong : Color.clear, lineWidth: 0.5))
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
    }

    private var foreground: Color {
        if !enabled { return Pal.ink3 }
        return kind == .primary ? Pal.buttonInk : Pal.ink
    }
    private var background: Color {
        if !enabled { return Pal.card }
        return kind == .primary ? Pal.button : Pal.bg
    }
}

// MARK: - Warning strip

package struct JBanner: View {
    package let icon: String
    package let text: String
    package var actionTitle: String? = nil
    package var chevron: String? = nil
    package var action: (() -> Void)? = nil

    package init(icon: String, text: String, actionTitle: String? = nil, chevron: String? = nil, action: (() -> Void)? = nil) {
        self.icon = icon
        self.text = text
        self.actionTitle = actionTitle
        self.chevron = chevron
        self.action = action
    }

    package var body: some View {
        Button { action?() } label: {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 14))
                Text(text).font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading)
                if let actionTitle { Text(actionTitle).font(.system(size: 12, weight: .medium)) }
                if let chevron { Image(systemName: chevron).font(.system(size: 11, weight: .medium)) }
            }
            .foregroundStyle(Pal.warn)
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Pal.warnBg))
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
    }
}

// MARK: - Metric cell

package struct JTile: View {
    package let label: String
    package let value: String

    package init(label: String, value: String) {
        self.label = label
        self.value = value
    }
    package var body: some View {
        VStack(spacing: 2) {
            Text(label).font(.system(size: 11)).foregroundStyle(Pal.ink3).lineLimit(1).minimumScaleFactor(0.8)
            Text(value).font(.system(size: 15, weight: .medium)).foregroundStyle(Pal.ink).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8).padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Pal.bg)
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Pal.line, lineWidth: 0.5))
        )
    }
}

// MARK: - Appearance mode (Auto / Light / Dark)

@MainActor
package final class AppearanceManager: ObservableObject {
    package static let shared = AppearanceManager()
    private let key = "ui_appearance_mode"

    /// 0 Follow macOS, 1 Light, 2 Dark
    @Published package var mode: Int {
        didSet { UserDefaults.standard.set(mode, forKey: key); apply() }
    }

    private init() { mode = UserDefaults.standard.integer(forKey: key) }

    package weak var popover: NSPopover?

    package var appearance: NSAppearance? {
        switch mode {
        case 1: return NSAppearance(named: .aqua)
        case 2: return NSAppearance(named: .darkAqua)
        default: return nil
        }
    }

    /// The scheme the UI really uses right now. It is always concrete (never nil): a SwiftUI `preferredColorScheme(nil)`
    /// does not reliably return to the system look after Light/Dark, which made Auto need a second click.
    @Published package private(set) var resolvedScheme: ColorScheme = .light
    package var colorScheme: ColorScheme? { resolvedScheme }
    private var systemObserver: NSKeyValueObservation?

    package func apply() {
        NSApp.appearance = appearance
        popover?.appearance = appearance
        popover?.contentViewController?.view.appearance = appearance
        resolve()
        if systemObserver == nil {
            // Follow macOS while in Auto mode.
            systemObserver = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
                Task { @MainActor in self?.resolve() }
            }
        }
    }

    private func resolve() {
        let scheme: ColorScheme
        switch mode {
        case 1: scheme = .light
        case 2: scheme = .dark
        default:
            scheme = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
        }
        if scheme != resolvedScheme { resolvedScheme = scheme }
    }
}

// MARK: - LeanMac logo (a minimal letter L)

/// LeanMac logo: the letter "L" whose foot is a leaf (lean, light, "sprouting").
package struct LeanGlyph: Shape {

    package init() {
    }
    package func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height)
        // Normalized 0...1 coordinates, origin bottom-left; converted to SwiftUI coordinates (origin top-left).
        func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * s, y: rect.minY + (1 - y) * s) }
        var p = Path()
        let w: CGFloat = 0.22
        p.addRoundedRect(in: CGRect(x: rect.minX + 0.16 * s, y: rect.minY + (1 - 0.92) * s, width: w * s, height: 0.82 * s),
                         cornerSize: CGSize(width: w * s / 2, height: w * s / 2))
        p.move(to: P(0.22, 0.10))
        p.addCurve(to: P(0.94, 0.52), control1: P(0.40, 0.02), control2: P(0.80, 0.10))
        p.addCurve(to: P(0.22, 0.10), control1: P(0.76, 0.52), control2: P(0.40, 0.48))
        p.closeSubpath()
        return p
    }
}

package enum LeanLogo {
    /// Colored menu bar image: the L body follows the system text color (light/dark), the leaf is mint green.
    /// macOS redraws the drawing handler for the current appearance, so the colors are always right.
    package static func menuBarImage(size: CGFloat = 18, ink: NSColor = .labelColor) -> NSImage {
        let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let s = rect.width
            func P(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x * s, y: y * s) }
            let w: CGFloat = 0.22
            ink.setFill()
            NSBezierPath(roundedRect: NSRect(x: 0.16 * s, y: 0.10 * s, width: w * s, height: 0.82 * s),
                         xRadius: w * s / 2, yRadius: w * s / 2).fill()
            let leaf = NSBezierPath()
            leaf.move(to: P(0.22, 0.10))
            leaf.curve(to: P(0.94, 0.52), controlPoint1: P(0.40, 0.02), controlPoint2: P(0.80, 0.10))
            leaf.curve(to: P(0.22, 0.10), controlPoint1: P(0.76, 0.52), controlPoint2: P(0.40, 0.48))
            leaf.close()
            NSColor(srgbRed: 0.18, green: 0.85, blue: 0.62, alpha: 1).setFill()
            leaf.fill()
            // Redraw the body over the leaf base so the L has a continuous stroke
            ink.setFill()
            NSBezierPath(roundedRect: NSRect(x: 0.16 * s, y: 0.10 * s, width: w * s, height: 0.82 * s),
                         xRadius: w * s / 2, yRadius: w * s / 2).fill()
            return true
        }
        img.isTemplate = false
        return img
    }
}
