import XCTest
import UIKit
import SwiftUI
@testable import Lime

/// The accent green is for the one primary action on a screen. Selection is the system blue, active and
/// pressed states are a warm neutral, and find highlights words in yellow.
@MainActor
final class ColourHierarchyTests: XCTestCase {
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

    func testTheSelectionTintIsTheSystemBlueAndNotTheAccent() {
        XCTAssertEqual(Theme.selectionUIColor, UIColor.systemBlue)
        for dark in [false, true] {
            let traits = UITraitCollection(userInterfaceStyle: dark ? .dark : .light)
            let blue = Theme.selectionUIColor.resolvedColor(with: traits)
            let accent = Theme.uiColor(Theme.Name.accent, dark: dark)
            XCTAssertNotEqual(blue, accent)
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            blue.getRed(&r, green: &g, blue: &b, alpha: &a)
            XCTAssertGreaterThan(b, g, "it is blue")
            XCTAssertGreaterThan(b, r)
        }
    }

    func testTheComposerTextViewIsGivenTheSystemBlueTint() {
        XCTAssertEqual(ComposerTextView().tintColor, UIColor.systemBlue)
    }

    func testThePressedNeutralIsNotTheAccentAndReadsOnTheBar() {
        for dark in [false, true] {
            let pressed = Theme.uiColor(Theme.Name.pressed, dark: dark)
            XCTAssertNotEqual(pressed, Theme.uiColor(Theme.Name.accent, dark: dark), "an active format button is not the accent")
            // LIME-104-fix: lighter still (about half the contrast of before): 1.2 to 1.4:1 on the canvas; the icon weight carries the state.
            let bar = contrast(Theme.Name.pressed, Theme.Name.canvas, dark: dark)
            XCTAssertGreaterThanOrEqual(bar, 1.2, "the pressed fill against the bar, dark: \(dark): \(String(format: "%.2f", bar))")
            XCTAssertLessThanOrEqual(bar, 1.4, "and not as heavy as the old grey circles, dark: \(dark)")
            let onSurface = contrast(Theme.Name.pressed, Theme.Name.surface, dark: dark)
            XCTAssertGreaterThanOrEqual(onSurface, 1.05, "against the surface the composer sits on, dark: \(dark): \(String(format: "%.2f", onSurface))")
            let ink = contrast(Theme.Name.pressed, Theme.Name.text, dark: dark)
            XCTAssertGreaterThanOrEqual(ink, 4.5, "the ink on the pressed fill, dark: \(dark): \(String(format: "%.2f", ink))")
            // warm, not blue-grey: red is not below blue
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            pressed.getRed(&r, green: &g, blue: &b, alpha: &a)
            XCTAssertGreaterThanOrEqual(r, b)
        }
    }

    func testFindHighlightsReadOnEveryBubbleAndTheCurrentMatchIsStronger() {
        for dark in [false, true] {
            for name in [Theme.Name.findMatch, Theme.Name.findCurrent] {
                XCTAssertGreaterThanOrEqual(contrast(Theme.Name.findInk, name, dark: dark), 4.5, "\(name) dark: \(dark)")
                XCTAssertNotEqual(Theme.uiColor(name, dark: dark), Theme.uiColor(Theme.Name.accent, dark: dark))
            }
            // Stronger = more saturated: the current match's yellow is deeper than the others'.
            XCTAssertGreaterThan(luminance(Theme.uiColor(Theme.Name.findMatch, dark: dark)), luminance(Theme.uiColor(Theme.Name.findCurrent, dark: dark)))
            // Both stand out from each bubble they sit on.
            for bubble in [Theme.Name.bubbleOther, Theme.Name.primary] {
                XCTAssertNotEqual(Theme.uiColor(Theme.Name.findMatch, dark: dark), Theme.uiColor(bubble, dark: dark))
            }
        }
    }

    private func spans(_ text: String) -> [Span] {
        [Span(text: text, bold: false, italic: false, underline: false, strike: false, code: false, link: nil)]
    }

    private func highlighted(_ text: AttributedString) -> [String: Color] {
        var found: [String: Color] = [:]
        for run in text.runs { if let background = run.backgroundColor { found[String(text[run.range].characters)] = background } }
        return found
    }

    func testFindHighlightsTheMatchedWordsNotTheWholeMessage() {
        let text = MessageRender.attributed(spans("Lesson planning is due; plan early"), ink: .black, link: .green,
                                            find: FindStyle(words: SearchText.words("plan"), current: false))
        XCTAssertEqual(highlighted(text), ["planning": Theme.findMatch, "plan": Theme.findMatch], "each word that starts with the typed word, nothing else")
        for run in text.runs where run.backgroundColor != nil { XCTAssertEqual(run.foregroundColor, Theme.findInk) }
    }

    func testTheCurrentMatchIsHighlightedStrongerAndCaseAndAccentsAreIgnored() {
        let current = MessageRender.attributed(spans("Café ÉCOLE"), ink: .black, link: .green, find: FindStyle(words: SearchText.words("cafe ecole"), current: true))
        XCTAssertEqual(highlighted(current), ["Café": Theme.findCurrent, "ÉCOLE": Theme.findCurrent])
        let other = MessageRender.attributed(spans("Café"), ink: .black, link: .green, find: FindStyle(words: ["cafe"], current: false))
        XCTAssertEqual(highlighted(other), ["Café": Theme.findMatch])
    }

    func testNoFindWordsMeansNoHighlight() {
        let text = MessageRender.attributed(spans("Lesson plan"), ink: .black, link: .green, find: FindStyle(words: [], current: true))
        XCTAssertTrue(highlighted(text).isEmpty)
        XCTAssertTrue(highlighted(MessageRender.attributed(spans("Lesson plan"), ink: .black, link: .green)).isEmpty)
    }

    func testAHighlightAcrossStyledRunsStaysOnTheWord() {
        let styled = [
            Span(text: "the ", bold: false, italic: false, underline: false, strike: false, code: false, link: nil),
            Span(text: "plan", bold: true, italic: false, underline: false, strike: false, code: false, link: nil),
            Span(text: "ning day", bold: false, italic: false, underline: false, strike: false, code: false, link: nil),
        ]
        let text = MessageRender.attributed(styled, ink: .black, link: .green, find: FindStyle(words: ["plan"], current: false))
        let colored = text.runs.filter { $0.backgroundColor != nil }.map { String(text[$0.range].characters) }.joined()
        XCTAssertEqual(colored, "planning", "a word split by styling is still one highlighted word")
    }
}
