import XCTest
@testable import Lime

/// LIME-173: how many replies a Replies screen lays out.
final class ThreadWindowTests: XCTestCase {
    func testASmallThreadShowsEverythingAndNoButton() {
        let replies = Array(1...30)
        XCTAssertEqual(Array(ThreadWindow.shown(replies, window: ThreadWindow.first)), replies)
        XCTAssertEqual(ThreadWindow.hidden(replies: 30, window: ThreadWindow.first), 0)
    }

    func testABigThreadShowsTheNewestTwoHundredAndGrowsByAPage() {
        let replies = Array(1...450)
        let shown = ThreadWindow.shown(replies, window: ThreadWindow.first)
        XCTAssertEqual(shown.count, 200)
        XCTAssertEqual(shown.last, 450, "the newest is always there")
        XCTAssertEqual(ThreadWindow.hidden(replies: 450, window: 200), 250)
        XCTAssertEqual(ThreadWindow.grown(window: 200, replies: 450), 300)
        XCTAssertEqual(ThreadWindow.grown(window: 400, replies: 450), 450, "never past the thread")
    }

    func testASearchHitInAnOlderReplyBringsTheWindowOutToIt() {
        XCTAssertEqual(ThreadWindow.covering(index: 400, replies: 450, window: 200), 200, "already inside the window")
        XCTAssertEqual(ThreadWindow.covering(index: 100, replies: 450, window: 200), 450 - 100 + 20, "out to the hit, with some context above")
        XCTAssertEqual(ThreadWindow.covering(index: 10, replies: 450, window: 200), 450, "never past the whole thread")
        XCTAssertEqual(ThreadWindow.covering(index: 999, replies: 450, window: 200), 200, "not a reply of this thread: unchanged")
    }
}
