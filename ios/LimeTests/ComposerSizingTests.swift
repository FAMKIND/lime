import XCTest
@testable import Lime

/// LIME-176: how tall the composer's field may grow.
final class ComposerSizingTests: XCTestCase {
    private let line: CGFloat = 20

    func testWithTheKeyboardUpTheComposerAndKeyboardTakeAboutThreeQuartersOfTheWindow() {
        let cap = ComposerSizing.maxFieldHeight(window: 844, keyboard: 336, bottomInset: 34, strip: false, line: line)
        XCTAssertEqual(cap + ComposerSizing.chrome + 336, 844 * 0.75, accuracy: 1)
    }

    func testWithTheKeyboardHiddenTheFieldIsTallerThanWithIt() {
        let up = ComposerSizing.maxFieldHeight(window: 844, keyboard: 336, bottomInset: 34, strip: false, line: line)
        let down = ComposerSizing.maxFieldHeight(window: 844, keyboard: 0, bottomInset: 34, strip: false, line: line)
        XCTAssertGreaterThan(down, up)
        XCTAssertEqual(down + ComposerSizing.chrome + 34, 844 * 0.75, accuracy: 1)
    }

    func testTheStripTakesItsHeightOutOfTheField() {
        let plain = ComposerSizing.maxFieldHeight(window: 844, keyboard: 336, bottomInset: 34, strip: false, line: line)
        let strip = ComposerSizing.maxFieldHeight(window: 844, keyboard: 336, bottomInset: 34, strip: true, line: line)
        XCTAssertEqual(plain - strip, ComposerSizing.stripHeight, accuracy: 1)
    }

    func testNeverUnderFiveLinesOnAShortWindowOrInLandscape() {
        let minimum = ComposerSizing.minimumHeight(line: line)
        XCTAssertEqual(minimum, 116)
        // A tall-enough window keeps the five lines (an iPhone in portrait with a big keyboard).
        XCTAssertGreaterThanOrEqual(ComposerSizing.maxFieldHeight(window: 812, keyboard: 500, topInset: 47, bottomInset: 34, strip: false, line: line), minimum)
    }

    func testExpandedGoesFromJustBelowTheHeaderToTheKeyboard() {
        let height = ComposerSizing.expandedFieldHeight(window: 844, keyboard: 336, topInset: 47, bottomInset: 34, strip: false, line: line)
        XCTAssertEqual(height + ComposerSizing.chrome + 336 + 47 + ComposerSizing.headerHeight, 844, accuracy: 1)
        XCTAssertGreaterThan(height, ComposerSizing.maxFieldHeight(window: 844, keyboard: 336, bottomInset: 34, strip: false, line: line))
    }

    func testExpandedWithTheKeyboardHiddenStopsAtTheHomeIndicator() {
        let height = ComposerSizing.expandedFieldHeight(window: 844, keyboard: 0, topInset: 47, bottomInset: 34, strip: false, line: line)
        XCTAssertEqual(height + ComposerSizing.chrome + 34 + 47 + ComposerSizing.headerHeight, 844, accuracy: 1)
    }

    func testAnIPadWindowScalesWithItsHeight() {
        let tall = ComposerSizing.maxFieldHeight(window: 1194, keyboard: 0, bottomInset: 20, strip: false, line: line)
        let small = ComposerSizing.maxFieldHeight(window: 600, keyboard: 0, bottomInset: 20, strip: false, line: line)
        XCTAssertGreaterThan(tall, small)
    }

    // MARK: A short window (LIME-176b)

    private func assertFits(window: CGFloat, keyboard: CGFloat, top: CGFloat, bottom: CGFloat, _ note: String) {
        for strip in [false, true] {
            let below = keyboard > 0 ? keyboard : bottom
            let extra = ComposerSizing.chrome + (strip ? ComposerSizing.stripHeight : 0)
            let collapsed = ComposerSizing.maxFieldHeight(window: window, keyboard: keyboard, topInset: top, bottomInset: bottom, strip: strip, line: line)
            let expanded = ComposerSizing.expandedFieldHeight(window: window, keyboard: keyboard, topInset: top, bottomInset: bottom, strip: strip, line: line)
            for (what, height) in [("collapsed", collapsed), ("expanded", expanded)] {
                XCTAssertGreaterThanOrEqual(height, ComposerSizing.oneLineHeight(line: line), "\(note) \(what): one line always shows")
                // Whenever one line fits at all, the composer stays between the header and the keyboard.
                if window - top - ComposerSizing.headerHeight - below - extra >= ComposerSizing.oneLineHeight(line: line) {
                    XCTAssertLessThanOrEqual(height + extra + below, window - top - ComposerSizing.headerHeight + 1, "\(note) \(what) strip=\(strip): fits under the header and above the keyboard")
                }
            }
        }
    }

    func testALandscapePhoneWindowKeepsTheWholeComposerBetweenTheHeaderAndTheKeyboard() {
        assertFits(window: 375, keyboard: 200, top: 0, bottom: 21, "13 mini landscape, keyboard")
        assertFits(window: 375, keyboard: 0, top: 0, bottom: 21, "13 mini landscape, no keyboard")
    }

    func testAnIPadLandscapeWindowKeepsTheWholeComposerBetweenTheHeaderAndTheKeyboard() {
        assertFits(window: 834, keyboard: 420, top: 24, bottom: 20, "iPad landscape, keyboard")
        assertFits(window: 834, keyboard: 0, top: 24, bottom: 20, "iPad landscape, no keyboard")
    }

    func testPortraitNumbersFrom176AreUnchanged() {
        XCTAssertEqual(ComposerSizing.maxFieldHeight(window: 812, keyboard: 337, topInset: 47, bottomInset: 34, strip: false, line: line), 218)
        XCTAssertEqual(ComposerSizing.maxFieldHeight(window: 812, keyboard: 0, topInset: 47, bottomInset: 34, strip: false, line: line), 521)
        XCTAssertEqual(ComposerSizing.expandedFieldHeight(window: 812, keyboard: 337, topInset: 47, bottomInset: 34, strip: false, line: line), 318)
    }
}
