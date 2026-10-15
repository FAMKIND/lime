import XCTest

/// The call mini player (LIME-148c): a capsule above the tab bar (or the composer) for a minimised call, with Mute and Leave.
@MainActor
final class CallMiniPlayerUITests: XCTestCase {
    private func launch(_ args: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat"] + args
        app.launch()
        return app
    }

    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    func testAVoiceCallMinimisesToTheMiniPlayerWithMuteReturnAndLeave() {
        let app = launch(["-lime-demo-call", "voice"])
        XCTAssertTrue(app.buttons["call-minimize"].waitForExistence(timeout: 10))
        app.buttons["call-minimize"].tap()
        let player = any(app, "call-mini-player")
        XCTAssertTrue(player.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["call-return-bar"].exists, "the green bar is gone")
        let bar = app.buttons["call-mini-return"]
        XCTAssertTrue(bar.label.hasPrefix("Call with "), bar.label)
        XCTAssertTrue(bar.label.hasSuffix("Double-tap to return"), bar.label)

        let mute = app.buttons["call-mini-mute"]
        XCTAssertGreaterThanOrEqual(mute.frame.height, 44)
        XCTAssertEqual(mute.label, "Mute")
        mute.tap()
        XCTAssertEqual(app.buttons["call-mini-mute"].label, "Unmute")
        XCTAssertEqual(app.buttons["call-mini-mute"].value as? String, "Muted", "a value, not colour alone")

        bar.tap()
        XCTAssertTrue(app.buttons["call-end"].waitForExistence(timeout: 5), "back on the full call screen")
        XCTAssertFalse(any(app, "call-mini-player").exists, "never on the call screen")

        app.buttons["call-minimize"].tap()
        XCTAssertTrue(app.buttons["call-mini-leave"].waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(app.buttons["call-mini-leave"].frame.height, 44)
        app.buttons["call-mini-leave"].tap()
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: any(app, "call-mini-player"))
        waitForExpectations(timeout: 8)
        XCTAssertFalse(app.buttons["call-end"].exists, "left the call, no screen to return to")
    }

    func testTheMiniPlayerSitsAboveTheTabBarAndCoversNeitherItNorTheHeader() {
        let app = launch(["-lime-demo-call", "voice"])
        XCTAssertTrue(app.buttons["call-minimize"].waitForExistence(timeout: 10))
        app.buttons["call-minimize"].tap()
        let player = any(app, "call-mini-player")
        XCTAssertTrue(player.waitForExistence(timeout: 5))
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.exists)
        XCTAssertLessThanOrEqual(player.frame.maxY, tabBar.frame.minY + 1, "above the tab bar")
        XCTAssertGreaterThan(player.frame.minY, app.windows.firstMatch.frame.height / 2, "at the bottom, never at the top")
    }

    func testAGroupCallsMiniPlayerHasThePeopleCountAndMutes() {
        let app = launch(["-lime-demo-screen", "group-call-4"])
        XCTAssertTrue(app.buttons["Minimise call"].waitForExistence(timeout: 15))
        app.buttons["Minimise call"].tap()
        let bar = app.buttons["call-mini-return"]
        XCTAssertTrue(bar.waitForExistence(timeout: 5), "also inside the group's own chat")
        XCTAssertTrue(bar.label.contains("4 in call"), bar.label)
        app.buttons["call-mini-mute"].tap()
        XCTAssertEqual(app.buttons["call-mini-mute"].label, "Unmute")
        bar.tap()
        XCTAssertTrue(app.buttons["Layout: Grid"].waitForExistence(timeout: 5), "back on the full call screen")
    }
}
