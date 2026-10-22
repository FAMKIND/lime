import XCTest
@testable import Lime

/// LIME-188t: what Posts, Articles and the filters let through.
final class JamFilterTests: XCTestCase {
    private func ok(_ kind: String, _ files: [String] = [], coauthored: Bool = false, articles: Bool = false, _ filter: JamFilter = JamFilter()) -> Bool {
        JamFilter.matches(kind: kind, files: files, coauthored: coauthored, articles: articles, filter: filter)
    }

    func testPostsAreEverythingThatIsNotAnArticle() {
        XCTAssertTrue(ok("quick"))
        XCTAssertTrue(ok("record", ["audio"]))
        XCTAssertFalse(ok("article"))
        XCTAssertTrue(ok("article", articles: true))
        XCTAssertFalse(ok("quick", articles: true))
    }

    func testMediaNarrowsPostsAndCoauthoredNarrowsBoth() {
        XCTAssertTrue(ok("record", ["audio"], JamFilter(media: .audio)))
        XCTAssertFalse(ok("record", ["video"], JamFilter(media: .audio)))
        XCTAssertTrue(ok("quick", ["image", "image"], JamFilter(media: .photos)))
        XCTAssertTrue(ok("record", ["video"], JamFilter(media: .video)))
        XCTAssertFalse(ok("quick", [], coauthored: false, JamFilter(coauthored: true)))
        XCTAssertTrue(ok("article", coauthored: true, articles: true, JamFilter(coauthored: true)))
        XCTAssertTrue(ok("article", articles: true, JamFilter(media: .audio)), "the media kinds are for Posts; an article ignores them")
        XCTAssertEqual(JamFilter(media: .audio, coauthored: true).activeCount, 2)
    }
}
