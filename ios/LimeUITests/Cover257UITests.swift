import XCTest

/// LIME-257: a group's Edit Cover (owner or admin): ‹ · Edit Cover · Done while editing; the sheet's colour changes the hero (demo).
@MainActor
final class Cover257UITests: LimeUITestCase {
    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    func testAnOwnerOpensEditCoverAndAColourChangesTheGroupsHero() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "group-details"]
        app.launch()
        XCTAssertTrue(app.buttons["group-edit"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["group-edit-cover"].exists, "Edit Cover is for editing")
        app.buttons["group-edit"].tap()
        XCTAssertTrue(app.buttons["group-edit-cover"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["group-edit-cover"].label, "Edit cover")
        XCTAssertTrue(app.buttons["group-done"].exists && app.buttons["group-edit-back"].exists, "‹ · Edit Cover · Done")
        XCTAssertTrue(any(app, "profile-hero-default").exists, "no cover: the ambient default")
        app.buttons["group-edit-cover"].tap()
        XCTAssertTrue(app.buttons["org-cover-choose"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["org-cover-remove"].exists, "nothing to remove")
        XCTAssertEqual(app.buttons["org-colour-6"].label, "Lavender")
        app.buttons["org-colour-6"].tap()
        XCTAssertTrue(app.buttons["org-colour-default"].waitForExistence(timeout: 3), "a colour is chosen")
        app.buttons["new-message-cancel"].tap()
        XCTAssertTrue(any(app, "group-tone-6").waitForExistence(timeout: 5), "the hero follows the colour")
    }
}
