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
        XCTAssertEqual(ComposerSizing.maxFieldHeight(window: 375, keyboard: 200, bottomInset: 0, strip: true, line: line), minimum)
        XCTAssertEqual(ComposerSizing.expandedFieldHeight(window: 375, keyboard: 200, topInset: 0, bottomInset: 0, strip: true, line: line), minimum)
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
}
