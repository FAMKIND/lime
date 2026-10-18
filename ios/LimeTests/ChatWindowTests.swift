import XCTest
@testable import Lime

/// LIME-164: the newest rows a chat shows, and how the window grows.
final class ChatWindowTests: XCTestCase {
    func testTheNewestRowsAreShownAndTheRestAreCounted() {
        let rows = Array(0..<500)
        XCTAssertEqual(Array(ChatWindow.shown(rows, window: 60)), Array(440..<500))
        XCTAssertEqual(ChatWindow.hidden(total: 500, window: 60), 440)
        XCTAssertEqual(Array(ChatWindow.shown(Array(0..<20), window: 60)), Array(0..<20), "a short chat shows all")
        XCTAssertEqual(ChatWindow.hidden(total: 20, window: 60), 0)
    }

    func testEachPageAddsSixtyAndStopsAtTheOldestRow() {
        XCTAssertEqual(ChatWindow.grown(window: 60, total: 500), 120)
        XCTAssertEqual(ChatWindow.grown(window: 480, total: 500), 500)
        XCTAssertEqual(ChatWindow.grown(window: 500, total: 500), 500)
    }

    func testAJumpToAnOldMessageWidensTheWindowToIncludeItWithContext() {
        // Row 10 of 2,000 (a search hit): the window has to reach back 1,990 rows plus context.
        XCTAssertEqual(ChatWindow.covering(index: 10, total: 2000, window: 60), 2000, "context would pass the oldest row: capped at the total")
        XCTAssertEqual(ChatWindow.covering(index: 1500, total: 2000, window: 60), 520)
        XCTAssertEqual(ChatWindow.covering(index: 1990, total: 2000, window: 60), 60, "already in the window: unchanged")
        XCTAssertEqual(ChatWindow.covering(index: 1990, total: 2000, window: 200), 200, "never smaller than it was")
        XCTAssertEqual(ChatWindow.covering(index: -1, total: 2000, window: 60), 60, "not found: unchanged")
    }
}
