import XCTest

/// A chat must never open blank (LIME-134): the newest message is on screen the moment the chat opens, without a scroll, however
/// the chat is opened (again and again, with a message arriving right after, after the keyboard, on a long or short chat).
@MainActor
final class ChatOpensUITests: XCTestCase {
    private func app(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        let screen = extra.first { $0.hasPrefix("-lime-demo-long=") }.map { "chat-long-" + $0.dropFirst("-lime-demo-long=".count) } ?? "chat-long"
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", screen] + extra
        app.launch()
        return app
    }

    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any)[id] }

    private func message(_ app: XCUIApplication, containing text: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    /// The newest message is there and inside the scroll view, with no scrolling done.
    private func assertNotBlank(_ app: XCUIApplication, newest: String, _ note: String, file: StaticString = #filePath, line: UInt = #line) {
        let scroll = any(app, "chat-scroll")
        XCTAssertTrue(scroll.waitForExistence(timeout: 8), "\(note): the chat opened", file: file, line: line)
        let last = message(app, containing: newest)
        XCTAssertTrue(last.waitForExistence(timeout: 3), "\(note): the newest message is on screen (not blank)", file: file, line: line)
        XCTAssertTrue(last.isHittable, "\(note): and reachable without a scroll", file: file, line: line)
        XCTAssertTrue(scroll.frame.intersects(last.frame), "\(note): inside the scroll view: \(last.frame) vs \(scroll.frame)", file: file, line: line)
    }

    private func closeChat(_ app: XCUIApplication) {
        if app.buttons["back-button"].exists { app.buttons["back-button"].tap() } else { app.navigationBars.buttons.element(boundBy: 0).tap() }
        XCTAssertTrue(app.buttons["conversation-row-dm:long"].waitForExistence(timeout: 5))
    }

    func testALongChatOpensAtTheNewestMessageEveryTimeNotBlank() {
        let app = app()
        assertNotBlank(app, newest: "Message 60", "first open")
        for round in 1...6 {
            closeChat(app)
            app.buttons["conversation-row-dm:long"].tap()
            assertNotBlank(app, newest: "Message 60", "open \(round)")
        }
    }

    func testAMessageArrivingJustAfterTheChatOpensDoesNotLeaveItBlank() {
        let app = app(["-lime-demo-arrival"])
        assertNotBlank(app, newest: "Arrived while open", "first open with an arrival")
        for round in 1...4 {
            closeChat(app)
            app.buttons["conversation-row-dm:long"].tap()
            assertNotBlank(app, newest: "Arrived while open", "reopen \(round)")
        }
    }

    func testShortChatsAndTheKeyboardAreNotBlankEither() {
        let app = app()
        closeChat(app)
        app.buttons["conversation-row-dm:sam"].tap()
        assertNotBlank(app, newest: "Bringing the new schedule", "short chat")
        app.textViews["composer-field"].tap()   // the keyboard comes up
        sleep(1)
        assertNotBlank(app, newest: "Bringing the new schedule", "short chat with the keyboard")
        app.swipeDown()   // dismissed
        closeChat2(app)
        app.buttons["conversation-row-dm:long"].tap()
        assertNotBlank(app, newest: "Message 60", "long chat after the keyboard")
    }

    private func closeChat2(_ app: XCUIApplication) {
        if app.buttons["back-button"].exists { app.buttons["back-button"].tap() } else { app.navigationBars.buttons.element(boundBy: 0).tap() }
        XCTAssertTrue(app.buttons["conversation-row-dm:long"].waitForExistence(timeout: 5))
    }

    /// Jean's chat on the phone had 151 rows and fell just over the old limit of 150 for being laid out whole: it opened blank. A 200-message
    /// chat (over 150 rows) must open at its newest message every time too.
    func testAChatOfTwoHundredMessagesOpensAtTheNewestMessageEveryTimeNotBlank() {
        let app = app(["-lime-demo-long=200"])
        assertNotBlank(app, newest: "Message 200", "first open")
        for round in 1...4 {
            closeChat(app)
            app.buttons["conversation-row-dm:long"].tap()
            assertNotBlank(app, newest: "Message 200", "open \(round)")
        }
    }

    /// A very long chat (2,000 messages) opens at its newest message on the first frame, every time: only the newest rows are laid out.
    func testAChatOfTwoThousandMessagesOpensAtTheNewestMessageEveryTime() {
        let app = app(["-lime-demo-long=2000"])
        assertNotBlank(app, newest: "Message 2000", "first open")
        for round in 1...4 {
            closeChat(app)
            app.buttons["conversation-row-dm:long"].tap()
            assertNotBlank(app, newest: "Message 2000", "open \(round)")
        }
    }

    /// Scrolling to the top loads older pages, and what you are looking at does not jump; the oldest message is reachable.
    func testScrollingUpLoadsOlderPagesWithoutJumpingAndReachesTheFirstMessage() {
        let app = app(["-lime-demo-long=240"])
        assertNotBlank(app, newest: "Message 240", "first open")
        let scroll = any(app, "chat-scroll")
        var reached = false
        for _ in 0..<40 {
            scroll.swipeDown(velocity: .fast)
            if message(app, containing: "Message 1:").exists && message(app, containing: "Message 1:").isHittable { reached = true; break }
        }
        XCTAssertTrue(reached, "scrolling up through 240 messages reaches the first one (older pages load as you go)")
        // And back down to the newest.
        for _ in 0..<40 {
            scroll.swipeUp(velocity: .fast)
            if message(app, containing: "Message 240").isHittable { break }
        }
        XCTAssertTrue(message(app, containing: "Message 240").isHittable, "and back to the newest")
    }

    /// A short chat still works: no "Earlier messages" row, everything shown.
    func testAShortChatShowsEverythingWithNoEarlierRow() {
        let app = app(["-lime-demo-long=20"])
        assertNotBlank(app, newest: "Message 20", "short chat")
        XCTAssertFalse(any(app, "chat-earlier").exists, "nothing is hidden")
        XCTAssertTrue(message(app, containing: "Message 1:").waitForExistence(timeout: 3), "the first message is there")
    }

    /// LIME-234: back from a reply thread, the chat is where it was (not at the newest message).
    func testBackFromAThreadKeepsThePlaceInTheChat() {
        let app = app(["-lime-demo-long=200"])
        let scroll = any(app, "chat-scroll")
        XCTAssertTrue(scroll.waitForExistence(timeout: 8))
        let summary = any(app, "thread-summary-m100")
        var tries = 0
        while !(summary.exists && summary.isHittable) && tries < 40 { scroll.swipeDown(velocity: .fast); tries += 1 }
        XCTAssertTrue(summary.isHittable, "message 100 is on screen after scrolling up")
        let before = summary.frame.minY
        summary.tap()
        XCTAssertTrue(any(app, "thread-scroll").waitForExistence(timeout: 8), "the thread opened")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(scroll.waitForExistence(timeout: 8))
        sleep(2)   // the old open task would have scrolled to the newest by now
        XCTAssertTrue(summary.exists && summary.isHittable, "message 100 is still on screen")
        XCTAssertEqual(summary.frame.minY, before, accuracy: 12, "at the same place")
        XCTAssertFalse(message(app, containing: "Message 200").isHittable, "not at the newest message")
    }
}
