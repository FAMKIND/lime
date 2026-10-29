import XCTest

/// LIME-231: a group with no picture of its own shows its members' circles in its details; the title is short (demo).
@MainActor
final class Fix231UITests: LimeUITestCase {
    func testGroupDetailsWithNoPictureShowsTheMembersCirclesAndOneBackButton() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "group-details-plain"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["group-details-avatar"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["group-details-members-avatar"].waitForExistence(timeout: 5), "the members' circles, not 👥")
        XCTAssertFalse(app.staticTexts["👥"].exists)
        // LIME-250: one ‹ and no title text in the bar (the page's own name is the title), so nothing squeezes to "…".
        XCTAssertEqual(app.buttons.matching(identifier: "back-button").count, 1, "exactly one back button")
        XCTAssertFalse(app.navigationBars.staticTexts["Details"].exists, "no title in the bar")
    }
}
