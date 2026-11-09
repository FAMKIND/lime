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
        /// A reaction chip: barely there, so the emoji is the clear thing (mine a touch deeper).
        static let chipFill = "ChipFill"
        static let chipFillMine = "ChipFillMine"
        /// Find: every matched word, the current one, and the ink on both (fixed, so it reads on any bubble).
        static let findMatch = "FindMatch"
        static let findCurrent = "FindCurrent"
        static let findInk = "FindInk"
    }

    static func color(_ name: String) -> Color {
        Color(name, bundle: Bundle(for: BundleToken.self))
    }

    // The tokens the theme drives (LIME-277a): computed from the accent and background chosen, light or dark, and checked by the contrast guard.
    static var canvas: Color { ThemeStore.shared.colour(.canvas) }
    static var surface: Color { ThemeStore.shared.colour(.surface) }
    static var bubbleOther: Color { ThemeStore.shared.colour(.bubble) }
    static var bubbleEdge: Color { ThemeStore.shared.colour(.bubbleEdge) }
    static var primary: Color { ThemeStore.shared.colour(.own) }
    static var primaryInk: Color { ThemeStore.shared.colour(.ownInk) }
    static var accent: Color { ThemeStore.shared.colour(.accent) }
    /// A filled heart (LIME-189d): the buttons' Red (docs: `ButtonPalette.red`): #B3261E in light, #FFB4AB in dark; on a black screen always the light one.
    static let heartHex: (light: UInt32, dark: UInt32) = (0xB3261E, 0xFFB4AB)
    static let heart = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: heartHex.dark) : UIColor(hex: heartHex.light) })
    static let heartOnBlack = Color(UIColor(hex: heartHex.dark))
    /// Red for text and icons (LIME-130-2): #B3261E in light, #FF8A80 in dark, nudged per theme to 4.5:1 (7:1 with Increase Contrast) on the canvas, surface and bubble.
    static let dangerHex: (light: UInt32, dark: UInt32) = (0xB3261E, 0xFF8A80)
    static var danger: Color { ThemeStore.shared.colour(.danger) }
    /// Red under white text or a white glyph (Delete, End call, Decline, recording): white on it is 6.5:1 (8:1 with Increase Contrast), light and dark.
    static let dangerFillHex: (normal: UInt32, increased: UInt32) = (0xB3261E, 0x9C1F18)
    static let dangerFillUIColor = UIColor { $0.accessibilityContrast == .high ? UIColor(hex: dangerFillHex.increased) : UIColor(hex: dangerFillHex.normal) }
    static let dangerFill = Color(dangerFillUIColor)
    static var accentInk: Color { ThemeStore.shared.colour(.accentInk) }
    // My bubble and the main button follow the accent (LIME-277d); a chat can have its own colour (`ChatLook`).
    static var ownBubble: Color { ThemeStore.shared.colour(.own) }
    static var ownBubbleInk: Color { ThemeStore.shared.colour(.ownInk) }
    /// Captions in my bubble: the ink a little softer, 4.5:1 on it (LIME-130-3a).
    static var ownBubbleSecondary: Color { ThemeStore.shared.colour(.ownSecondary) }
    static var text: Color { ThemeStore.shared.colour(.text) }
    static var textSecondary: Color { ThemeStore.shared.colour(.secondary) }
    /// The soft grey of an empty field's hint (LIME-188f): one grey for every placeholder, readable (4.5:1) on the canvas in light and dark.
    /// (LIME-188l: softer than the text grey, still 4.5:1 on the canvas in light and dark.)
    static var placeholder: Color { ThemeStore.shared.colour(.placeholder) }
    /// The hint of a large field, the article's title (bold, over 14 pt, so WCAG's 3:1 for large text applies): lighter still.
    static var placeholderLarge: Color { ThemeStore.shared.colour(.placeholderLarge) }
    static var hairline: Color { ThemeStore.shared.colour(.hairline) }
    /// A link in someone else's bubble, and in the composer.
    static var linkOther: Color { ThemeStore.shared.colour(.link) }
    /// A link in my own bubble.
    static var linkOwn: Color { ThemeStore.shared.colour(.linkOwn) }
    static let pressed = color(Name.pressed)
    static var chipFill: Color { ThemeStore.shared.colour(.chip) }
    static var chipFillMine: Color { ThemeStore.shared.colour(.chipMine) }
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
    static var title: Font { font(.body, weight: .semibold) }
    static var body: Font { font(.body) }
    static var secondary: Font { font(.subheadline) }
    static var caption: Font { font(.caption) }

    /// A text style in lime's typeface (LIME-168): the system font by default, or the one chosen in Settings → Customize → Text size. Always
    /// scales with Dynamic Type and lime's own size. Reading it inside a view's body makes the view follow a change of typeface.
    static func font(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        TextPreferences.shared.typeface.font(style, weight: weight)
    }

    /// The web app's avatar pastels (`--lime-avatar-0…7`), light and dark; index 5 is lime green (LIME-277a: it replaced periwinkle, so avatars, covers and the accent share one set of 8).
    private static let avatarLight: [UInt32] = [0xFEB2BF, 0xFED2CA, 0xF3BF91, 0xEFDF91, 0x92D4FF, 0xC4EFA6, 0xD9BAFF, 0x99EEFF]
    private static let avatarDark: [UInt32] = [0xDF8193, 0xEF9B8D, 0xC59770, 0xC3B571, 0x51ABE2, 0x7FBF5F, 0xB091D6, 0x78C2D1]

    /// The avatar pastel as a plain colour, for one appearance.
    static func avatarUIColor(_ tone: Int, dark: Bool) -> UIColor {
        let i = ((tone % 8) + 8) % 8
        let hex = (dark ? avatarDark : avatarLight)[i]
        return UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }

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

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
