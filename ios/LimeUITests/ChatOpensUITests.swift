import XCTest

/// A chat must never open blank (LIME-134): the newest message is on screen the moment the chat opens, without a scroll, however
/// the chat is opened (again and again, with a message arriving right after, after the keyboard, on a long or short chat).
@MainActor
final class ChatOpensUITests: XCTestCase {
    private func app(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        let screen = extra.contains("-lime-demo-two-hundred") ? "chat-long-200" : "chat-long"
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
        let app = app(["-lime-demo-two-hundred"])
        assertNotBlank(app, newest: "Message 200", "first open")
        for round in 1...4 {
            closeChat(app)
            app.buttons["conversation-row-dm:long"].tap()
            assertNotBlank(app, newest: "Message 200", "open \(round)")
        }
    }
}
