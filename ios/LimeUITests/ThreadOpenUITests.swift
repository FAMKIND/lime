import XCTest

/// LIME-173: the Replies screen opens showing its messages on the first frame, however long the first message is.
@MainActor
final class ThreadOpenUITests: XCTestCase {
    private func launch(_ screen: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", screen]
        app.launch()
        return app
    }

    /// A ~60-line message with no replies opens at its first line, five times over (the blank screen came and went).
    func testALongMessageWithNoRepliesOpensAtItsFirstLineEveryTime() {
        for attempt in 1...5 {
            let app = launch("thread-long")
            let first = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Line 01 of a very long message'")).firstMatch
            XCTAssertTrue(first.waitForExistence(timeout: 8), "attempt \(attempt): the message is on the screen")
            let screen = app.windows.firstMatch.frame
            XCTAssertGreaterThanOrEqual(first.frame.minY, 0, "attempt \(attempt): its top is not scrolled away: \(first.frame)")
            XCTAssertLessThan(first.frame.minY, screen.height / 2, "attempt \(attempt): its top is in the upper half, below the header: \(first.frame)")
            XCTAssertTrue(app.staticTexts["thread-count"].exists || app.descendants(matching: .any)["replies-title"].exists, "attempt \(attempt): the header is there")
            app.terminate()
        }
    }

    /// A thread with 30 replies opens at the newest one.
    func testAThreadWithManyRepliesOpensAtTheNewestReply() {
        let app = launch("thread-many")
        let newest = app.staticTexts["Reply number 30"]
        XCTAssertTrue(newest.waitForExistence(timeout: 8), "the newest reply is on the screen")
        let screen = app.windows.firstMatch.frame
        XCTAssertTrue(screen.contains(newest.frame), "and fully visible: \(newest.frame)")
        XCTAssertTrue(newest.isHittable)
        XCTAssertFalse(app.staticTexts["Reply number 01"].isHittable, "the oldest is far above")
    }
}
