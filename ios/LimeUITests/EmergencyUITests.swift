import XCTest

/// LIME-143 (Debug builds): emergency mode in the demo: start it from a group, send a status, see the card and the panel, end it; and Settings.
@MainActor
final class EmergencyUITests: XCTestCase {
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "groups-rows"]
        app.launch()
        return app
    }

    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any)[id] }

    func testStartSendSeeTheCardAndThePanelThenEnd() {
        let app = launch()
        let row = app.buttons["conversation-row-grp:demo1"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        XCTAssertTrue(app.buttons["chat-more"].waitForExistence(timeout: 8))
        app.buttons["chat-more"].tap()
        let start = app.buttons["chat-emergency"]
        XCTAssertTrue(start.waitForExistence(timeout: 5), "an Emergency item in the group's menu")
        start.tap()
        let call = any(app, "emergency-call-first")
        XCTAssertTrue(call.waitForExistence(timeout: 5), "the first thing is Call 911 first")
        XCTAssertTrue(call.label.hasPrefix("Call 911 first if you can") || call.label.contains("first if you can"), call.label)
        XCTAssertGreaterThanOrEqual(call.frame.height, 60, "big targets")
        XCTAssertGreaterThanOrEqual(any(app, "emergency-safe").frame.height, 60)
        XCTAssertGreaterThanOrEqual(any(app, "emergency-need-help").frame.height, 60)
        for _ in 0..<3 { any(app, "emergency-students-plus").tap() }
        XCTAssertEqual(any(app, "emergency-students").label, "3 students")
        let where_ = any(app, "emergency-where")
        where_.tap()
        where_.typeText("Room 204")
        any(app, "emergency-need-help").tap()
        any(app, "emergency-send").tap()
        XCTAssertTrue(any(app, "emergency-panel").waitForExistence(timeout: 8), "the roll-up appears")
        XCTAssertTrue(any(app, "emergency-card-").exists || app.otherElements.matching(NSPredicate(format: "identifier BEGINSWITH 'emergency-card-'")).firstMatch.waitForExistence(timeout: 5), "the card is in the chat")
        XCTAssertTrue(app.staticTexts["1 safe \u{00B7} 0 need help"].exists || app.staticTexts.matching(NSPredicate(format: "label CONTAINS '1 need help'")).firstMatch.exists, "the totals")
        any(app, "emergency-end").tap()
        app.buttons["emergency-end-confirm"].firstMatch.tap()
        XCTAssertTrue(any(app, "emergency-panel").waitForNonExistence(timeout: 8), "ending closes the panel")
    }

    func testSettingsHasTheEmergencyScreenWithTheSoundOffAndTheHonestNote() {
        let app = launch()
        XCTAssertTrue(app.buttons["settings-button"].waitForExistence(timeout: 10))
        app.buttons["settings-button"].tap()
        app.buttons["profile-settings"].tap()
        let row = app.buttons["settings-emergency"]
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        row.tap()
        let sound = app.switches["emergency-settings-sound"]
        XCTAssertTrue(sound.waitForExistence(timeout: 5))
        XCTAssertEqual(sound.value as? String, "0", "silent by default")
        XCTAssertEqual(app.switches["emergency-settings-school"].value as? String, "1", "the school actions are on by default")
        XCTAssertTrue(app.staticTexts["emergency-settings-honest"].exists || app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'not a promise of delivery'")).firstMatch.exists)
        XCTAssertTrue(app.buttons["emergency-settings-drill"].exists)
    }
}
