import Observation
import SwiftUI
import UIKit

/// LIME-277a: the theme engine. One set of 8 colours (the avatar tones, with lime green at 5) is the accent choices; 8 backgrounds (277b) set the paper under
/// everything. The tokens in `Theme` are worked out from the choice for light or dark and then checked by the contrast guard, so text stays readable on whatever
/// is chosen. All of it is kept on this phone, per account space, and never sent.

/// The eight colours: the avatar tones, shared by avatars, covers and the accent.
enum LimeColours {
    /// What VoiceOver says and the pickers show, in tone order (index 5 is lime green).
    static let names = ["Pink", "Peach", "Orange", "Yellow", "Blue", "Lime", "Lavender", "Cyan"]
    static let lime = 5
    /// The vivid version of each tone, for the accent (a filled button, the "+", a badge). Lime is lime's own accent, unchanged.
    static let accentHex: [UInt32] = [0xF59AB0, 0xF7B39E, 0xF2A65A, 0xEBCB45, 0x6BB8F0, 0xA3E18A, 0xB99AF0, 0x5ED6E8]
    static func name(_ tone: Int) -> String { names[((tone % 8) + 8) % 8] }
}

/// The eight backgrounds.
enum ThemeBackground: String, CaseIterable, Identifiable {
    case plain, paper, dots, lined, graph, chalkboard, bulletin, living

    var id: String { rawValue }

    var title: String {
        switch self {
        case .plain: "Plain"
        case .paper: "Paper"
        case .dots: "Dot grid"
        case .lined: "Lined"
        case .graph: "Graph"
        case .chalkboard: "Chalkboard"
        case .bulletin: "Bulletin board"
        case .living: "Living"
        }
    }

    /// Chalkboard is dark-feeling in both modes, so the whole app is drawn dark on it.
    var forcesDark: Bool { self == .chalkboard }

    /// The colours under and on the paper, as hex (before the guard), for one mode.
    struct Base {
        var canvas: UInt32, surface: UInt32, text: UInt32, secondary: UInt32, hairline: UInt32
    }

    func base(dark: Bool) -> Base {
        switch (self, dark) {
        case (.plain, false), (.living, false): Base(canvas: 0xF9F8F4, surface: 0xF0EEE6, text: 0x131B17, secondary: 0x504840, hairline: 0xDDDDD9)
        case (.plain, true), (.living, true): Base(canvas: 0x131B17, surface: 0x212925, text: 0xF5F3ED, secondary: 0xA09890, hairline: 0x3D4441)
        case (.paper, false): Base(canvas: 0xF5F0E2, surface: 0xECE5D1, text: 0x1F1A12, secondary: 0x56493A, hairline: 0xD8CFBA)
        case (.paper, true): Base(canvas: 0x1D1B16, surface: 0x2A2720, text: 0xF3EFE4, secondary: 0xA8A092, hairline: 0x433E33)
        case (.dots, false): Base(canvas: 0xFAF9F5, surface: 0xF0EEE6, text: 0x131B17, secondary: 0x504840, hairline: 0xDDDDD9)
        case (.dots, true): Base(canvas: 0x141A17, surface: 0x212925, text: 0xF5F3ED, secondary: 0xA09890, hairline: 0x3D4441)
        case (.lined, false): Base(canvas: 0xFBFAF2, surface: 0xF0EEE4, text: 0x131B17, secondary: 0x504840, hairline: 0xD9D8D0)
        case (.lined, true): Base(canvas: 0x151B1B, surface: 0x222A2A, text: 0xF5F3ED, secondary: 0xA09890, hairline: 0x3D4545)
        case (.graph, false): Base(canvas: 0xF7FAF4, surface: 0xEBF0E6, text: 0x131B17, secondary: 0x4A5048, hairline: 0xD3DCCD)
        case (.graph, true): Base(canvas: 0x131C18, surface: 0x202B25, text: 0xF2F5EE, secondary: 0x9CA69C, hairline: 0x3A4740)
        case (.chalkboard, _): Base(canvas: 0x22392F, surface: 0x2E4A3E, text: 0xF2F0E6, secondary: 0xC4CCBE, hairline: 0x4A6558)
        // Cork, with the cards as pinned cream surfaces; in the dark the cork is deep brown and the cards a lighter brown.
        case (.bulletin, false): Base(canvas: 0xD9B98F, surface: 0xFBF3E4, text: 0x2B1B0E, secondary: 0x5A4430, hairline: 0xB8955F)
        case (.bulletin, true): Base(canvas: 0x3B2C20, surface: 0x4A392B, text: 0xF3E9DA, secondary: 0xCDBCA6, hairline: 0x5E4A38)
        }
    }
}

