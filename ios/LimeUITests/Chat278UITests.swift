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

    func testAShortBubblesReactionCirclesSitOnItsBottomEdgeFromItsCorner() {
        let app = chat()
        let first = chip(app, "s2", "😂")
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        let bubble = app.descendants(matching: .any).matching(identifier: "own-bubble").element(boundBy: 0)
        XCTAssertTrue(bubble.exists)
        XCTAssertLessThan(first.frame.minY, bubble.frame.maxY, "a circle overlaps the bubble's bottom edge")
        XCTAssertGreaterThan(first.frame.maxY, bubble.frame.maxY, "and hangs below it")
        XCTAssertLessThan(abs(first.frame.midY - bubble.frame.maxY), 8, "about half of it on the bubble")
        XCTAssertLessThan(first.frame.minX, bubble.frame.midX + 20, "starting at my bubble's inner (leading) corner")
        XCTAssertTrue(first.label.contains("😂") && first.label.contains("1 person"), first.label)
    }

    /// LIME-278c: four reactions on a short bubble are four circles, each with its own count, all on the screen, flowing toward the middle.
    func testSeveralReactionsOnAShortBubbleAreOneCirclePerEmojiWithTheirOwnCountsAllOnScreen() {
        let app = chat()
        let window = app.windows.firstMatch.frame
        XCTAssertTrue(chip(app, "s2", "😂").waitForExistence(timeout: 10))
        let own = app.descendants(matching: .any).matching(identifier: "own-bubble").element(boundBy: 0)
        for emoji in ["😂", "👍", "❤️", "🎉"] {
            let c = chip(app, "s2", emoji)
            XCTAssertTrue(c.exists, emoji)
            XCTAssertGreaterThanOrEqual(c.frame.minX, 0, emoji)
            XCTAssertLessThanOrEqual(c.frame.maxX, window.maxX, "\(emoji) is on the screen")
        }
        XCTAssertTrue(chip(app, "s2", "❤️").label.contains("3 people"), "❤️ has its own count of 3")
        XCTAssertTrue(chip(app, "s2", "👍").label.contains("including you"), "mine says so")
        XCTAssertLessThan(chip(app, "s2", "🎉").frame.minX, chip(app, "s2", "😂").frame.minX, "later ones go toward the middle")
        XCTAssertLessThan(chip(app, "s2", "🎉").frame.minX, own.frame.minX, "past the bubble's corner, into the screen")
        // Someone else's short bubble: the circles flow toward the middle too, never past the right edge.
        let theirs = chip(app, "s1", "🙏")
        XCTAssertTrue(theirs.exists)
        XCTAssertLessThanOrEqual(theirs.frame.maxX, window.maxX)
        // Tapping one is the who-reacted card, with the people stacked under each reaction.
        chip(app, "s2", "❤️").tap()
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
