import XCTest

/// LIME-175: a keyboard button in the composer row, tap the messages to hide the keyboard, voice messages use a waveform.
@MainActor
final class Composer175UITests: LimeUITestCase {
    private func openChat(_ screen: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat"] + (screen.map { ["-lime-demo-screen", $0] } ?? [])
        app.launch()
        if screen == nil { app.buttons["conversation-row-dm:sam"].tap() }
        return app
    }

    private func type(_ app: XCUIApplication, _ text: String) {
        let field = app.textViews["composer-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 8))
        field.tap()
        field.typeText(text)
    }

    func testTheKeyboardButtonHidesTheKeyboardKeepsTheDraftAndTheFieldBringsItBack() {
        let app = openChat()
        type(app, "half a message")
        let button = app.buttons["composer-hide-keyboard"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        XCTAssertTrue(button.isHittable)
        XCTAssertEqual(button.label, "Hide keyboard")
        XCTAssertGreaterThanOrEqual(button.frame.height, 40)
        button.tap()
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: app.keyboards.firstMatch)
        waitForExpectations(timeout: 5)
        XCTAssertEqual(app.textViews["composer-field"].value as? String, "half a message", "the draft stays")
        XCTAssertEqual(app.buttons["composer-hide-keyboard"].label, "Show keyboard")
        app.textViews["composer-field"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "tapping the field brings the keyboard back")
        XCTAssertEqual(app.buttons["composer-hide-keyboard"].label, "Hide keyboard")
    }

    func testTheKeyboardButtonShowsTheKeyboardAgain() {
        let app = openChat()
        type(app, "abc")
        app.buttons["composer-hide-keyboard"].tap()
        XCTAssertTrue(app.buttons["composer-hide-keyboard"].waitForExistence(timeout: 5))
        sleep(1)
        app.buttons["composer-hide-keyboard"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(app.textViews["composer-field"].value as? String, "abc")
    }

    func testTappingTheMessagesHidesTheKeyboard() {
        let app = openChat()
        type(app, "hello")
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        app.scrollViews.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)).tap()
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: app.keyboards.firstMatch)
        waitForExpectations(timeout: 5)
        XCTAssertEqual(app.textViews["composer-field"].value as? String, "hello")
    }

    func testTheVoiceButtonStillExistsAsTheMicId() {
        let app = openChat()
        XCTAssertTrue(app.descendants(matching: .any)["composer-mic"].waitForExistence(timeout: 8))
    }
}
