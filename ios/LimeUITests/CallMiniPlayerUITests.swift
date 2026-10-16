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
        XCTAssertTrue(app.buttons["Minimise"].waitForExistence(timeout: 15))
        app.buttons["Minimise"].tap()
        let bar = app.buttons["call-mini-return"]
        XCTAssertTrue(bar.waitForExistence(timeout: 5), "also inside the group's own chat")
        XCTAssertTrue(bar.label.contains("4 in call"), bar.label)
        app.buttons["call-mini-mute"].tap()
        XCTAssertEqual(app.buttons["call-mini-mute"].label, "Unmute")
        bar.tap()
        XCTAssertTrue(app.buttons["Minimise"].waitForExistence(timeout: 5), "back on the full call screen")
    }

    func testTheMiniPlayerIsShortHasNoLiveBadgeAndAWarmMuteCircle() {
        let app = launch(["-lime-demo-screen", "group-call-4"])
        XCTAssertTrue(app.buttons["Minimise"].waitForExistence(timeout: 15))
        app.buttons["Minimise"].tap()
        let bar = app.buttons["call-mini-return"]
        XCTAssertTrue(bar.waitForExistence(timeout: 5))
        XCTAssertFalse(any(app, "call-mini-live").exists, "no LIVE badge: the call's time is there instead")
        XCTAssertTrue(bar.label.contains("in call"), bar.label)
        XCTAssertEqual(app.buttons["call-mini-mute"].frame.height, 44, "a 44 pt tap area (a 36 pt circle inside)")
        XCTAssertLessThanOrEqual(bar.frame.height, 48, "about the header's 44 pt, not the old 60")
    }

    func testSwipingTheMiniPlayerOffAnEdgeTucksItIntoATabThatComesBackOnTap() {
        let app = launch(["-lime-demo-screen", "group-call-4"])
        XCTAssertTrue(app.buttons["Minimise"].waitForExistence(timeout: 15))
        app.buttons["Minimise"].tap()
        let bar = app.buttons["call-mini-return"]
        XCTAssertTrue(bar.waitForExistence(timeout: 5))
        // A real drag: from the right part of the capsule's name area to its left end.
        bar.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)).press(forDuration: 0.1, thenDragTo: bar.coordinate(withNormalizedOffset: CGVector(dx: 0.0, dy: 0.5)))
        let tab = app.buttons["call-mini-tab"]
        XCTAssertTrue(tab.waitForExistence(timeout: 5), "it folds into an edge tab")
        XCTAssertFalse(bar.exists)
        XCTAssertEqual(tab.label, "Call controls, hidden")
        XCTAssertGreaterThanOrEqual(tab.frame.height, 44)
        tab.tap()
        XCTAssertTrue(app.buttons["call-mini-return"].waitForExistence(timeout: 5), "the player is back")
        XCTAssertFalse(app.buttons["call-mini-tab"].exists)
    }
}
