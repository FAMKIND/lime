import XCTest

/// LIME-225: edit your profile in place, each field in its own sheet.
@MainActor
final class Profile225UITests: LimeUITestCase {
    private func ownProfile() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat"]
        app.launch()
        app.buttons["settings-button"].tap()
        XCTAssertTrue(app.buttons["profile-edit"].waitForExistence(timeout: 10))
        return app
    }

    func testPencilTurnsTheProfileIntoAnEditorWithCameraPencilsAndRows() {
        let app = ownProfile()
        XCTAssertFalse(app.buttons["profile-edit-photo"].exists, "not editing yet")
        app.buttons["profile-edit"].tap()
        XCTAssertTrue(app.buttons["profile-edit-photo"].waitForExistence(timeout: 8), "the camera badge on the avatar")
        XCTAssertEqual(app.buttons["profile-edit-photo"].label, "Change photo")
        for id in ["profile-edit-name", "profile-edit-username", "profile-edit-school"] { XCTAssertTrue(app.buttons[id].exists, id) }
        XCTAssertEqual(app.buttons["profile-edit-name"].label, "Edit name")
        XCTAssertTrue(app.buttons["profile-edit-background"].exists, "Change background on the hero")
        XCTAssertFalse(app.buttons["profile-tab-Info"].exists, "the tabs give way to the rows")
        for id in ["profile-name", "profile-about", "profile-username", "profile-school", "profile-links-row", "profile-background-row"] {
            XCTAssertTrue(app.buttons[id].exists, id)
        }
        XCTAssertTrue(app.switches["profile-hide-toggle"].exists || app.descendants(matching: .any)["profile-hide-toggle"].exists)
        XCTAssertFalse(app.buttons["profile-settings"].exists || app.buttons["profile-more"].exists, "Done replaces the header's buttons")
        app.buttons["profile-done"].tap()
        XCTAssertTrue(app.buttons["profile-tab-Info"].waitForExistence(timeout: 8), "Done returns to the tabs")
        XCTAssertFalse(app.buttons["profile-edit-photo"].exists)
        XCTAssertTrue(app.buttons["profile-edit"].exists)
    }

    func testChangingTheNameInItsSheetUpdatesTheHeroAtOnce() {
        let app = ownProfile()
        app.buttons["profile-edit"].tap()
        let pencil = app.buttons["profile-edit-name"]
        XCTAssertTrue(pencil.waitForExistence(timeout: 8))
        pencil.tap()
        let field = app.textFields["editor-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 8), "a sheet with the one field")
        app.buttons["editor-clear"].tap()
        field.typeText("Ms Teacher")
        app.buttons["editor-save"].tap()
        XCTAssertTrue(app.staticTexts["Ms Teacher"].waitForExistence(timeout: 8), "the hero shows the new name")
        XCTAssertTrue(app.buttons["profile-name"].label.contains("Ms Teacher"), "and the row")
    }

    func testTheSchoolRowOpensItsOwnSheet() {
        let app = ownProfile()
        app.buttons["profile-edit"].tap()
        app.buttons["profile-school"].tap()
        XCTAssertTrue(app.staticTexts["editor-title"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["editor-title"].label, "School")
        app.buttons["editor-close"].tap()
        XCTAssertTrue(app.buttons["profile-done"].waitForExistence(timeout: 8))
    }

    func testTheSettingsProfileCardOpensYourProfileForEditing() {
        let app = ownProfile()
        app.buttons["profile-settings"].tap()
        XCTAssertTrue(app.buttons["settings-profile"].waitForExistence(timeout: 8))
        app.buttons["settings-profile"].tap()
        XCTAssertTrue(app.buttons["profile-done"].waitForExistence(timeout: 10), "Settings closed and your profile is its editor")
    }

    // MARK: LIME-225b: the sheets from the editor show their whole screens (the Background one was blank once a background was set).

    /// Every id given is on screen and inside the window (nothing pushed off the side by an oversize child).
    private func assertPage(_ app: XCUIApplication, _ ids: [String], file: StaticString = #filePath, line: UInt = #line) {
        let window = app.windows.firstMatch.frame
        for id in ids {
            let element = app.descendants(matching: .any)[id]
            XCTAssertTrue(element.waitForExistence(timeout: 8), "\(id) is there", file: file, line: line)
            XCTAssertGreaterThanOrEqual(element.frame.minX, 0, "\(id) starts inside the screen", file: file, line: line)
            XCTAssertLessThanOrEqual(element.frame.maxX, window.width + 1, "\(id) ends inside the screen: \(element.frame)", file: file, line: line)
        }
    }

    private func editor(withBackground: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat"] + (withBackground ? ["-lime-demo-screen", "profile-me"] : [])
        app.launch()
        if !withBackground { app.buttons["settings-button"].tap() }
        XCTAssertTrue(app.buttons["profile-edit"].waitForExistence(timeout: 10))
        app.buttons["profile-edit"].tap()
        return app
    }

    func testChangeBackgroundShowsItsWholeScreenWithABackgroundSet() {
        let app = editor(withBackground: true)
        app.buttons["profile-edit-background"].tap()
        assertPage(app, ["background-preview", "background-choose", "background-remove", "background-vis-everyone", "background-vis-contacts"])
        XCTAssertEqual(app.buttons["background-choose"].label, "Change Background")
        XCTAssertEqual(app.buttons["background-choose"].frame.width, 343, accuracy: 2, "as wide as the page, not wider")
        XCTAssertTrue(app.buttons["edit-sheet-done"].exists, "Done stays")
    }

    func testChangeBackgroundShowsItsWholeScreenWithNone() {
        let app = editor(withBackground: false)
        app.buttons["profile-edit-background"].tap()
        assertPage(app, ["background-choose", "background-vis-everyone", "background-vis-contacts"])
        XCTAssertEqual(app.buttons["background-choose"].label, "Choose a Photo or Video")
    }

    func testChangePhotoAndLinksShowTheirWholeScreens() {
        let app = editor(withBackground: true)
        app.buttons["profile-edit-photo"].tap()
        assertPage(app, ["photo-library", "photo-vis-everyone", "photo-vis-contacts"])
        app.buttons["edit-sheet-done"].tap()
        XCTAssertTrue(app.buttons["profile-links-row"].waitForExistence(timeout: 8))
        app.buttons["profile-links-row"].tap()
        assertPage(app, ["links-add", "links-vis-everyone", "links-vis-contacts", "links-save"])
    }
}
