import XCTest
@testable import Lime

/// LIME-188q: every button colour reads at 4.5:1 (label on fill) in light and dark; lime is the default; the actions are the ones lime knows.
final class ButtonPaletteTests: XCTestCase {
    private func luminance(_ hex: UInt32) -> Double {
        func lin(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        let r = lin(Double((hex >> 16) & 0xFF) / 255), g = lin(Double((hex >> 8) & 0xFF) / 255), b = lin(Double(hex & 0xFF) / 255)
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }
    private func ratio(_ a: UInt32, _ b: UInt32) -> Double {
        let (x, y) = (luminance(a), luminance(b))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    func testEveryColourReadsAtFourPointFiveToOneInLightAndDark() {
        for palette in ButtonPalette.allCases {
            XCTAssertGreaterThanOrEqual(ratio(palette.light.fill, palette.light.label), 4.5, "\(palette.title) light: \(ratio(palette.light.fill, palette.light.label))")
            XCTAssertGreaterThanOrEqual(ratio(palette.dark.fill, palette.dark.label), 4.5, "\(palette.title) dark: \(ratio(palette.dark.fill, palette.dark.label))")
        }
    }

    func testLimeIsTheDefaultAndAnUnknownNameIsLime() {
        XCTAssertEqual(ButtonPalette.allCases.first, .lime)
        XCTAssertEqual(ButtonPalette.allCases.count, 6)
        XCTAssertEqual(ButtonPalette.named(""), .lime)
        XCTAssertEqual(ButtonPalette.named("chartreuse"), .lime)
        XCTAssertEqual(ButtonPalette.named("blue"), .blue)
    }

    func testAnAddressIsAnActionOrALink() {
        XCTAssertEqual(ButtonAction(url: "lime:subscribe"), .subscribe)
        XCTAssertEqual(ButtonAction(url: "lime:message"), .message)
        XCTAssertEqual(ButtonAction(url: "lime:share").address, "lime:share")
        XCTAssertEqual(ButtonAction(url: "https://example.com"), .link("https://example.com"))
    }

    func testTheEditorKeepsAButtonsCaptionAndColourAndHeadingsGoToSix() {
        let markdown = "###### Small\n\n[[Message me]](lime:message \"Ask me\"){.blue}"
        let text = ComposerDocument.attributed(fromMarkdown: markdown, post: true)
        XCTAssertEqual(ComposerDocument.markdown(from: text, post: true), markdown)
    }
}
