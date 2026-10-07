import SwiftUI
import UIKit

private final class BundleToken {}

/// Colours ported from `public/css/lime.css` (default Warm light tone, and dark).
/// Values live in the asset catalog; the names are here so tests can resolve them.
enum Theme {
    enum Name {
        static let canvas = "Canvas"
        static let surface = "Surface"
        static let bubbleOther = "BubbleOther"
        static let bubbleEdge = "BubbleEdge"
        /// `--lime-primary-bg`: the own bubble, the unread badge, the "+" button.
        static let primary = "OwnBubble"
        /// `--lime-primary-ink`
        static let primaryInk = "OwnInk"
        /// The accent for unread badges and the Messages "+" (not the own bubble).
        static let accent = "Accent"
        static let accentInk = "AccentInk"
        static let text = "TextPrimary"
        static let textSecondary = "TextSecondary"
        static let hairline = "Hairline"
        /// Links: a green that keeps 4.5:1 contrast on the surface it sits on (see ThemeTests).
        static let linkOther = "LinkOther"
        static let linkOwn = "LinkOwn"
        /// A warm neutral for active and pressed states (the formatting toolbar). The accent is only for the primary action.
        static let pressed = "Pressed"
        /// Find: every matched word, the current one, and the ink on both (fixed, so it reads on any bubble).
        static let findMatch = "FindMatch"
        static let findCurrent = "FindCurrent"
        static let findInk = "FindInk"
    }

    static func color(_ name: String) -> Color {
        Color(name, bundle: Bundle(for: BundleToken.self))
    }

    static let canvas = color(Name.canvas)
    static let surface = color(Name.surface)
    static let bubbleOther = color(Name.bubbleOther)
    static let bubbleEdge = color(Name.bubbleEdge)
    static let primary = color(Name.primary)
    static let primaryInk = color(Name.primaryInk)
    static let accent = color(Name.accent)
    static let accentInk = color(Name.accentInk)
    static let ownBubble = primary
    static let ownBubbleInk = primaryInk
    static let text = color(Name.text)
    static let textSecondary = color(Name.textSecondary)
    static let hairline = color(Name.hairline)
    /// A link in someone else's bubble, and in the composer.
    static let linkOther = color(Name.linkOther)
    /// A link in my own bubble.
    static let linkOwn = color(Name.linkOwn)
    static let pressed = color(Name.pressed)
    static let findMatch = color(Name.findMatch)
    static let findCurrent = color(Name.findCurrent)
    static let findInk = color(Name.findInk)

    /// The selection, the caret and its handles: the system's own blue, never the accent.
    static let selectionUIColor = UIColor.systemBlue
    static let selection = Color(uiColor: selectionUIColor)

    /// Resolves an asset colour for a given appearance (used by the contrast tests).
    static func uiColor(_ name: String, dark: Bool) -> UIColor {
        UIColor(named: name, in: Bundle(for: BundleToken.self), compatibleWith: nil)!
            .resolvedColor(with: UITraitCollection(userInterfaceStyle: dark ? .dark : .light))
    }

    // Radii
    static let bubbleRadius: CGFloat = 22

    // Typography. The web app uses Montserrat (`--seed-font-ui`); the native app uses
    // the system font (SF) for now. Whether to bundle Montserrat is a later decision.
    static let title = Font.system(.body, design: .default, weight: .semibold)
    static let body = Font.system(.body)
    static let secondary = Font.system(.subheadline)
    static let caption = Font.system(.caption)

    /// The web app's avatar pastels (`--lime-avatar-0…7`), light and dark.
    private static let avatarLight: [UInt32] = [0xFEB2BF, 0xFED2CA, 0xF3BF91, 0xEFDF91, 0x92D4FF, 0xD1DEFE, 0xD9BAFF, 0x99EEFF]
    private static let avatarDark: [UInt32] = [0xDF8193, 0xEF9B8D, 0xC59770, 0xC3B571, 0x51ABE2, 0x98B2F7, 0xB091D6, 0x78C2D1]

    static func avatar(_ tone: Int) -> Color {
        let i = ((tone % 8) + 8) % 8
        func ui(_ hex: UInt32) -> UIColor {
            UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                    blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
        let light = ui(avatarLight[i]), dark = ui(avatarDark[i])
        return Color(UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
}

extension View {
    /// Text fields show the system's blue selection and caret, whatever tint the screen around them has.
    func selectionTint() -> some View { tint(Theme.selection) }
}
