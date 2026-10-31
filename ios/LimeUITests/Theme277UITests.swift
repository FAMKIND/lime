import XCTest

/// LIME-277a/277b/277c (demo): the Appearance screen with its live preview and pickers, and the profile's colour swatches.
@MainActor
final class Theme277UITests: LimeUITestCase {
    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    private func appearance(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "settings/appearance"] + extra
        app.launch()
        return app
    }

    func testTheAppearanceScreenShowsAPreviewAndOneRowForEachChoiceWithItsValue() {
        let app = appearance()
        XCTAssertTrue(app.buttons["appearance-row-accent"].waitForExistence(timeout: 10))
        XCTAssertTrue(any(app, "appearance-preview-shown").exists, "the live preview")
        XCTAssertTrue(app.buttons["appearance-row-accent"].label.contains("Lime"))
        XCTAssertTrue(app.buttons["appearance-row-background"].label.contains("Plain"))
        XCTAssertTrue(app.buttons["appearance-row-mode"].label.contains("System"))
        XCTAssertTrue(app.buttons["appearance-row-font"].exists && app.buttons["appearance-row-size"].exists)
    }

    func testChoosingAnAccentAndABackgroundFollowsInTheRowsAndResetBringsLimeBack() {
        let app = appearance()
        app.buttons["appearance-row-accent"].tap()
        XCTAssertTrue(app.buttons["theme-accent-3"].waitForExistence(timeout: 5), "eight accents")
        XCTAssertEqual(app.buttons["theme-accent-5"].label, "Lime, lime's own")
        XCTAssertTrue(app.buttons["theme-accent-5"].isSelected, "lime is the default")
        app.buttons["theme-accent-3"].tap()
        XCTAssertTrue(app.buttons["theme-accent-3"].isSelected)
        XCTAssertFalse(app.buttons["theme-accent-5"].isSelected)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["appearance-row-accent"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["appearance-row-accent"].label.contains("Yellow"), "the row shows the choice")
        app.buttons["appearance-row-background"].tap()
        XCTAssertTrue(app.buttons["theme-background-graph"].waitForExistence(timeout: 5), "eight backgrounds")
        XCTAssertTrue(app.buttons["theme-background-plain"].isSelected)
        app.buttons["theme-background-graph"].tap()
        XCTAssertTrue(app.buttons["theme-background-graph"].isSelected)
        XCTAssertTrue(any(app, "theme-bg-graph").exists, "this page is drawn on the graph paper")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["appearance-row-background"].label.contains("Graph"))
        app.buttons["appearance-reset"].tap()
        XCTAssertTrue(app.buttons["appearance-row-background"].label.contains("Plain"))
        XCTAssertTrue(app.buttons["appearance-row-accent"].label.contains("Lime"))
    }

    func testTheFontAndTheSizeAreChosenFromTheSameScreenAndResetRestoresThem() {
        let app = appearance()
        app.buttons["appearance-row-font"].tap()
        XCTAssertTrue(app.buttons["font-lexend"].waitForExistence(timeout: 5), "the font list")
        app.buttons["font-lexend"].tap()
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["appearance-row-font"].label.contains("Lexend"))
        app.buttons["appearance-row-size"].tap()
        let follow = app.switches["text-size-follow"]
        XCTAssertTrue(follow.waitForExistence(timeout: 5))
        if follow.value as? String == "1" { follow.tap() }
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertFalse(app.buttons["appearance-row-size"].label.contains("iPhone"), "its own size now")
        app.buttons["appearance-reset"].tap()
        XCTAssertTrue(app.buttons["appearance-row-font"].label.contains("System"))
        XCTAssertTrue(app.buttons["appearance-row-size"].label.contains("iPhone"))
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
