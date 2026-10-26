import XCTest

/// LIME-113: delete your account (demo, with the stand-in backend), and a chat with a deleted account (demo).
@MainActor
final class Delete113UITests: LimeUITestCase {
    func testDeleteAccountExplainsThenAsksForDELETEPasswordAndCode() {
        let app = demoApp()
        app.launch()
        openSettings(app)
        app.buttons["settings-account"].tap()
        XCTAssertTrue(app.buttons["account-delete"].waitForExistence(timeout: 5), "Delete Account is on the Account screen")
        app.buttons["account-delete"].tap()
        XCTAssertTrue(app.staticTexts["delete-title"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'already have on their phones stays there'")).firstMatch.exists, "says what stays")
        app.buttons["delete-continue"].tap()
        let typed = app.textFields["delete-type"]
        XCTAssertTrue(typed.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["delete-send"].isEnabled)
        typeSecure("x", "delete-password", app)
        typed.tap(); typed.typeText("DELET")
        XCTAssertFalse(app.buttons["delete-send"].isEnabled, "it has to be DELETE exactly")
        typed.typeText("E")
        XCTAssertTrue(app.buttons["delete-send"].isEnabled)
        // A wrong password is refused before any code.
        app.buttons["delete-send"].tap()
        XCTAssertTrue(app.staticTexts["delete-error"].waitForExistence(timeout: 5))
        let password = app.secureTextFields["delete-password"]
        password.tap(); password.typeText(XCUIKeyboardKey.delete.rawValue); password.typeText("correct horse battery")
        app.buttons["delete-send"].tap()
        let code = app.textFields["delete-code"]
        XCTAssertTrue(code.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["delete-confirm"].isEnabled)
        for _ in 0..<3 where !code.value(forKey: "hasKeyboardFocus").map({ ($0 as? Bool) ?? false })! { code.tap(); usleep(500_000) }
        code.typeText("000000")
        app.buttons["delete-confirm"].tap()
        XCTAssertTrue(app.staticTexts["delete-error"].waitForExistence(timeout: 5), "a wrong code deletes nothing")
        code.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 6))
        code.typeText("123456")
        app.buttons["delete-confirm"].tap()
        XCTAssertTrue(app.buttons["welcome-continue"].waitForExistence(timeout: 15), "back at the welcome screen")
    }

    func testAChatWithADeletedPersonLooksLikeAnyOldChatAndSendingShowsOneQuietLine() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "chat-deleted-person"]
        app.launch()
        let field = app.textViews["composer-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "the composer stays")
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'deleted'")).firstMatch.exists, "nothing announces it")
        XCTAssertFalse(app.descendants(matching: .any)["chat-deleted-account"].exists)
        field.tap(); field.typeText("are you there?")
        app.buttons["send-button"].tap()
        XCTAssertTrue(app.staticTexts["You can\u{2019}t message this person."].waitForExistence(timeout: 5), "one quiet line")
        XCTAssertFalse(app.staticTexts["are you there?"].exists, "nothing was sent")
    }
}
