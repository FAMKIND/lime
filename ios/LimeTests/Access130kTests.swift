import XCTest
@testable import Lime

/// LIME-130-7: the contrast guard covers every text/background pair a theme draws, for every theme, accent, mode and Increase Contrast.
final class Access130kTests: XCTestCase {
    func testEveryPairOfEveryThemeAccentModeAndContrastMeetsItsMinimum() {
        var worst: (ratio: Double, label: String)?
        var failures: [String] = []
        var count = 0
        for background in ThemeBackground.allCases {
            for accent in 0..<8 {
                for dark in [false, true] {
                    for increase in [false, true] {
                        let theme = ThemeResolver.resolve(accent: accent, background: background, dark: dark, increaseContrast: increase)
                        let darkMode = background.forcesDark || dark
                        let extra = background == .living ? LivingVeil.extremes(canvas: theme.canvas, dark: darkMode) : []
                        for pair in theme.pairs(increaseContrast: increase, extra: extra) {
                            count += 1
                            let margin = pair.ratio / pair.minimum
                            let label = "\(background.rawValue) accent \(accent) \(darkMode ? "dark" : "light")\(increase ? " IC" : "") \(pair.name): \(String(format: "%.2f", pair.ratio)) (needs \(pair.minimum))"
                            if worst == nil || margin < worst!.ratio { worst = (margin, label) }
                            if pair.ratio < pair.minimum - 0.005 { failures.append(label) }
                        }
                    }
                }
            }
        }
        print("LIME-130-7 sweep: \(count) pairs; tightest: \(worst?.label ?? "-")")
        XCTAssertTrue(failures.isEmpty, "\(failures.count) pairs fail, first: \(failures.prefix(8))")
    }

    func testTheLivingVeilIsStrongerInDarkAndTheSecondaryTextReadsOnTheLightestPhoto() {
        XCTAssertEqual(LivingVeil.opacity(dark: true), 0.85)
        let theme = ThemeResolver.resolve(accent: LimeColours.lime, background: .living, dark: true)
        for bg in LivingVeil.extremes(canvas: theme.canvas, dark: true) {
            XCTAssertGreaterThanOrEqual(ContrastGuard.ratio(theme.secondary, bg), 4.5)
        }
    }
}
