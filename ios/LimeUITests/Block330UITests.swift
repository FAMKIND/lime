import XCTest

/// LIME-330: block a person from a group message's menu; their messages collapse to one row, Show reveals them, Settings → Blocked → Unblock restores everything.
@MainActor
final class Block330UITests: LimeUITestCase {
    func testBlockingAGroupMemberCollapsesTheirMessagesShowRevealsAndUnblockRestores() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "group"]
        app.launch()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "field trip")).firstMatch.waitForExistence(timeout: 10), "Lee's message is there")

        // The long-press menu has "Block Lee Wong" (a group message from someone else); it asks first and does not block on Cancel.
        longPress(app, "field trip")
        XCTAssertEqual(app.buttons["action-block"].label, "Block Lee Wong")
        app.buttons["action-block"].tap()
        XCTAssertTrue(app.buttons["block-person-confirm"].firstMatch.waitForExistence(timeout: 5), "Block asks first")
        app.buttons["block-person-confirm"].firstMatch.tap()

        // Their message is one quiet row with no name and no words; Sam's stays.
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'blocked-row-'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8), "Lee's message collapsed")
        XCTAssertEqual(row.label, "Message from someone you blocked")
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "field trip")).firstMatch.exists, "nothing of what Lee said is on the screen")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "permission forms")).firstMatch.exists, "Sam's message stays")

        // Show reveals that one message.
        let show = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'blocked-show-'")).firstMatch
        XCTAssertTrue(show.exists)
        show.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "field trip")).firstMatch.waitForExistence(timeout: 5), "Show brings the message back for now")

        // Settings → Privacy → Blocked lists Lee; Unblock restores.
        goBack(app)
        openSettings(app)
        app.buttons["settings-privacy"].tap()
        app.buttons["privacy-blocked"].tap()
        let unblock = app.buttons["unblock-dm:lee"]
        XCTAssertTrue(unblock.waitForExistence(timeout: 5), "Lee is in the Blocked list though never a chat")
        unblock.tap()
        XCTAssertTrue(app.staticTexts["blocked-empty"].exists || app.buttons["unblock-dm:pat"].exists, "Lee is gone from the list")
    }
}
