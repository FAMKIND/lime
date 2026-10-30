import XCTest

/// LIME-245: the org page works like a profile: the word Edit, edit in place with a pencil on each row, a small sheet per field.
@MainActor
final class Org245UITests: LimeUITestCase {
    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    func testAnOwnerEditsAnOrgInPlaceNameInItsOwnSheetThenDone() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "jam-mine-profile"]
        app.launch()
        XCTAssertTrue(app.buttons["profile-tab-Orgs"].waitForExistence(timeout: 10))
        app.buttons["profile-tab-Orgs"].tap()
        any(app, "profile-org-demo-my-jam").tap()
        let edit = app.buttons["jam-edit-page"]
        XCTAssertTrue(edit.waitForExistence(timeout: 8))
        XCTAssertEqual(edit.label, "Edit band")
        XCTAssertTrue(app.buttons["profile-tab-Info"].exists, "the profile's tabs")
        edit.tap()
        XCTAssertTrue(app.buttons["org-edit-picture"].waitForExistence(timeout: 5), "the camera circle")
        XCTAssertFalse(app.buttons["profile-tab-Info"].exists, "the tabs give way to the rows")
        for id in ["org-edit-name", "org-edit-about", "org-edit-tags", "jam-community-toggle", "jam-end"] { XCTAssertTrue(any(app, id).exists, id) }
        XCTAssertEqual(app.buttons["org-edit-name"].label, "Edit name, Reading circles")
        app.buttons["org-edit-name"].tap()
        let field = app.textFields["jam-title-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.press(forDuration: 1.0)
        if app.menuItems["Select All"].waitForExistence(timeout: 2) { app.menuItems["Select All"].tap() }
        field.typeText("Reading rounds")
        app.buttons["org-field-save"].tap()
        XCTAssertTrue(app.staticTexts["profile-jam-row"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["org-edit-name"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["org-edit-name"].label, "Edit name, Reading rounds")
        app.buttons["org-done"].tap()
        XCTAssertTrue(app.buttons["profile-tab-Info"].waitForExistence(timeout: 5), "Done: the page again")
        XCTAssertEqual(app.staticTexts["profile-jam-row"].label, "Reading rounds")
    }

    func testClosingAnOrgAsksFirstAndTheRowsEditSheetCloses() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "jam-mine-profile"]
        app.launch()
        XCTAssertTrue(app.buttons["profile-tab-Orgs"].waitForExistence(timeout: 10))
        app.buttons["profile-tab-Orgs"].tap()
        any(app, "profile-org-demo-my-jam").tap()
        app.buttons["jam-edit-page"].tap()
        app.buttons["jam-end"].tap()
        XCTAssertTrue(app.buttons["jam-end-confirm"].firstMatch.waitForExistence(timeout: 5), "Close band asks first")
        XCTAssertEqual(app.buttons["jam-end-confirm"].firstMatch.label, "Close band")
        app.buttons["Cancel"].firstMatch.tap()
        XCTAssertTrue(app.buttons["org-done"].waitForExistence(timeout: 5), "cancelled: still editing")
    }
}
