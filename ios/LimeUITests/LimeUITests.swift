import XCTest
import UIKit

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

        // iOS 26+ has the system back button; below it, the custom glass one.
        let custom = app.buttons["back-button"]
        (custom.exists ? custom : app.navigationBars.buttons.element(boundBy: 0)).tap()
        XCTAssertTrue(list.waitForExistence(timeout: 5), "back to Messages")
    }

    func testEdgeSwipeGoesBack() {
        let app = XCUIApplication()
        app.launch()
        let list = app.scrollViews["messages-list"]
        XCTAssertTrue(list.waitForExistence(timeout: 10))
        app.buttons["conversation-row-c2"].tap()
        XCTAssertTrue(app.scrollViews["chat-scroll"].waitForExistence(timeout: 5))

        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.0, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: end)

        XCTAssertTrue(list.waitForExistence(timeout: 5), "swiping from the left edge returns to Messages")
        XCTAssertFalse(app.scrollViews["chat-scroll"].exists)
    }

    /// Short names show in full at any width (checked at 375pt on the iPhone 13 mini simulator, and
    /// everywhere else too): the rendered name is at least as wide as the untruncated text.
    func testChatTitleShowsFullName() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.scrollViews["messages-list"].waitForExistence(timeout: 10))
        for (row, name) in [("c2", "Autumn Reyes"), ("c1", "Journey Park"), ("c4", "Grade 4 Team")] {
            app.buttons["conversation-row-\(row)"].tap()
            let title = app.staticTexts["chat-title-name"]
            XCTAssertTrue(title.waitForExistence(timeout: 5), name)
            XCTAssertEqual(title.label, name)
            let style: UIFont.TextStyle
            if #available(iOS 26, *) { style = .caption1 } else { style = .subheadline }
            let font = UIFont.systemFont(ofSize: UIFont.preferredFont(forTextStyle: style).pointSize, weight: .semibold)
            let full = (name as NSString).size(withAttributes: [.font: font]).width
            XCTAssertGreaterThanOrEqual(title.frame.width, full * 0.97, "\(name) is truncated: \(title.frame.width) < \(full)")
            let custom = app.buttons["back-button"]
            (custom.exists ? custom : app.navigationBars.buttons.element(boundBy: 0)).tap()
            XCTAssertTrue(app.scrollViews["messages-list"].waitForExistence(timeout: 5))
        }
    }
}
