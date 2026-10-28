import XCTest

/// LIME-210g: a community chat for a jam (demo).
@MainActor
final class Community210gUITests: LimeUITestCase {
    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    func testASubscriberJoinsFromTheJamPageAndIsToldWhenTheyWillBeAdded() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "jam-community"]
        app.launch()
        let join = app.buttons["community-join"]
        XCTAssertTrue(join.waitForExistence(timeout: 12), "Join <writer>'s community on a followed jam that has one")
        XCTAssertEqual(join.label, "Join Sam\u{2019}s community")
        join.tap()
        XCTAssertTrue(any(app, "community-asked").waitForExistence(timeout: 5))
        XCTAssertTrue(any(app, "community-asked").label.contains("You will be added when Sam\u{2019}s phone is next online"), any(app, "community-asked").label)
        XCTAssertFalse(join.exists)
    }

    func testTheWriterHasASwitchForTheCommunityInTheJamDetails() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "jam-mine-profile"]
        app.launch()
        XCTAssertTrue(app.buttons["profile-tab-Orgs"].waitForExistence(timeout: 12))
        app.buttons["profile-tab-Orgs"].tap()
        any(app, "profile-org-demo-my-jam").tap()
        XCTAssertTrue(app.buttons["jam-edit-page"].waitForExistence(timeout: 10))
        app.buttons["jam-edit-page"].tap()
        XCTAssertTrue(any(app, "jam-community-toggle").waitForExistence(timeout: 5), "the writer's switch")
        XCTAssertEqual(any(app, "jam-community-toggle").value as? String, "0")
    }
}
