import XCTest

/// LIME-278 (demo, `-lime-demo-short-chat`): a reaction is a circle on its bubble, times show once per run, a drag left shows every time.
@MainActor
final class Chat278UITests: LimeUITestCase {
    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    private func chat(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-short-chat", "-lime-demo-screen", "chat"] + extra
        app.launch()
        return app
    }

    private func chip(_ app: XCUIApplication, _ message: String, _ emoji: String) -> XCUIElement { any(app, "reaction-chip-\(message)-\(emoji)") }

    func testTheFirstCircleSitsAtTheInnerCornerOnTheBubblesBottomEdge() {
        let app = chat()
        let first = chip(app, "s2", "😂")
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        let bubble = app.descendants(matching: .any).matching(identifier: "own-bubble").element(boundBy: 0)
        XCTAssertTrue(bubble.exists)
        XCTAssertLessThan(first.frame.minY, bubble.frame.maxY, "a circle overlaps the bubble's bottom edge")
        XCTAssertGreaterThan(first.frame.maxY, bubble.frame.maxY, "and hangs below it")
        XCTAssertLessThan(abs(first.frame.midY - bubble.frame.maxY), 8, "about half of it on the bubble")
        XCTAssertEqual(first.frame.minX, bubble.frame.minX - 2, accuracy: 3, "the first circle is at my bubble's inner (left) corner")
        XCTAssertTrue(first.label.contains("😂") && first.label.contains("1 person"), first.label)
    }

    /// LIME-278d: circles are added toward the sender's side, never past the bubble's inner edge, never off the screen; each has its own count.
    func testCirclesGrowTowardTheSendersSideFromTheInnerCornerAndNeverPastIt() {
        let app = chat()
        let window = app.windows.firstMatch.frame
        XCTAssertTrue(chip(app, "s2", "😂").waitForExistence(timeout: 10))
        let own = app.descendants(matching: .any).matching(identifier: "own-bubble").element(boundBy: 0)
        let ownCircles = ["😂", "👍", "❤️", "🎉"].map { chip(app, "s2", $0) }
        for c in ownCircles {
            XCTAssertTrue(c.exists, c.label)
            XCTAssertGreaterThanOrEqual(c.frame.minX, own.frame.minX - 5, "mine: nothing past the inner (left) edge into the middle")
            XCTAssertLessThanOrEqual(c.frame.maxX, window.maxX, "on the screen")
        }
        XCTAssertLessThan(ownCircles[0].frame.minX, ownCircles[1].frame.minX, "the second is toward my side (right) of the first")
        XCTAssertTrue(ownCircles[2].label.contains("3 people"), "❤️ has its own count of 3")
        XCTAssertTrue(ownCircles[1].label.contains("including you"), "mine says so")
        // Someone else's bubble: the first at its inner (right) corner, the rest toward their avatar (left); never past the inner edge.
        let theirBubble = app.descendants(matching: .any).matching(identifier: "other-bubble").element(boundBy: 0)
        let theirs = ["❤️", "👍", "😮", "🙏"].map { chip(app, "s1", $0) }
        XCTAssertTrue(theirs[0].exists)
        for c in theirs where c.exists {
            XCTAssertLessThanOrEqual(c.frame.maxX, theirBubble.frame.maxX + 5, "theirs: nothing past the inner (right) edge")
            XCTAssertGreaterThanOrEqual(c.frame.minX, 0)
        }
        if theirs[1].exists { XCTAssertGreaterThan(theirs[0].frame.minX, theirs[1].frame.minX - 1, "the second is toward their avatar (left)") }
        // Tapping one is the who-reacted card, with the people stacked under each reaction.
        ownCircles[2].tap()
        XCTAssertTrue(app.staticTexts["You"].waitForExistence(timeout: 5) || app.staticTexts["Sam Park"].waitForExistence(timeout: 5), "who reacted")
    }

    func testOnlyTheLastMessageOfARunShowsItsTime() {
        let app = chat()
        XCTAssertTrue(app.staticTexts["message-time-s2c"].waitForExistence(timeout: 10), "the last of my run shows its time")
        XCTAssertFalse(app.staticTexts["message-time-s2"].exists, "the first of the run does not")
        XCTAssertFalse(app.staticTexts["message-time-s2b"].exists, "nor the middle one")
        XCTAssertTrue(app.staticTexts["message-time-s1c"].exists, "Sam's run shows its time at its end")
        XCTAssertFalse(app.staticTexts["message-time-s1"].exists || app.staticTexts["message-time-s1b"].exists)
        XCTAssertTrue(app.staticTexts["delivery-sending"].exists, "a message with a status keeps its footer")
        // VoiceOver still has every time.
        XCTAssertTrue(any(app, "message-time-silent-s2").exists)
        XCTAssertTrue(any(app, "message-time-silent-s2b").exists)
    }

    func testDraggingTheChatLeftShowsEveryTimeAtTheTrailingEdge() {
        let app = chat(["-lime-demo-reveal-times"])
        let revealed = any(app, "message-time-revealed-s2b")
        XCTAssertTrue(revealed.waitForExistence(timeout: 10), "the hidden time of a middle message is there")
        let bubbles = app.descendants(matching: .any).matching(identifier: "own-bubble")
        XCTAssertGreaterThan(revealed.frame.minX, bubbles.element(boundBy: 1).frame.maxX, "at the trailing edge, beside the bubble")
    }
}
