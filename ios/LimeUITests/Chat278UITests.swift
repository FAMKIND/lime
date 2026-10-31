import XCTest

/// LIME-278 (demo, `-lime-demo-short-chat`): a reaction is a pill on its bubble, times show once per run, a drag left shows every time.
@MainActor
final class Chat278UITests: LimeUITestCase {
    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    private func chat(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-short-chat", "-lime-demo-screen", "chat"] + extra
        app.launch()
        return app
    }

    func testAShortBubblesReactionSitsOnItsCornerWhateverItsWidth() {
        let app = chat()
        let cluster = any(app, "reaction-cluster-s2")
        XCTAssertTrue(cluster.waitForExistence(timeout: 10))
        let bubble = app.descendants(matching: .any).matching(identifier: "own-bubble").element(boundBy: 0)
        XCTAssertTrue(bubble.exists)
        XCTAssertLessThan(cluster.frame.minY, bubble.frame.maxY, "the pill overlaps the bubble's bottom edge")
        XCTAssertGreaterThan(cluster.frame.maxY, bubble.frame.maxY, "and hangs below it")
        XCTAssertLessThan(cluster.frame.minX, bubble.frame.midX, "on the inner corner of my bubble (the leading side)")
        XCTAssertLessThan(abs(cluster.frame.midY - bubble.frame.maxY), 8, "about half of it on the bubble")
        XCTAssertTrue(cluster.label.contains("😂"), cluster.label)
    }

    /// LIME-278b: four reactions on a short bubble fold into one pill that stays on the screen, growing toward the middle.
    func testSeveralReactionsOnAShortBubbleAreOnePillFullyOnTheScreen() {
        let app = chat()
        let window = app.windows.firstMatch.frame
        let mineCluster = any(app, "reaction-cluster-s2")
        XCTAssertTrue(mineCluster.waitForExistence(timeout: 10))
        let own = app.descendants(matching: .any).matching(identifier: "own-bubble").element(boundBy: 0)
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "reaction-cluster-s2").count, 1, "one pill, not four chips")
        XCTAssertGreaterThanOrEqual(mineCluster.frame.minX, 0)
        XCTAssertLessThanOrEqual(mineCluster.frame.maxX, window.maxX, "my pill is fully on the screen")
        XCTAssertLessThan(mineCluster.frame.minX, own.frame.minX + 20, "and grows toward the middle from the bubble's inner corner")
        XCTAssertTrue(mineCluster.label.contains("4 in total") && mineCluster.label.contains("including yours"), mineCluster.label)
        // Someone else's short bubble: the pill grows toward the middle too, never past the right edge.
        let theirs = any(app, "reaction-cluster-s1")
        XCTAssertTrue(theirs.exists)
        XCTAssertLessThanOrEqual(theirs.frame.maxX, window.maxX)
        XCTAssertTrue(theirs.label.contains("4 in total") && !theirs.label.contains("including yours"), theirs.label)
        // Tapping it is the who-reacted sheet.
        mineCluster.tap()
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
