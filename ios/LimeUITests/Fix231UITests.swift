import XCTest

/// LIME-231: a group with no picture of its own shows its members' circles in its details; the title is short (demo).
@MainActor
final class Fix231UITests: LimeUITestCase {
    func testGroupDetailsWithNoPictureShowsTheMembersCirclesAndAShortTitle() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "group-details-plain"]
        app.launch()
        XCTAssertTrue(app.buttons["group-details-avatar"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["group-details-members-avatar"].waitForExistence(timeout: 5), "the members' circles, not 👥")
        XCTAssertFalse(app.staticTexts["👥"].exists)
        XCTAssertTrue(app.staticTexts["Details"].exists || app.navigationBars["Details"].exists, "the title is Details")
    }
}
