import XCTest

/// LIME-194: a picture for a jam, from the org page's Edit. (The Photos picker itself is the system's; the demo starts with a picture already set.)
@MainActor
final class Jam194UITests: LimeUITestCase {
    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    private func editPage(_ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "jam-mine-profile"] + extra
        app.launch()
        XCTAssertTrue(app.buttons["profile-tab-Orgs"].waitForExistence(timeout: 10))
        app.buttons["profile-tab-Orgs"].tap()
        any(app, "profile-org-demo-my-jam").tap()
        XCTAssertTrue(app.buttons["jam-edit-page"].waitForExistence(timeout: 8))
        app.buttons["jam-edit-page"].tap()
        XCTAssertTrue(app.buttons["org-edit-picture"].waitForExistence(timeout: 8), "the camera circle")
        app.buttons["org-edit-picture"].tap()
        XCTAssertTrue(app.buttons["jam-picture-add"].waitForExistence(timeout: 8))
        return app
    }

    func testAJamWithNoPictureOffersAddAndNoRemove() {
        let app = editPage([])
        XCTAssertEqual(app.buttons["jam-picture-add"].label, "Add picture")
        XCTAssertFalse(app.buttons["jam-picture-remove"].exists)
        XCTAssertTrue(app.staticTexts["Your band's picture is public, like its name."].exists, "says it is public")
    }

    func testAJamWithAPictureOffersChangeAndRemoveAndRemoveBringsBackAdd() {
        let app = editPage(["-lime-demo-jam-picture"])
        XCTAssertEqual(app.buttons["jam-picture-add"].label, "Change picture")
        XCTAssertTrue(app.buttons["jam-picture-remove"].exists)
        app.buttons["jam-picture-remove"].tap()
        XCTAssertTrue(app.buttons["jam-picture-remove"].waitForNonExistence(timeout: 8), "removed")
        XCTAssertEqual(app.buttons["jam-picture-add"].label, "Add picture")
    }
}
