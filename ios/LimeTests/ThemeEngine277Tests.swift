import XCTest
@testable import Lime

/// LIME-277a/277b: the eight colours, the theme engine and its contrast guard.
final class ThemeEngine277Tests: XCTestCase {
    func testThereAreEightNamedColoursWithLimeAtFive() {
        XCTAssertEqual(LimeColours.names, ["Pink", "Peach", "Orange", "Yellow", "Blue", "Lime", "Lavender", "Cyan"])
        XCTAssertEqual(LimeColours.names[LimeColours.lime], "Lime")
        XCTAssertEqual(LimeColours.accentHex.count, 8)
        // Avatars, covers and the accent share the set: tone 5 is green in light and dark.
        for dark in [false, true] {
            var (r, g, b): (CGFloat, CGFloat, CGFloat) = (0, 0, 0)
            Theme.avatarUIColor(5, dark: dark).getRed(&r, green: &g, blue: &b, alpha: nil)
            XCTAssertTrue(g > r && g > b, "lime green, not periwinkle (dark: \(dark))")
        }
        XCTAssertEqual(ThemeBackground.allCases.count, 8)
    }

    func testEveryAccentOnEveryBackgroundInBothModesReadsAtAA() {
        for accent in 0..<8 {
            for background in ThemeBackground.allCases {
                for dark in [false, true] {
                    for increase in [false, true] {
                        let theme = ThemeResolver.resolve(accent: accent, background: background, dark: dark, increaseContrast: increase)
                        XCTAssertTrue(theme.passes(increaseContrast: increase), "\(LimeColours.name(accent)) on \(background.title), dark \(dark), increase contrast \(increase)")
                        XCTAssertGreaterThanOrEqual(ContrastGuard.ratio(theme.accentInk, theme.accent), 4.5)
                    }
                }
            }
        }
    }

    func testTheDefaultThemeIsLimesOwnColoursUnchanged() {
        for dark in [false, true] {
            let theme = ThemeResolver.resolve(accent: LimeColours.lime, background: .plain, dark: dark)
            func same(_ a: UIColor, _ name: String) {
                var x: (CGFloat, CGFloat, CGFloat) = (0, 0, 0), y: (CGFloat, CGFloat, CGFloat) = (0, 0, 0)
                a.getRed(&x.0, green: &x.1, blue: &x.2, alpha: nil)
                Theme.uiColor(name, dark: dark).getRed(&y.0, green: &y.1, blue: &y.2, alpha: nil)
                XCTAssertEqual(x.0, y.0, accuracy: 0.004, "\(name) dark \(dark)"); XCTAssertEqual(x.1, y.1, accuracy: 0.004); XCTAssertEqual(x.2, y.2, accuracy: 0.004)
            }
            same(theme.canvas, Theme.Name.canvas); same(theme.surface, Theme.Name.surface); same(theme.text, Theme.Name.text)
            same(theme.secondary, Theme.Name.textSecondary); same(theme.hairline, Theme.Name.hairline)
            same(theme.accent, Theme.Name.accent); same(theme.accentInk, Theme.Name.accentInk)
            same(theme.bubble, Theme.Name.bubbleOther); same(theme.bubbleEdge, Theme.Name.bubbleEdge); same(theme.link, Theme.Name.linkOther)
        }
    }

    /// 277g: the pairs the first guard did not cover. Every one passes for every accent, background, mode and Increase Contrast.
    func testTheBubblePairsLinksAndPlaceholdersPassOnEveryBackground() {
        let ownInk = UIColor(hex: 0x131B17)
        for background in ThemeBackground.allCases {
            for dark in [false, true] {
                for increase in [false, true] {
                    let t = ThemeResolver.resolve(accent: 5, background: background, dark: dark, increaseContrast: increase)
                    let label = "\(background.title), dark \(dark), increase contrast \(increase)"
                    XCTAssertGreaterThanOrEqual(ContrastGuard.ratio(t.text, t.bubble), increase ? 7 : 4.5, "the other person's text on their bubble: \(label)")
                    XCTAssertGreaterThanOrEqual(ContrastGuard.ratio(t.link, t.bubble), 4.5, "a link in their bubble: \(label)")
                    XCTAssertGreaterThanOrEqual(ContrastGuard.ratio(t.text, t.surface), increase ? 7 : 4.5, "a card: \(label)")
                    XCTAssertGreaterThanOrEqual(ContrastGuard.ratio(t.placeholder, t.canvas), 4.5, "a hint: \(label)")
                    XCTAssertGreaterThanOrEqual(ContrastGuard.ratio(t.placeholderLarge, t.canvas), 3, "a large hint: \(label)")
                    XCTAssertGreaterThan(ContrastGuard.ratio(t.bubble, t.canvas), 1.03, "the bubble can be told from the page: \(label)")
                }
            }
        }
        // My bubble keeps its own pair whatever the background.
        for (fill, name) in [(0xE4F9BE, "light"), (0x8ECF73, "dark")] { XCTAssertGreaterThanOrEqual(ContrastGuard.ratio(ownInk, UIColor(hex: UInt32(fill))), 4.5, name) }
    }

    func testTheGuardMovesFailingTextUntilItPassesAndLeavesGoodTextAlone() {
        let canvas = UIColor(hex: 0xF9F8F4)
        let weak = UIColor(hex: 0xC9C5BC)
        XCTAssertLessThan(ContrastGuard.ratio(weak, canvas), 4.5)
        let fixed = ContrastGuard.nudge(weak, against: [canvas], minimum: 4.5)
        XCTAssertGreaterThanOrEqual(ContrastGuard.ratio(fixed, canvas), 4.5)
        let good = UIColor(hex: 0x131B17)
        XCTAssertEqual(ContrastGuard.nudge(good, against: [canvas], minimum: 4.5), good)
        // Light text on a dark background is nudged lighter, not darker.
        let dark = UIColor(hex: 0x22392F)
        let on = ContrastGuard.nudge(UIColor(hex: 0x56705F), against: [dark], minimum: 4.5)
        XCTAssertGreaterThan(ContrastGuard.luminance(on), ContrastGuard.luminance(UIColor(hex: 0x56705F)))
        XCTAssertGreaterThanOrEqual(ContrastGuard.ratio(on, dark), 4.5)
    }

    func testChalkboardIsDarkInBothModesAndTheChoiceIsKeptPerAccount() {
        XCTAssertTrue(ThemeBackground.chalkboard.forcesDark)
        XCTAssertEqual(ThemeResolver.resolve(accent: 5, background: .chalkboard, dark: false), ThemeResolver.resolve(accent: 5, background: .chalkboard, dark: true))
        let suite = UserDefaults(suiteName: "lime.theme.test.\(UUID().uuidString)")!
        let store = ThemeStore()
        store.load(for: "a", defaults: suite)
        XCTAssertEqual(store.accent, LimeColours.lime)
        store.accent = 3
        store.background = .graph
        let again = ThemeStore()
        again.load(for: "a", defaults: .standard)
        XCTAssertEqual(again.background, .graph, "the same account gets its choice back")
        again.load(for: "b", defaults: .standard)
        XCTAssertEqual(again.background, .plain, "another account starts with lime's own look")
        store.reset()
        again.load(for: "a", defaults: .standard)
        XCTAssertEqual(again.background, .plain)
        for key in ["accent", "background"] { UserDefaults.standard.removeObject(forKey: "lime.theme.a.\(key)"); UserDefaults.standard.removeObject(forKey: "lime.theme.b.\(key)") }
    }
}
