import XCTest

/// LIME-143, LIME-160 (Debug builds): emergency mode in the demo: start it from the long-press on +, choose the group, send a status, see the card and the
/// panel in the group's chat, end it; Settings. The chat's ⋯ menu has nothing about emergencies.
@MainActor
final class EmergencyUITests: XCTestCase {
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "groups-rows"]
        app.launch()
        return app
    }

    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any)[id] }

    /// Long-press + → Emergency, then pick the group in the sheet ("Send to" → Change), as a phone with no emergency group chosen yet.
    private func startFromPlus(_ app: XCUIApplication, group: String = "grp:demo1") {
        let plus = app.buttons["new-message-button"]
        XCTAssertTrue(plus.waitForExistence(timeout: 10))
        plus.press(forDuration: 1.0)
        let item = app.buttons["Emergency"].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5), "the long-press menu has Emergency")
        item.tap()
        XCTAssertTrue(any(app, "emergency-call-first").waitForExistence(timeout: 5))
        any(app, "emergency-change").tap()
        let pick = any(app, "emergency-group-\(group)")
        XCTAssertTrue(pick.waitForExistence(timeout: 5), "the groups are offered in the sheet")
        pick.tap()
    }

    func testStartSendSeeTheCardAndThePanelThenEnd() {
        let app = launch()
        startFromPlus(app)
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
        // Back in Messages: the group's chat shows the card and the roll-up.
        let row = app.buttons["conversation-row-grp:demo1"]
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        row.tap()
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
        XCTAssertTrue(app.staticTexts["emergency-settings-honest"].exists || app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Not guaranteed'")).firstMatch.exists)
        XCTAssertFalse(app.buttons["emergency-settings-drill"].exists, "no drills")
        XCTAssertTrue(app.staticTexts["Safewords"].exists, "the toggle is called Safewords")
    }

    /// The "+" really long-pressed (not tapped) opens the menu with Emergency, and that opens the sheet.
    func testLongPressingThePlusOffersEmergencyAndOpensTheSheet() {
        let app = launch()
        let plus = app.buttons["new-message-button"]
        XCTAssertTrue(plus.waitForExistence(timeout: 10))
        plus.press(forDuration: 1.0)
        let item = app.buttons["Emergency"].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5), "the long-press menu has Emergency")
        XCTAssertFalse(app.textFields.firstMatch.exists, "a long-press did not also start a new message")
        item.tap()
        XCTAssertTrue(any(app, "emergency-call-first").waitForExistence(timeout: 5), "the Emergency sheet opens on Call first")
    }

    /// The label is one line on the card at the default text size.
    func testTheCardLabelIsOneLine() {
        let app = launch()
        startFromPlus(app)
        any(app, "emergency-send").tap()
        app.buttons["conversation-row-grp:demo1"].tap()
        let card = app.otherElements.matching(NSPredicate(format: "identifier BEGINSWITH 'emergency-card-'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 8))
        XCTAssertLessThan(card.frame.height, 130, "label row, status line and sender: no wrapped label")
    }

    /// LIME-160: no chat or group chat's ⋯ menu mentions emergencies (they are not for daily use).
    func testTheGroupChatsMenuHasNothingAboutEmergencies() {
        let app = launch()
        app.buttons["conversation-row-grp:demo1"].tap()
        XCTAssertTrue(app.buttons["chat-more"].waitForExistence(timeout: 8))
        app.buttons["chat-more"].tap()
        XCTAssertTrue(app.buttons["chat-group-details"].waitForExistence(timeout: 5), "the menu is open")
        XCTAssertFalse(app.buttons["chat-emergency"].exists)
        XCTAssertFalse(app.buttons["chat-make-emergency-group"].exists)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'emergency'")).firstMatch.exists)
    }
}
