import XCTest

/// LIME-272b (demo, a scripted other phone): the new phone's choice and flow, and the old phone's flow.
@MainActor
final class Move272UITests: LimeUITestCase {
    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    func testTheNewPhoneOffersTransferAndShowsTheCodeThenProgressThenOpens() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-demo-move-offer"]
        app.launch()
        XCTAssertTrue(app.buttons["move-transfer"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["move-start-fresh"].exists, "the other choice is always there")
        app.buttons["move-transfer"].tap()
        XCTAssertTrue(any(app, "move-qr").waitForExistence(timeout: 5), "the QR")
        XCTAssertTrue(any(app, "move-qr-fallback").exists, "and a code to use instead of scanning")
        XCTAssertTrue(any(app, "move-code").waitForExistence(timeout: 10), "the check code once the old phone answers")
        XCTAssertTrue(any(app, "move-code").label.contains("4 8 2 9 1 7"), "read digit by digit")
        app.buttons["move-match"].tap()
        XCTAssertTrue(any(app, "move-progress").waitForExistence(timeout: 5), "progress")
        XCTAssertTrue(any(app, "move-bytes").waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30), "lime opens when it is all there")
    }

    func testStartFreshSignsInTheOldWay() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-demo-move-offer"]
        app.launch()
        XCTAssertTrue(app.buttons["move-start-fresh"].waitForExistence(timeout: 10))
        app.buttons["move-start-fresh"].tap()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 15))
    }

    func testCancellingTheNewPhoneMoveGoesBackToTheChoice() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-demo-move-offer"]
        app.launch()
        app.buttons["move-transfer"].tap()
        XCTAssertTrue(any(app, "move-code").waitForExistence(timeout: 10))
        app.buttons["move-nomatch"].tap()
        XCTAssertTrue(app.buttons["move-transfer"].waitForExistence(timeout: 5), "back to the choice")
    }

    func testTheOldPhoneTakesACodeShowsTheCheckCodeSendsAndSaysItMoved() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "settings/account/move-old"]
        app.launch()
        XCTAssertTrue(app.buttons["move-old-scan"].waitForExistence(timeout: 10), "scan is offered")
        app.buttons["move-old-enter"].tap()
        let field = app.textFields["move-old-code-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "typing the code is the other way in")
        field.tap(); field.typeText("lime-move1:demo")
        app.buttons["move-old-continue"].tap()
        XCTAssertTrue(any(app, "move-code").waitForExistence(timeout: 10))
        app.buttons["move-match"].tap()
        XCTAssertTrue(any(app, "move-progress").waitForExistence(timeout: 10), "progress while it sends")
        XCTAssertTrue(any(app, "moved-notice").waitForExistence(timeout: 30), "lime moved to your new phone")
        app.buttons["moved-ok"].tap()
    }

    func testTheOldPhoneRefusesACodeThatIsNotALimeMoveCode() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "settings/account/move-old"]
        app.launch()
        app.buttons["move-old-enter"].tap()
        let field = app.textFields["move-old-code-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap(); field.typeText("hello")
        app.buttons["move-old-continue"].tap()
        XCTAssertTrue(any(app, "move-failed").waitForExistence(timeout: 5))
    }

    func testTheOldPhoneCanCancelWhileItSends() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "settings/account/move-old"]
        app.launch()
        app.buttons["move-old-enter"].tap()
        let field = app.textFields["move-old-code-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap(); field.typeText("lime-move1:demo")
        app.buttons["move-old-continue"].tap()
        XCTAssertTrue(any(app, "move-code").waitForExistence(timeout: 10))
        app.buttons["move-match"].tap()
        XCTAssertTrue(app.buttons["move-cancel"].waitForExistence(timeout: 10))
        app.buttons["move-cancel"].tap()
        XCTAssertTrue(app.buttons["move-old-scan"].waitForExistence(timeout: 5), "back at the start, nothing moved")
        XCTAssertFalse(any(app, "moved-notice").exists)
    }
}
