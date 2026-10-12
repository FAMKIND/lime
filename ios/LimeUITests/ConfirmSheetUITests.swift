import XCTest

/// Confirmations are one bottom sheet (LIME-125), never a popover.
@MainActor
final class ConfirmSheetUITests: XCTestCase {
    private func app(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat"] + extra
        app.launch()
        return app
    }

    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any)[id] }

    /// The sheet's buttons sit in the lower part of the screen (a popover would be anchored near the row).
    private func assertAtTheBottom(_ app: XCUIApplication, _ button: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let height = app.windows.firstMatch.frame.height
        XCTAssertGreaterThan(button.frame.midY, height * 0.55, "\(button.label) is in a bottom sheet (y \(button.frame.midY) of \(height))", file: file, line: line)
    }

    func testSwipeDeleteOnAChatAsksInABottomSheetAndCancelKeepsIt() {
        let app = app()
        let row = app.buttons["conversation-row-dm:lee"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.swipeLeft()
        app.buttons["swipe-delete-dm:lee"].tap()
        let delete = app.buttons["delete-chat-confirm"].firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        XCTAssertTrue(any(app, "confirm-sheet").exists || delete.exists)
        assertAtTheBottom(app, delete)
        let cancel = app.buttons["Cancel"].firstMatch
        XCTAssertTrue(cancel.exists)
        assertAtTheBottom(app, cancel)
        cancel.tap()
        XCTAssertTrue(delete.waitForNonExistence(timeout: 5), "Cancel closes the sheet")
        XCTAssertTrue(row.exists, "and keeps the chat")
    }

    func testDeleteInTheSheetRemovesTheChat() {
        let app = app()
        let row = app.buttons["conversation-row-dm:lee"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.swipeLeft()
        app.buttons["swipe-delete-dm:lee"].tap()
        app.buttons["delete-chat-confirm"].firstMatch.tap()
        XCTAssertTrue(row.waitForNonExistence(timeout: 8), "Delete removes the chat from the list")
    }

    func testLeaveGroupAsksInTheSameSheet() {
        let app = app(["-lime-demo-screen", "groups-rows"])
        let member = app.buttons["conversation-row-grp:demo2"]
        XCTAssertTrue(member.waitForExistence(timeout: 10))
        member.swipeLeft()
        app.buttons["swipe-leave-grp:demo2"].tap()
        let confirm = app.buttons["group-action-confirm"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        assertAtTheBottom(app, confirm)
        XCTAssertTrue(app.buttons["Cancel"].firstMatch.exists)
        app.buttons["Cancel"].firstMatch.tap()
        XCTAssertTrue(confirm.waitForNonExistence(timeout: 5))
        XCTAssertTrue(member.exists, "Cancel keeps me in the group")
    }

    func testClearCallHistoryAsksInTheSameSheet() {
        let app = app(["-lime-demo-calls"])
        app.buttons["settings-button"].tap()
        XCTAssertTrue(app.buttons["profile-settings"].waitForExistence(timeout: 5))
        app.buttons["profile-settings"].tap()
        let privacy = app.buttons["settings-privacy"]
        XCTAssertTrue(privacy.waitForExistence(timeout: 8))
        privacy.tap()
        app.buttons["privacy-clear-calls"].tap()
        let confirm = app.buttons["privacy-clear-calls-confirm"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        assertAtTheBottom(app, confirm)
        XCTAssertTrue(app.buttons["Cancel"].firstMatch.exists)
    }

    func testMuteChoicesAreTheSameSheet() {
        let app = app()
        let row = app.buttons["conversation-row-dm:lee"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.swipeLeft()
        app.buttons["swipe-mute-dm:lee"].tap()
        let first = app.buttons["mute-1h"].firstMatch.exists ? app.buttons["mute-1h"].firstMatch : app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'mute-'")).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        assertAtTheBottom(app, first)
        XCTAssertTrue(app.buttons["Cancel"].firstMatch.exists)
    }
}