/// WCAG 2.2 contrast: 4.5:1 for text, 3:1 for large text, icons and controls.
enum ContrastGuard {
    static let text = 4.5
    static let large = 3.0
    /// With Increase Contrast on, text is pushed further.
    static let enhanced = 7.0

    static func luminance(_ colour: UIColor) -> Double {
        var (r, g, b, a): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        colour.getRed(&r, green: &g, blue: &b, alpha: &a)
        func lin(_ v: CGFloat) -> Double { let x = Double(v); return x <= 0.03928 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }

    static func ratio(_ a: UIColor, _ b: UIColor) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    static func blend(_ a: UIColor, _ b: UIColor, _ t: CGFloat) -> UIColor {
        var (ar, ag, ab, aa): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        var (br, bg, bb, ba): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        a.getRed(&ar, green: &ag, blue: &ab, alpha: &aa); b.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        return UIColor(red: ar + (br - ar) * t, green: ag + (bg - ag) * t, blue: ab + (bb - ab) * t, alpha: 1)
    }

    /// `colour` moved toward black or white (whichever helps) until it reaches `minimum` against every one of `backgrounds`. Unchanged when it already does.
    static func nudge(_ colour: UIColor, against backgrounds: [UIColor], minimum: Double) -> UIColor {
        func worst(_ c: UIColor) -> Double { backgrounds.map { ratio(c, $0) }.min() ?? 21 }
        if worst(colour) >= minimum { return colour }
        let target: UIColor = backgrounds.map { luminance($0) }.reduce(0, +) / Double(backgrounds.count) > 0.4 ? .black : .white
        var t: CGFloat = 0
        while t < 1 {
            t += 0.02
            let moved = blend(colour, target, min(1, t))
            if worst(moved) >= minimum { return moved }
        }
        return target
    }

    /// Dark ink or white, whichever reads better on `fill` (the dark ink first: it is lime's own).
    static func ink(on fill: UIColor, minimum: Double = text) -> UIColor {
        let dark = UIColor(hex: 0x131B17)
        if ratio(dark, fill) >= minimum { return dark }
        if ratio(.white, fill) >= minimum { return .white }
        return nudge(dark, against: [fill], minimum: minimum)
    }
}

/// A theme worked out for one accent, background and mode.
struct ResolvedTheme: Equatable {
    var canvas: UIColor, surface: UIColor, text: UIColor, secondary: UIColor, hairline: UIColor, accent: UIColor, accentInk: UIColor

    /// Every pairing the app draws text in meets WCAG AA (7:1 for the main text with Increase Contrast).
    func passes(increaseContrast: Bool = false) -> Bool {
        let main = increaseContrast ? ContrastGuard.enhanced : ContrastGuard.text
        return ContrastGuard.ratio(text, canvas) >= main && ContrastGuard.ratio(text, surface) >= main
            && ContrastGuard.ratio(secondary, canvas) >= ContrastGuard.text && ContrastGuard.ratio(secondary, surface) >= ContrastGuard.text
            && ContrastGuard.ratio(accentInk, accent) >= ContrastGuard.text
    }
}

enum ThemeResolver {
    nonisolated(unsafe) private static var cache: [String: ResolvedTheme] = [:]
    private static let lock = NSLock()

