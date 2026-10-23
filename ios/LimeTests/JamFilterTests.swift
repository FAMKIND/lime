import XCTest
@testable import Lime

/// LIME-188x: what the segments (All, Posts, Articles, Podcasts) and the filters let through.
final class JamFilterTests: XCTestCase {
    private func ok(_ kind: String, _ files: [String] = [], coauthored: Bool = false, asJam: Bool = false, subscribed: Bool = true, saved: Bool = false,
                    seg segment: JamSegment = .all, filter: JamFilter = JamFilter()) -> Bool {
        JamFilter.matches(kind: kind, files: files, coauthored: coauthored, asJam: asJam, subscribed: subscribed, saved: saved, segment: segment, filter: filter)
    }

    func testTheSegmentsSplitByKind() {
        for kind in ["quick", "article", "record"] { XCTAssertTrue(ok(kind), "All has \(kind)") }
        XCTAssertTrue(ok("quick", seg: .posts)); XCTAssertFalse(ok("article", seg: .posts)); XCTAssertFalse(ok("record", seg: .posts))
        XCTAssertTrue(ok("article", seg: .articles)); XCTAssertFalse(ok("quick", seg: .articles))
        XCTAssertTrue(ok("record", ["audio"], seg: .podcasts)); XCTAssertFalse(ok("quick", seg: .podcasts))
        XCTAssertEqual(JamSegment.allCases.map(\.title), ["All", "Posts", "Articles", "Podcasts"])
    }

    func testMediaNarrowsAndAnArticleIgnoresIt() {
        XCTAssertTrue(ok("record", ["audio"], seg: .all, filter: JamFilter(media: .audio)))
        XCTAssertFalse(ok("record", ["video"], seg: .all, filter: JamFilter(media: .audio)))
        XCTAssertTrue(ok("quick", ["image", "image"], seg: .all, filter: JamFilter(media: .photos)))
        XCTAssertTrue(ok("record", ["video"], seg: .podcasts, filter: JamFilter(media: .video)))
        XCTAssertTrue(ok("article", seg: .all, filter: JamFilter(media: .audio)))
    }

    func testCoauthoredSubscribedOrgsAndSaved() {
        XCTAssertFalse(ok("quick", coauthored: false, seg: .all, filter: JamFilter(coauthored: true)))
        XCTAssertTrue(ok("article", coauthored: true, seg: .all, filter: JamFilter(coauthored: true)))
        XCTAssertFalse(ok("quick", subscribed: false, seg: .all, filter: JamFilter(subscribed: true)), "my own jam is not a subscription")
        XCTAssertTrue(ok("quick", subscribed: true, seg: .all, filter: JamFilter(subscribed: true)))
        XCTAssertTrue(ok("quick", asJam: true, seg: .all, filter: JamFilter(orgs: true)))
        XCTAssertFalse(ok("quick", asJam: false, seg: .all, filter: JamFilter(orgs: true)))
        XCTAssertTrue(ok("article", saved: true, seg: .all, filter: JamFilter(saved: true)))
        XCTAssertFalse(ok("article", saved: false, seg: .all, filter: JamFilter(saved: true)))
        XCTAssertEqual(JamFilter(media: .audio, coauthored: true, subscribed: true, orgs: true, saved: true).activeCount, 5)
    }
}
