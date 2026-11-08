import XCTest
@testable import Lime

/// LIME-130-2: the red for text and icons reads on the canvas, the surface and the bubble, and white reads on the red fill, in light and dark and with
/// Increase Contrast, on every background.
final class Danger130Tests: XCTestCase {
    private func report() -> String {
        var lines: [String] = []
        for background in ThemeBackground.allCases {
            for dark in [false, true] {
                for ic in [false, true] {
                    let t = ThemeResolver.resolve(accent: LimeColours.lime, background: background, dark: dark, increaseContrast: ic)
                    lines.append("\(background.rawValue) \(dark ? "dark" : "light")\(ic ? " IC" : ""): canvas \(ContrastGuard.ratio(t.danger, t.canvas)) surface \(ContrastGuard.ratio(t.danger, t.surface))")
                }
            }
        }
        return lines.joined(separator: "\n")
    }

    func testDangerTextHas4Point5OnCanvasSurfaceAndBubbleEverywhere() {
        for background in ThemeBackground.allCases {
            for dark in [false, true] {
                let t = ThemeResolver.resolve(accent: LimeColours.lime, background: background, dark: dark, increaseContrast: false)
                for (name, bg) in [("canvas", t.canvas), ("surface", t.surface), ("bubble", t.bubble)] {
                    XCTAssertGreaterThanOrEqual(ContrastGuard.ratio(t.danger, bg), 4.5, "\(background.rawValue) \(dark ? "dark" : "light") \(name)")
                }
            }
        }
    }

    func testWithIncreaseContrastDangerTextHasSevenToOne() {
        for background in ThemeBackground.allCases {
            for dark in [false, true] {
                let t = ThemeResolver.resolve(accent: LimeColours.lime, background: background, dark: dark, increaseContrast: true)
                for (name, bg) in [("canvas", t.canvas), ("surface", t.surface), ("bubble", t.bubble)] {
                    XCTAssertGreaterThanOrEqual(ContrastGuard.ratio(t.danger, bg), 7.0, "\(background.rawValue) \(dark ? "dark" : "light") IC \(name)")
                }
            }
        }
    }

    func testWhiteOnTheDangerFillHas4Point5() {
        XCTAssertGreaterThanOrEqual(ContrastGuard.ratio(.white, UIColor(hex: Theme.dangerFillHex.normal)), 4.5)
        XCTAssertGreaterThanOrEqual(ContrastGuard.ratio(.white, UIColor(hex: Theme.dangerFillHex.increased)), 7.0)
    }

    func testTheAcceptButtonsInkOnLimeGreenHas4Point5() {
        XCTAssertGreaterThanOrEqual(ContrastGuard.ratio(UIColor(hex: 0x131B17), UIColor(hex: LimeColours.accentHex[LimeColours.lime])), 4.5)
    }

    @MainActor func testTheAvailabilityBadgeHas3OnTheCanvasAndSurfaceInLightAndDark() {
        let bases: [UInt32] = [0xF9F8F4, 0xF0EEE6, 0x131B17, 0x212925]
        for (name, hex) in [("available", StatusBadge.availableHex), ("away", StatusBadge.awayHex), ("dnd", StatusBadge.dndHex)] {
            for base in bases { XCTAssertGreaterThanOrEqual(ContrastGuard.ratio(UIColor(hex: hex), UIColor(hex: base)), 3.0, "\(name) on \(String(base, radix: 16))") }
        }
        // The moon and the z are white on the away and do-not-disturb discs.
        XCTAssertGreaterThanOrEqual(ContrastGuard.ratio(.white, UIColor(hex: StatusBadge.awayHex)), 3.0)
        XCTAssertGreaterThanOrEqual(ContrastGuard.ratio(.white, UIColor(hex: StatusBadge.dndHex)), 3.0)
    }

    func testNoColorRedTextRemains() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Lime")
        var found: [String] = []
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)!
        for case let url as URL in files where url.pathExtension == "swift" && !url.path.contains("/Generated/") && !url.path.hasSuffix("JamButtons.swift") {
            let text = try String(contentsOf: url, encoding: .utf8)
            for (i, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
            where line.contains("Color.red") || line.contains("foregroundStyle(.red)") || line.contains("systemRed") || line.contains("Color(red: 0.72, green: 0.17, blue: 0.2)") {
                found.append("\(url.lastPathComponent):\(i + 1)")
            }
        }
        XCTAssertEqual(found, [], "red is Theme.danger (text, icons) or Theme.dangerFill (under white)")
    }
}
