import XCTest
import UIKit
@testable import Lime

/// Links get a green of their own on each surface, with at least 4.5:1 contrast, and are told apart from
/// the text colour (an underline alone is `__underline__`).
final class LinkColourTests: XCTestCase {
    private func luminance(_ color: UIColor) -> Double {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        func lin(_ c: CGFloat) -> Double { let v = Double(c); return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }

    private func contrast(_ a: String, _ b: String, dark: Bool) -> Double {
        let la = luminance(Theme.uiColor(a, dark: dark)), lb = luminance(Theme.uiColor(b, dark: dark))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    func testEveryLinkColourPassesFourPointFiveToOneOnItsSurface() {
        let pairs: [(link: String, surface: String, what: String)] = [
            (Theme.Name.linkOther, Theme.Name.bubbleOther, "a link in someone else's bubble"),
            (Theme.Name.linkOwn, Theme.Name.primary, "a link in my own bubble"),
            (Theme.Name.linkOther, Theme.Name.canvas, "a link in the composer (on the canvas)"),
            (Theme.Name.linkOther, Theme.Name.surface, "a link on a surface card"),
        ]
        for dark in [false, true] {
            for pair in pairs {
                let ratio = contrast(pair.link, pair.surface, dark: dark)
                XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(pair.what), \(dark ? "dark" : "light"): \(String(format: "%.2f", ratio)):1")
            }
        }
    }

    func testALinkIsNotTheTextColour() {
        // The link's green differs from the ink of its own bubble, so it is not mistaken for plain underlined text.
        for dark in [false, true] {
            let otherInk = luminance(Theme.uiColor(Theme.Name.text, dark: dark)), otherLink = luminance(Theme.uiColor(Theme.Name.linkOther, dark: dark))
            XCTAssertGreaterThanOrEqual((max(otherInk, otherLink) + 0.05) / (min(otherInk, otherLink) + 0.05), 1.4, "neutral bubble, dark: \(dark)")
            let ownInk = luminance(Theme.uiColor(Theme.Name.primaryInk, dark: dark)), ownLink = luminance(Theme.uiColor(Theme.Name.linkOwn, dark: dark))
            XCTAssertGreaterThanOrEqual((max(ownInk, ownLink) + 0.05) / (min(ownInk, ownLink) + 0.05), 1.4, "own bubble, dark: \(dark)")
        }
    }

    func testALinkIsGreenAndUnderlinedWhileAnUnderlineKeepsTheTextColour() {
        let spans = [
            Span(text: "plain ", bold: false, italic: false, underline: false, strike: false, code: false, link: nil),
            Span(text: "underlined", bold: false, italic: false, underline: true, strike: false, code: false, link: nil),
            Span(text: " and ", bold: false, italic: false, underline: false, strike: false, code: false, link: nil),
            Span(text: "link", bold: false, italic: false, underline: false, strike: false, code: false, link: "https://limechat.org"),
        ]
        let text = MessageRender.attributed(spans, ink: .black, link: .green)
        var byWord: [String: AttributedString.Runs.Run] = [:]
        for run in text.runs { byWord[String(text[run.range].characters)] = run }
        let underline = byWord["underlined"], link = byWord["link"]
        XCTAssertEqual(underline?.underlineStyle, .single)
        XCTAssertNil(underline?.foregroundColor, "an underline keeps the text colour")
        XCTAssertNil(underline?.link)
        XCTAssertEqual(link?.underlineStyle, .single, "a link is underlined too")
        XCTAssertEqual(link?.foregroundColor, .green, "but in its own colour")
        XCTAssertEqual(link?.link?.absoluteString, "https://limechat.org")
        XCTAssertNil(link?.backgroundColor)

        let pressed = MessageRender.attributed(spans, ink: .black, link: .green, pressed: "https://limechat.org")
        let pressedLink = pressed.runs.first { $0.link != nil }
        XCTAssertNotNil(pressedLink?.backgroundColor, "the tapped link shows pressed")
        let others = pressed.runs.filter { $0.link == nil && $0.backgroundColor != nil }
        XCTAssertTrue(others.isEmpty, "and only that link")
    }
}
