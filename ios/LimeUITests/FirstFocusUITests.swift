import XCTest

/// LIME-152a-fix: the composer's whole tool row is above the keyboard the first time it is tapped, and every time after.
@MainActor
final class FirstFocusUITests: LimeUITestCase {
    private func assertAbove(_ app: XCUIApplication, _ note: String) {
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5), "\(note): the keyboard is up")
        sleep(1)
        for id in ["composer-plus", "composer-emoji", "composer-aa"] {
            let button = app.buttons[id]
            XCTAssertTrue(button.waitForExistence(timeout: 5), "\(note): \(id) exists")
            XCTAssertTrue(button.isHittable, "\(note): \(id) is hittable")
            XCTAssertLessThanOrEqual(button.frame.maxY, keyboard.frame.minY + 1, "\(note): \(id) is above the keyboard (\(button.frame) vs \(keyboard.frame))")
        }
    }

    func testTheToolRowIsAboveTheKeyboardOnTheFirstFocusAfterAFreshLaunchAndAfter() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat"]
        app.launch()
        app.buttons["conversation-row-dm:sam"].tap()
        let field = app.textViews["composer-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 8))
        field.tap()
        assertAbove(app, "first focus")
        // Dismiss and focus again, and again in another chat.
        app.swipeDown()
        sleep(1)
        field.tap()
        assertAbove(app, "second focus")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["conversation-row-dm:lee"].tap()
        let other = app.textViews["composer-field"]
        XCTAssertTrue(other.waitForExistence(timeout: 8))
        other.tap()
        assertAbove(app, "first focus in another chat")
    }
}
