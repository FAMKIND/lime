import XCTest

/// LIME-258: a band's Edit Cover: ‹ · Edit Cover · Done while editing; the sheet's colour changes the hero (demo).
@MainActor
final class Cover258UITests: LimeUITestCase {
    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    func testEditCoverOpensACoverAndColourSheetAndAColourChangesTheHero() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "jam-mine-profile"]
        app.launch()
        XCTAssertTrue(app.buttons["profile-tab-Orgs"].waitForExistence(timeout: 10))
        app.buttons["profile-tab-Orgs"].tap()
        any(app, "profile-org-demo-band-demo-my-jam").tap()
        XCTAssertTrue(app.buttons["jam-edit-page"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["org-edit-cover"].exists, "Edit Cover is for editing")
        app.buttons["jam-edit-page"].tap()
        XCTAssertTrue(app.buttons["org-edit-cover"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["org-edit-cover"].label, "Edit cover")
        XCTAssertTrue(app.buttons["org-done"].exists && app.buttons["org-edit-back"].exists, "‹ · Edit Cover · Done")
        XCTAssertTrue(any(app, "profile-hero-default").exists, "no cover: the ambient default")
        app.buttons["org-edit-cover"].tap()
        XCTAssertTrue(app.buttons["org-cover-choose"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["org-cover-remove"].exists, "nothing to remove")
        let blue = app.buttons["org-colour-4"]
        XCTAssertTrue(blue.exists)
        XCTAssertEqual(blue.label, "Blue")
        blue.tap()
        XCTAssertTrue(app.buttons["org-colour-default"].waitForExistence(timeout: 3), "a colour is chosen: the way back to the default appears")
        app.buttons["new-message-cancel"].tap()
        XCTAssertTrue(any(app, "org-tone-4").waitForExistence(timeout: 5), "the hero follows the colour")
    }
}
