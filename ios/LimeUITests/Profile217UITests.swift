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
        XCTAssertLessThan(hero.frame.minY, app.windows.firstMatch.frame.minY + 1, "full bleed from the very top of the window, under the status bar")
        XCTAssertGreaterThan(app.buttons["profile-tab-Info"].frame.minY, app.staticTexts["profile-name"].frame.maxY, "the tabs are below the name")
        XCTAssertLessThan(app.buttons["profile-tab-Info"].frame.midY, hero.frame.maxY, "and sit on the photo's fade")
        XCTAssertGreaterThanOrEqual(hero.frame.height, app.windows.firstMatch.frame.height * 0.58, "the photo is more than half the screen")
        XCTAssertTrue(app.staticTexts["profile-name"].exists)
    }

    func testAProfileWithNoBackgroundShowsTheHeroWithADefault() {
        // Lee has no background and no photo in the demo: the hero is a soft tone colour.
        let app = app()
        app.buttons["conversation-row-dm:lee"].tap()
        app.descendants(matching: .any).matching(identifier: "chat-title").firstMatch.tap()
        XCTAssertTrue(app.staticTexts["profile-name"].waitForExistence(timeout: 10))
        let hero = app.descendants(matching: .any)["profile-hero-default"]
        XCTAssertTrue(hero.waitForExistence(timeout: 8), "the default hero is there")
        XCTAssertFalse(app.descendants(matching: .any)["profile-hero-background"].exists, "not a real background")
        XCTAssertLessThan(hero.frame.minY, app.windows.firstMatch.frame.minY + 1, "full bleed from the top of the window")
        XCTAssertGreaterThanOrEqual(hero.frame.height, app.windows.firstMatch.frame.height * 0.58)
        XCTAssertGreaterThan(app.buttons["profile-tab-Info"].frame.minY, app.staticTexts["profile-name"].frame.maxY, "the tabs are below the name")
        XCTAssertLessThan(app.buttons["profile-tab-Info"].frame.midY, hero.frame.maxY, "on the fade")
    }

    func testYourOwnProfileWithNoBackgroundShowsTheHeroToo() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat"]
        app.launch()
        app.buttons["settings-button"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["profile-hero-default"].waitForExistence(timeout: 10))
    }

    // MARK: LIME-217e: the photo is as wide as the window and always reaches below the text.

    private func assertHeroCoversTheText(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let hero = app.descendants(matching: .any)["profile-hero-background"].exists ? app.descendants(matching: .any)["profile-hero-background"] : app.descendants(matching: .any)["profile-hero-default"]
        XCTAssertTrue(hero.waitForExistence(timeout: 10), file: file, line: line)
        let window = app.windows.firstMatch.frame
        XCTAssertEqual(hero.frame.minX, window.minX, accuracy: 1, "starts at the window's left edge: hero \(hero.frame) in \(window)", file: file, line: line)
        XCTAssertEqual(hero.frame.width, window.width, accuracy: 1, "as wide as the window: \(hero.frame) in \(window)", file: file, line: line)
        let handle = app.staticTexts["profile-handle"]
        XCTAssertTrue(handle.waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertGreaterThan(hero.frame.maxY, handle.frame.maxY + 60, "the photo reaches well below the @handle: hero \(hero.frame), handle \(handle.frame)", file: file, line: line)
        XCTAssertGreaterThan(hero.frame.maxY, app.buttons["profile-tab-Info"].frame.midY, "and under the pills", file: file, line: line)
    }

    func testThePhotoSpansTheWindowAndReachesBelowTheTextInPortraitAndLandscape() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "profile-me"]
        app.launch()
        XCTAssertTrue(app.buttons["profile-edit"].waitForExistence(timeout: 10))
        assertHeroCoversTheText(app)
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(2)
        assertHeroCoversTheText(app)
        XCUIDevice.shared.orientation = .portrait
    }

    func testADefaultHeroAlsoSpansTheWindowInLandscape() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat"]
        app.launch()
        app.buttons["settings-button"].tap()
        XCTAssertTrue(app.buttons["profile-edit"].waitForExistence(timeout: 10))
        XCUIDevice.shared.orientation = .landscapeRight
        sleep(2)
        assertHeroCoversTheText(app)
        XCUIDevice.shared.orientation = .portrait
    }
}
