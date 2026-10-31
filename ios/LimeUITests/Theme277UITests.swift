import XCTest

/// LIME-277a/277b (demo): the accent and background choices, and the profile's colour swatches.
@MainActor
final class Theme277UITests: LimeUITestCase {
    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    func testChoosingAnAccentAndABackgroundIsKeptAndShownOnTheRootScreen() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "settings/customize"]
        app.launch()
        XCTAssertTrue(app.buttons["theme-accent-3"].waitForExistence(timeout: 10), "eight accents")
        XCTAssertEqual(app.buttons["theme-accent-5"].label, "Lime")
        XCTAssertTrue(app.buttons["theme-accent-5"].isSelected, "lime is the default")
        app.buttons["theme-accent-3"].tap()
        XCTAssertTrue(app.buttons["theme-accent-3"].isSelected)
        XCTAssertFalse(app.buttons["theme-accent-5"].isSelected)
        app.swipeUp()
        XCTAssertTrue(app.buttons["theme-background-graph"].waitForExistence(timeout: 5), "eight backgrounds")
        XCTAssertTrue(app.buttons["theme-background-plain"].isSelected)
        app.buttons["theme-background-graph"].tap()
        XCTAssertTrue(app.buttons["theme-background-graph"].isSelected)
        XCTAssertTrue(any(app, "theme-bg-graph").exists, "this page is drawn on the graph paper")
        app.buttons["theme-reset"].tap()
        XCTAssertTrue(app.buttons["theme-background-plain"].isSelected)
        app.swipeDown()
        XCTAssertTrue(app.buttons["theme-accent-5"].isSelected)
    }

    func testARelaunchOnAChosenBackgroundShowsItOnTheMessagesScreen() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-theme-background", "chalkboard", "-lime-theme-accent", "1"]
        app.launch()
        XCTAssertTrue(any(app, "theme-bg-chalkboard").waitForExistence(timeout: 10))
    }

    func testTheProfilesBackgroundScreenOffersTheSameEightColours() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "settings/background"]
        app.launch()
        XCTAssertTrue(app.buttons["profile-colour-0"].waitForExistence(timeout: 10) || { app.swipeUp(); return app.buttons["profile-colour-0"].waitForExistence(timeout: 5) }())
        XCTAssertEqual(app.buttons["profile-colour-5"].label, "Lime")
        app.buttons["profile-colour-6"].tap()
        XCTAssertTrue(app.buttons["profile-colour-6"].isSelected)
        app.buttons["profile-colour-default"].tap()
        XCTAssertFalse(app.buttons["profile-colour-6"].isSelected)
    }
}
