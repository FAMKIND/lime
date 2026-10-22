import XCTest
@testable import Lime

/// LIME-188p: the reader's text size and line spacing sit on top of Dynamic Type and never go below 90% of the system's size.
final class ReaderPrefsTests: XCTestCase {
    func testTheSizeIsOneStepEitherWayFromTheBase() {
        XCTAssertEqual(ReaderPrefs.points(forStep: 0), 18)
        XCTAssertEqual(ReaderPrefs.points(forStep: -1), 16)
        XCTAssertEqual(ReaderPrefs.points(forStep: 1), 20)
        XCTAssertEqual(ReaderPrefs.points(forStep: -9), 16, "never more than one step")
        XCTAssertGreaterThanOrEqual(ReaderPrefs.points(forStep: -1), 17 * 0.9, "never below 90% of the system body size")
        XCTAssertEqual(ReaderPrefs.label(forSizeStep: -1), "2 pt smaller")
        XCTAssertEqual(ReaderPrefs.label(forSizeStep: 0), "Default")
    }

    func testLineSpacingGrowsWithTheStepAndTheSize() {
        let compact = ReaderPrefs.lineSpacing(size: 18, step: -1), normal = ReaderPrefs.lineSpacing(size: 18, step: 0), relaxed = ReaderPrefs.lineSpacing(size: 18, step: 1)
        XCTAssertLessThan(compact, normal)
        XCTAssertLessThan(normal, relaxed)
        XCTAssertGreaterThan(ReaderPrefs.lineSpacing(size: 24, step: 0), normal)
    }

    func testAnArticleSplitsIntoBlocksWithoutBreakingACodeFence() {
        let parts = ArticleSegments.split("One\n\nTwo\nlines\n\n```\ncode\n\nmore code\n```\n\nEnd")
        XCTAssertEqual(parts, ["One", "Two\nlines", "```\ncode\n\nmore code\n```", "End"])
        XCTAssertEqual(ArticleSegments.occurrences(of: "it", in: "Fold it, cut IT, with"), 3)
        XCTAssertEqual(ArticleSegments.occurrences(of: "cafe", in: "Caf\u{00E9}"), 1, "any case, any accents")
    }

    func testEveryFontIsOnOfferAndTheAccessibleOnesSayWhy() {
        XCTAssertEqual(ReaderFont.allCases.count, 8)
        XCTAssertFalse(ReaderFont.lexend.hint.isEmpty)
        XCTAssertFalse(ReaderFont.atkinson.hint.isEmpty)
        XCTAssertFalse(ReaderFont.comicNeue.hint.isEmpty)
    }
}
