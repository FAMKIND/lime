import XCTest

/// LIME-191: Report from a message, a jam post and a profile (demo), with Also block.
@MainActor
final class Report191UITests: LimeUITestCase {
    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    private func fillAndSend(_ app: XCUIApplication, reason: String = "spam") {
        let send = app.buttons["report-send"]
        XCTAssertTrue(send.waitForExistence(timeout: 8))
        XCTAssertFalse(send.isEnabled, "pick a reason first")
        XCTAssertTrue(app.buttons["report-reason-child_safety"].exists, "A child's safety is a reason")
        app.buttons["report-reason-\(reason)"].tap()
        XCTAssertTrue(send.isEnabled)
        XCTAssertTrue(any(app, "report-include").exists, "what will be sent is shown and can be left out")
        send.tap()
        XCTAssertTrue(any(app, "report-thanks").waitForExistence(timeout: 8))
        XCTAssertEqual(any(app, "report-thanks").label, "Thanks. lime\u{2019}s team will look at this.")
        app.buttons["report-done"].tap()
    }

    func testReportAMessage() {
        let app = demoApp()
        openSam(app)
        longPress(app, "staff meeting")
        XCTAssertTrue(app.buttons["action-report"].exists, "someone else's message has Report")
        app.buttons["action-report"].tap()
        XCTAssertTrue(any(app, "report-also-block").waitForExistence(timeout: 8), "a message from a contact offers Also block")
        fillAndSend(app)
    }

    func testMyOwnMessageHasNoReport() {
        let app = demoApp()
        openSam(app)
        longPress(app, "Yes, see you there")
        XCTAssertFalse(app.buttons["action-report"].exists)
    }

    func testReportAJamPostFromItsMenu() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "jam-following"]
        app.launch()
        let more = app.buttons["card-more-demo-post-2"]
        XCTAssertTrue(more.waitForExistence(timeout: 10)); more.tap()
        XCTAssertTrue(app.buttons["Report"].waitForExistence(timeout: 5))
        app.buttons["Report"].tap()
        fillAndSend(app, reason: "inappropriate")
    }

    func testReportAPersonFromTheirProfileWithAlsoBlock() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "jam-following"]
        app.launch()
        app.buttons["link"].tap()
        app.buttons["conversation-row-dm:lee"].tap()
        any(app, "chat-title").tap()
        let more = app.buttons["profile-more"]
        XCTAssertTrue(more.waitForExistence(timeout: 10)); more.tap()
        XCTAssertTrue(app.buttons["profile-report"].waitForExistence(timeout: 5))
        app.buttons["profile-report"].tap()
        let block = any(app, "report-also-block")
        XCTAssertTrue(block.waitForExistence(timeout: 8))
        block.switches.firstMatch.exists ? block.switches.firstMatch.tap() : block.tap()
        fillAndSend(app, reason: "harassment")
    }
}
