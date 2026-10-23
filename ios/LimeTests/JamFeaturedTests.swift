import XCTest
@testable import Lime

/// LIME-188c: what the featured row picks, and the reading time.
final class JamFeaturedTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    private func post(_ id: String, kind: String, daysAgo: Double, state: String = "ready") -> JamPostInfo {
        JamPostInfo(postId: id, jamId: "j", author: "a", tier: "free", kind: kind, title: id, subtitle: "", markdown: "", plain: "",
                    attachmentsJson: "[]", created: Int64((now.timeIntervalSince1970 - daysAgo * 86_400) * 1000), coauthors: [], displayAs: "person", state: state)
    }

    func testNewestFirstWithinSevenDaysAtMostTen() {
        let posts = (0..<12).map { post("p\($0)", kind: "article", daysAgo: Double($0) * 0.5) } + [post("old", kind: "article", daysAgo: 8)]
        let picked = JamFeatured.pick(posts, now: now) { _ in false }
        XCTAssertEqual(picked.count, 10)
        XCTAssertEqual(picked.first?.postId, "p0")
        XCTAssertEqual(picked.map(\.postId), (0..<10).map { "p\($0)" })
        XCTAssertFalse(picked.contains { $0.postId == "old" })
    }

    func testAQuickPostNeedsMediaAndAnUnfinishedOneIsLeftOut() {
        let posts = [post("text", kind: "quick", daysAgo: 1), post("photo", kind: "quick", daysAgo: 1), post("clip", kind: "record", daysAgo: 1), post("late", kind: "article", daysAgo: 1, state: "fetching")]
        let picked = JamFeatured.pick(posts, now: now) { $0.postId == "photo" }
        XCTAssertEqual(Set(picked.map(\.postId)), ["photo", "clip"])
    }

    func testEmptyWhenNothingIsRecent() {
        XCTAssertTrue(JamFeatured.pick([post("a", kind: "article", daysAgo: 9)], now: now) { _ in true }.isEmpty)
    }

    func testReadingTimeIsWordsOverTwoHundredAtLeastOne() {
        XCTAssertEqual(JamFeatured.minutes(words: 0), 1)
        XCTAssertEqual(JamFeatured.minutes(words: 200), 1)
        XCTAssertEqual(JamFeatured.minutes(words: 201), 2)
        XCTAssertEqual(JamFeatured.minutes(words: 1000), 5)
    }
}
