import XCTest

/// LIME-191: Settings → Moderation is for moderators only; the queue puts urgent first; a report opens and Dismiss asks first (demo).
@MainActor
final class Moderation191UITests: LimeUITestCase {
    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    private func openSettings(_ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat"] + extra
        app.launch()
        app.buttons["settings-button"].tap()
        openProfileSettings(app)
        XCTAssertTrue(any(app, "settings-root").waitForExistence(timeout: 10))
        return app
    }

    func testANormalAccountHasNoModerationRow() {
        let app = openSettings([])
        XCTAssertTrue(app.buttons["settings-about"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["settings-moderation"].exists)
    }

    func testAModeratorSeesTheQueueUrgentFirstAndDismissAsksFirst() {
        let app = openSettings(["-lime-demo-moderator"])
        let row = app.buttons["settings-moderation"]
        XCTAssertTrue(row.waitForExistence(timeout: 8)); row.tap()
        let urgent = app.buttons["moderation-row-demo-report-2"], spam = app.buttons["moderation-row-demo-report-1"]
        XCTAssertTrue(urgent.waitForExistence(timeout: 8))
        XCTAssertTrue(spam.exists)
        XCTAssertLessThan(urgent.frame.minY, spam.frame.minY, "a child's safety is on top")
        XCTAssertTrue(urgent.label.contains("URGENT"))
        spam.tap()
        XCTAssertTrue(any(app, "moderation-included").waitForExistence(timeout: 8), "the included item as sent")
        app.buttons["moderation-dismiss"].tap()
        XCTAssertTrue(app.buttons["moderation-confirm"].waitForExistence(timeout: 5), "Dismiss asks first")
        app.buttons["moderation-confirm"].tap()
        XCTAssertTrue(urgent.waitForExistence(timeout: 8))
        XCTAssertFalse(spam.exists, "the dismissed report left the queue")
    }
}
