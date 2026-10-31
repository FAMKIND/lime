import XCTest

/// LIME-277f (demo): a palette button left of Edit on your profile, a band you own and a group you run; not on someone else's profile.
@MainActor
final class Theme277fUITests: LimeUITestCase {
    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    func testYourOwnProfilesPaletteButtonOpensTheAppearancePickersLeftOfEdit() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "profile-me"]
        app.launch()
        XCTAssertTrue(app.buttons["profile-theme"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons["profile-theme"].label, "Customize appearance")
        XCTAssertLessThan(app.buttons["profile-theme"].frame.maxX, app.buttons["profile-edit"].frame.minX, "immediately left of Edit")
        XCTAssertGreaterThanOrEqual(app.buttons["profile-theme"].frame.height, 44)
        app.buttons["profile-theme"].tap()
        XCTAssertTrue(app.buttons["appearance-row-accent"].waitForExistence(timeout: 5), "the Appearance screen in a sheet")
        XCTAssertTrue(any(app, "appearance-preview").exists || any(app, "appearance-preview-shown").exists, "with its live preview")
        app.buttons["edit-sheet-done"].tap()
        XCTAssertTrue(app.buttons["profile-edit"].waitForExistence(timeout: 5))
    }

    func testSomeoneElsesProfileHasNoPaletteButton() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "profile-sam"]
        app.launch()
        XCTAssertTrue(app.buttons["profile-message"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["profile-theme"].exists)
    }

    func testABandYouOwnOpensItsCoverAndColourFromThePaletteButton() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "jam-mine-profile"]
        app.launch()
        XCTAssertTrue(app.buttons["profile-tab-Orgs"].waitForExistence(timeout: 10))
        app.buttons["profile-tab-Orgs"].tap()
        any(app, "profile-org-demo-band-demo-my-jam").tap()
        XCTAssertTrue(app.buttons["org-theme"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.buttons["org-theme"].label, "Cover and colour")
        XCTAssertLessThan(app.buttons["org-theme"].frame.maxX, app.buttons["jam-edit-page"].frame.minX)
        app.buttons["org-theme"].tap()
        XCTAssertTrue(app.buttons["org-colour-4"].waitForExistence(timeout: 5), "the cover and colour sheet, without entering Edit")
    }

    func testAGroupYouRunOpensItsCoverAndColourFromThePaletteButton() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "group-details"]
        app.launch()
        XCTAssertTrue(app.buttons["group-theme"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.buttons["group-theme"].label, "Cover and colour")
        XCTAssertLessThan(app.buttons["group-theme"].frame.maxX, app.buttons["group-edit"].frame.minX)
        app.buttons["group-theme"].tap()
        XCTAssertTrue(app.buttons["org-colour-6"].waitForExistence(timeout: 5))
    }
}
