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

    /// LIME-152h: someone's message in a group, near the bottom, is lifted with the whole stack kept on the screen: the message's text above the
    /// actions and fully visible. (That its last line is not clipped is checked in the screenshots: a clip does not change an element's frame.)
    func testAGroupMessageNearTheBottomIsLiftedOnScreenAboveTheActions() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "group"]
        app.launch()
        let text = "I can bring the permission forms"
        let bubble = app.staticTexts[text].firstMatch
        XCTAssertTrue(bubble.waitForExistence(timeout: 8))
        bubble.press(forDuration: 0.8)
        let actions = any(app, "message-actions")
        let reactions = any(app, "reaction-row")
        XCTAssertTrue(actions.waitForExistence(timeout: 5))
        let screen = app.windows.firstMatch.frame
        let copies = app.staticTexts.matching(NSPredicate(format: "label == %@", text)).allElementsBoundByIndex
        XCTAssertTrue(copies.contains { screen.contains($0.frame) && $0.frame.maxY <= actions.frame.minY && $0.frame.minY >= reactions.frame.maxY },
                      "a whole copy sits between the reactions and the actions: \(copies.map(\.frame))")
    }
}