    static func resolve(accent: Int, background: ThemeBackground, dark: Bool, increaseContrast: Bool = false) -> ResolvedTheme {
        let darkMode = background.forcesDark || dark
        let key = "\(accent)|\(background.rawValue)|\(darkMode)|\(increaseContrast)"
        lock.lock(); defer { lock.unlock() }
        if let hit = cache[key] { return hit }
        let base = background.base(dark: darkMode)
        let canvas = UIColor(hex: base.canvas), surface = UIColor(hex: base.surface)
        let on = [canvas, surface]
        let text = ContrastGuard.nudge(UIColor(hex: base.text), against: on, minimum: increaseContrast ? ContrastGuard.enhanced : ContrastGuard.text)
        let secondary = ContrastGuard.nudge(UIColor(hex: base.secondary), against: on, minimum: increaseContrast ? ContrastGuard.enhanced : ContrastGuard.text)
        var hairline = UIColor(hex: base.hairline)
        if increaseContrast { hairline = ContrastGuard.nudge(hairline, against: [canvas], minimum: ContrastGuard.large) }
        let accentFill = UIColor(hex: LimeColours.accentHex[((accent % 8) + 8) % 8])
        let made = ResolvedTheme(canvas: canvas, surface: surface, text: text, secondary: secondary, hairline: hairline, accent: accentFill, accentInk: ContrastGuard.ink(on: accentFill))
        cache[key] = made
        return made
    }
}

/// What the person chose, kept on this phone for the account that is open.
@Observable
final class ThemeStore: @unchecked Sendable {
    nonisolated(unsafe) static let shared = ThemeStore()

    /// The tone index of the accent (5 = lime, the default).
    var accent = LimeColours.lime { didSet { save() } }
    var background = ThemeBackground.plain { didSet { save() } }

    /// My own picture, for the Living background's colours (set by the app when it has one).
    var livingPhoto: UIImage?
    private var space: String?
    private var loading = false

    private func key(_ name: String) -> String { "lime.theme.\(space ?? "none").\(name)" }

    /// Opens the choice of one account's space (nil: signed out, lime's own look).
    func load(for account: String?, defaults: UserDefaults = .standard) {
        loading = true
        defer { loading = false }
        space = account
        guard account != nil else { accent = LimeColours.lime; background = .plain; return }
        let stored = defaults.object(forKey: key("accent")) as? Int
        accent = stored.map { min(7, max(0, $0)) } ?? LimeColours.lime
        background = defaults.string(forKey: key("background")).flatMap(ThemeBackground.init(rawValue:)) ?? .plain
        #if DEBUG
        // Screenshots and UI tests: `-lime-theme-accent 3 -lime-theme-background chalkboard`.
        let arguments = ProcessInfo.processInfo.arguments
        if let at = arguments.firstIndex(of: "-lime-theme-accent"), at + 1 < arguments.count, let value = Int(arguments[at + 1]) { accent = min(7, max(0, value)) }
        if let at = arguments.firstIndex(of: "-lime-theme-background"), at + 1 < arguments.count, let value = ThemeBackground(rawValue: arguments[at + 1]) { background = value }
        #endif
    }

    private func save(defaults: UserDefaults = .standard) {
        guard !loading, space != nil else { return }
        defaults.set(accent, forKey: key("accent"))
        defaults.set(background.rawValue, forKey: key("background"))
    }

    func reset() { accent = LimeColours.lime; background = .plain }

    /// The theme for a trait collection, read when a colour is drawn.
    func resolved(dark: Bool) -> ResolvedTheme {
        ThemeResolver.resolve(accent: accent, background: background, dark: dark, increaseContrast: UIAccessibility.isDarkerSystemColorsEnabled)
    }

    enum Role { case canvas, surface, text, secondary, hairline, accent, accentInk }

    /// A colour that follows the choice. Reading `accent` and `background` here makes the view that asked redraw when they change.
    func colour(_ role: Role) -> Color {
        _ = accent; _ = background
        return Color(UIColor { [self] traits in
            let theme = resolved(dark: traits.userInterfaceStyle == .dark)
            switch role {
            case .canvas: return theme.canvas
            case .surface: return theme.surface
            case .text: return theme.text
            case .secondary: return theme.secondary
            case .hairline: return theme.hairline
            case .accent: return theme.accent
            case .accentInk: return theme.accentInk
            }
        })
    }
}
