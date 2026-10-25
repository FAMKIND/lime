import XCTest

/// LIME-217: a profile background image you choose who sees.
@MainActor
final class Profile217UITests: LimeUITestCase {
    private func app(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat"] + extra
        app.launch()
        return app
    }

    func testChoosingABackgroundShowsItOnYourProfileAndRemovingClearsIt() {
        let app = app(["-lime-demo-screen", "settings/background"])
        XCTAssertTrue(app.buttons["background-choose"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["background-vis-contacts"].isSelected, "contacts only by default")
        XCTAssertFalse(app.buttons["background-remove"].exists)
        app.buttons["background-choose"].tap()
        XCTAssertTrue(app.buttons["background-crop-save"].waitForExistence(timeout: 8), "move and scale")
        app.buttons["background-crop-save"].tap()
        XCTAssertTrue(app.buttons["background-remove"].waitForExistence(timeout: 8), "it is set")
        app.buttons["background-vis-everyone"].tap()
        XCTAssertTrue(app.buttons["background-vis-everyone"].isSelected)
        app.buttons["background-remove"].tap()
        XCTAssertTrue(app.buttons["background-remove"].waitForNonExistence(timeout: 8))
    }

    func testAContactsBackgroundShowsOnTheirProfile() {
        let app = app()
        app.buttons["conversation-row-dm:sam"].tap()
        app.descendants(matching: .any).matching(identifier: "chat-title").firstMatch.tap()
        let hero = app.descendants(matching: .any)["profile-hero-background"]
        XCTAssertTrue(hero.waitForExistence(timeout: 10), "Sam is a contact: his background shows")
        XCTAssertLessThan(hero.frame.minY, 1, "full bleed from the very top, under the status bar")
        XCTAssertGreaterThan(app.buttons["profile-tab-Info"].frame.minY, app.staticTexts["profile-name"].frame.maxY, "the tabs are below the name")
        XCTAssertLessThan(app.buttons["profile-tab-Info"].frame.midY, hero.frame.maxY, "and sit on the photo's fade")
        XCTAssertGreaterThanOrEqual(hero.frame.height, app.windows.firstMatch.frame.height * 0.58, "the photo is more than half the screen")
        XCTAssertTrue(app.staticTexts["profile-name"].exists)
    }

    func testAProfileWithNoBackgroundKeepsTheCleanLook() {
        // Lee has no background in the demo.
        let again = XCUIApplication()
        again.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat"]
        again.launch()
        again.buttons["conversation-row-dm:lee"].tap()
        again.descendants(matching: .any).matching(identifier: "chat-title").firstMatch.tap()
        XCTAssertTrue(again.staticTexts["profile-name"].waitForExistence(timeout: 10))
        XCTAssertFalse(again.descendants(matching: .any)["profile-hero-background"].exists, "no photo: today's canvas")
    }
}
