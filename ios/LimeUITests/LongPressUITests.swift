import XCTest

/// LIME-152d: a long-press keeps the pressed message on screen with the reactions above it and the actions below.
@MainActor
final class LongPressUITests: LimeUITestCase {
    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    func testALongPressShowsTheMessageTheReactionsAndTheActionsAllAtOnce() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat"]
        app.launch()
        app.buttons["conversation-row-dm:sam"].tap()
        let bubble = app.staticTexts["Are you coming to the staff meeting?"].firstMatch
        XCTAssertTrue(bubble.waitForExistence(timeout: 8))
        let original = bubble.frame
        bubble.press(forDuration: 0.8)
        let lifted = any(app, "lifted-bubble")
        let reactions = any(app, "reaction-row")
        let actions = any(app, "message-actions")
        XCTAssertTrue(reactions.waitForExistence(timeout: 5), "the reactions")
        XCTAssertTrue(actions.exists, "the actions")
        XCTAssertTrue(lifted.exists, "the lifted message")
        XCTAssertTrue(app.staticTexts.matching(identifier: "Are you coming to the staff meeting?").count >= 1, "its words are on screen")
        let screen = app.windows.firstMatch.frame
        for (name, frame) in [("reactions", reactions.frame), ("actions", actions.frame), ("message", lifted.frame)] {
            XCTAssertTrue(screen.contains(frame.insetBy(dx: 1, dy: 1)), "\(name) is fully on screen: \(frame)")
        }
        XCTAssertLessThanOrEqual(reactions.frame.maxY, lifted.frame.minY + 2, "the reactions sit above the message")
        XCTAssertGreaterThanOrEqual(actions.frame.minY, lifted.frame.maxY - 2, "the actions sit below it")
        XCTAssertEqual(lifted.frame.minY, original.minY - 10, accuracy: 60, "the message stays about where it was (\(original))")
        any(app, "react-👍").tap()
        XCTAssertTrue(reactions.waitForNonExistence(timeout: 5), "choosing closes it")
    }
}
