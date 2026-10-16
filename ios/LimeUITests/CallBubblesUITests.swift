import XCTest

/// Calls as bubbles in the chat (LIME-123), in a made-up chat with Sam (`-lime-demo-screen call-bubbles`).
@MainActor
final class CallBubblesUITests: XCTestCase {
    private func app() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "call-bubbles"]
        app.launch()
        return app
    }

    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any)[id] }

    func testCallsShowAsBubblesOnTheCallersSideWithTheirWords() {
        let app = app()
        let mine = any(app, "call-bubble-call:d1"), theirs = any(app, "call-bubble-call:d2"), noAnswer = any(app, "call-bubble-call:d3")
        XCTAssertTrue(mine.waitForExistence(timeout: 10))
        XCTAssertTrue(theirs.exists && noAnswer.exists)
        let width = app.windows.firstMatch.frame.width
        XCTAssertGreaterThan(mine.frame.midX, width / 2, "a call I placed is on my side (right)")
        XCTAssertLessThan(theirs.frame.midX, width / 2, "their call is on their side (left)")
        XCTAssertGreaterThan(noAnswer.frame.midX, width / 2)
        XCTAssertEqual(app.buttons["call-bubble-call:d1"].label, "Video call, 0:23")
        XCTAssertEqual(app.buttons["call-bubble-call:d2"].label, "Missed voice call, Missed")
        XCTAssertEqual(app.buttons["call-bubble-call:d3"].label, "Voice call, No answer")
    }

    func testLongPressOffersOnlyTheEmojiBarReplyAndDelete() {
        let app = app()
        let bubble = any(app, "call-bubble-call:d1")
        XCTAssertTrue(bubble.waitForExistence(timeout: 10))
        bubble.press(forDuration: 0.8)
        // On a busy simulator (tests run in parallel) the first press can be swallowed while the screen is still settling: press once more.
        if !any(app, "reaction-row").waitForExistence(timeout: 3) { bubble.press(forDuration: 0.8) }
        XCTAssertTrue(any(app, "reaction-row").waitForExistence(timeout: 5), "the emoji bar")
        XCTAssertTrue(app.buttons["reply-in-thread"].exists, "Reply")
        XCTAssertTrue(app.buttons["action-delete"].exists, "Delete")
        for gone in ["action-forward", "action-edit", "action-copy", "action-select"] {
            XCTAssertFalse(app.buttons[gone].exists, "\(gone) is not offered for a call")
        }
    }

    func testTapAsksToCallBackWithTheHeadersTwoRowsAndIcons() {
        let app = app()
        let bubble = app.buttons["call-bubble-call:d1"]
        XCTAssertTrue(bubble.waitForExistence(timeout: 10))
        bubble.tap()
        let first = app.buttons["call-back-voice"].firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 5), "a confirmation, not an instant call")
        XCTAssertEqual(first.label, "Voice call", "the same order as the header's menu: voice, then video")
        XCTAssertEqual(app.buttons["call-back-video"].firstMatch.label, "Video call")
        app.buttons["Cancel"].firstMatch.tap()
        XCTAssertTrue(first.waitForNonExistence(timeout: 5))
    }

    func testReplyToACallQuotesIt() {
        let app = app()
        let bubble = any(app, "call-bubble-call:d1")
        XCTAssertTrue(bubble.waitForExistence(timeout: 10))
        bubble.press(forDuration: 0.8)
        app.buttons["reply-in-thread"].tap()
        // The reply screen shows the call as the message being answered.
        XCTAssertTrue(any(app, "call-bubble-call:d1").waitForExistence(timeout: 8))
    }
}
