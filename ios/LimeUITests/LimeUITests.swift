import XCTest

@MainActor
final class LimeUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testMessagesToChatAndBack() {
        let app = XCUIApplication()
        app.launch()

        let list = app.scrollViews["messages-list"]
        XCTAssertTrue(list.waitForExistence(timeout: 10), "launches into Messages")

        let row = app.buttons["conversation-row-c1"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()

        let chat = app.scrollViews["chat-scroll"]
        XCTAssertTrue(chat.waitForExistence(timeout: 5), "chat appears")

        let field = app.textFields["composer-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("hello")

        let send = app.buttons["send-button"]
        XCTAssertTrue(send.waitForExistence(timeout: 5))
        send.tap()

        let bubble = app.staticTexts.matching(identifier: "own-bubble").matching(NSPredicate(format: "label == %@", "hello")).firstMatch
        XCTAssertTrue(bubble.waitForExistence(timeout: 5), "a new own bubble with hello appears")

        app.buttons["back-button"].tap()
        XCTAssertTrue(list.waitForExistence(timeout: 5), "back to Messages")
    }
}
