import XCTest

/// LIME-251: a group's page works like a profile and an org: glass tabs on the hero, Edit and ⋯ top right (Mute, Pin and the rest inside ⋯), edit in place.
@MainActor
final class GroupDetailsHeaderUITests: LimeUITestCase {
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "group-details"]
        app.launch()
        return app
    }

    func testTheGroupPageHasTabsEditAndAMenuWithMuteAndLeave() {
        let app = launch()
        XCTAssertTrue(app.buttons["group-edit"].waitForExistence(timeout: 8), "an owner sees Edit")
        for tab in ["Members", "Media", "Files", "Links"] { XCTAssertTrue(app.buttons["profile-tab-\(tab)"].exists, tab) }
        XCTAssertFalse(app.buttons["group-mute"].exists, "the bell and pin circles moved into ⋯")
        // Members: roles.
        XCTAssertEqual(app.buttons["group-member-open-me"].label, "You, owner")
        XCTAssertTrue(app.buttons["group-add"].exists, "an admin adds from the top of Members")
        // ⋯: Mute (asks how long), Pin, Leave group.
        app.buttons["group-more"].tap()
        XCTAssertTrue(app.buttons["group-mute"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["group-more-leave"].exists)
        app.buttons["group-mute"].tap()
        XCTAssertTrue(app.buttons["mute-hour"].waitForExistence(timeout: 5))
        app.buttons["mute-hour"].tap()
        app.buttons["group-more"].tap()
        XCTAssertEqual(app.buttons["group-mute"].label, "Unmute")
        XCTAssertEqual(app.buttons["group-pin"].label, "Pin")
        app.buttons["group-pin"].tap()
        app.buttons["group-more"].tap()
        XCTAssertEqual(app.buttons["group-pin"].label, "Unpin")
    }

    func testAnAdminEditsInPlaceTheNameInItsSheetThenDone() {
        let app = launch()
        app.buttons["group-edit"].tap()
        XCTAssertTrue(app.buttons["group-edit-picture"].waitForExistence(timeout: 5), "the camera circle")
        XCTAssertFalse(app.buttons["profile-tab-Members"].exists, "the tabs give way to the rows")
        XCTAssertTrue(app.buttons["group-edit-name"].exists && app.buttons["group-leave"].exists)
        app.buttons["group-edit-name"].tap()
        let field = app.textFields["group-rename-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        if let current = field.value as? String, !current.isEmpty { field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count)) }
        field.typeText("Grade 4 Crew")
        app.buttons["group-rename-save"].tap()
        XCTAssertTrue(app.buttons["group-edit-name"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["group-edit-name"].label, "Edit name, Grade 4 Crew")
        app.buttons["group-done"].tap()
        XCTAssertTrue(app.buttons["profile-tab-Members"].waitForExistence(timeout: 5), "Done: the page again")
        XCTAssertEqual(app.staticTexts["group-details-name"].label, "Grade 4 Crew", "the hero shows it")
    }
}
