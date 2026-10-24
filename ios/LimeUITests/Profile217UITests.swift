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
        XCTAssertTrue(app.descendants(matching: .any)["profile-hero-background"].waitForExistence(timeout: 10), "Sam is a contact: his background shows")
    }
}
