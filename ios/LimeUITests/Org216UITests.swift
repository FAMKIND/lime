import XCTest

/// LIME-216: orgs: rows with swipe actions, and the org's own profile (pushed).
@MainActor
final class Org216UITests: LimeUITestCase {
    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    private func myOrgsTab() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "jam-mine-asjam"]
        app.launch()
        app.buttons["settings-button"].tap()
        XCTAssertTrue(app.buttons["profile-tab-Orgs"].waitForExistence(timeout: 10))
        app.buttons["profile-tab-Orgs"].tap()
        return app
    }

    func testAnOwnersOrgRowSwipesLeftForEditSubscribersAndEndJamAndRightForShare() {
        let app = myOrgsTab()
        let row = any(app, "profile-org-demo-my-jam")
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        XCTAssertTrue(row.label.contains("Reading circles"), row.label)
        row.swipeLeft()
        XCTAssertTrue(app.buttons["org-swipe-edit-demo-my-jam"].waitForExistence(timeout: 5), "Edit")
        XCTAssertTrue(app.buttons["org-swipe-subscribers-demo-my-jam"].exists, "Subscribers")
        XCTAssertTrue(app.buttons["org-swipe-end-demo-my-jam"].exists, "End jam (red)")
        // End jam asks first.
        app.buttons["org-swipe-end-demo-my-jam"].tap()
        XCTAssertTrue(app.buttons["jam-end-confirm"].firstMatch.waitForExistence(timeout: 5), "End jam asks before it ends")
        app.buttons["Cancel"].firstMatch.tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5), "cancelled: the org stays")
    }

    func testTheOrgPageIsAPushedProfileWithItsHeaderTabsAndItsPosts() {
        let app = myOrgsTab()
        any(app, "profile-org-demo-my-jam").tap()
        XCTAssertTrue(app.staticTexts["profile-jam-row"].waitForExistence(timeout: 8), "the org's name")
        XCTAssertEqual(app.staticTexts["profile-jam-row"].label, "Reading circles")
        XCTAssertTrue(app.buttons["jam-edit-page"].exists, "✎ Edit for the owner")
        XCTAssertTrue(app.buttons["profile-org-more"].exists, "⋯")
        for tab in ["All", "Posts", "Articles", "Podcasts", "Info"] { XCTAssertTrue(app.buttons["org-tab-\(tab)"].exists, tab) }
        XCTAssertTrue(app.staticTexts["org-authors"].exists, "the authors under the name")
        XCTAssertTrue(app.descendants(matching: .any)["profile-hero-default"].exists, "the profile's hero, with the org's colour as its default")
        XCTAssertFalse(app.navigationBars.buttons["Done"].exists, "pushed, not a sheet")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Welcome from the circle'")).firstMatch.waitForExistence(timeout: 8) || app.staticTexts["Welcome from the circle"].exists, "a post made as the org shows under All")
        // The ⋯ has Subscribers and End jam.
        app.buttons["profile-org-more"].tap()
        XCTAssertTrue(app.buttons["jam-subscribers"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["jam-end"].exists)
    }

    func testAnOrgWithNoPostsShowsTheWayToPostAsIt() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "jam-mine-profile"]
        app.launch()
        XCTAssertTrue(app.buttons["profile-tab-Orgs"].waitForExistence(timeout: 10))
        app.buttons["profile-tab-Orgs"].tap()
        any(app, "profile-org-demo-my-jam").tap()
        XCTAssertTrue(any(app, "org-empty").waitForExistence(timeout: 8))
        XCTAssertTrue(any(app, "org-empty").label.contains("in Post as"), any(app, "org-empty").label)
    }

    func testSomeoneElsesOrgHasASubscribePillUnderTheNameAndTheInfoTab() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat"]
        app.launch()
        app.buttons["conversation-row-dm:sam"].tap()
        any(app, "chat-title").tap()
        app.buttons["profile-tab-Orgs"].waitForExistence(timeout: 10)
        app.buttons["profile-tab-Orgs"].tap()
        any(app, "profile-org-demo-sam-jam").tap()
        let subscribe = app.buttons["profile-org-page-subscribe"]
        XCTAssertTrue(subscribe.waitForExistence(timeout: 8), "Subscribe is a pill under the name")
        XCTAssertGreaterThan(subscribe.frame.minY, app.staticTexts["profile-jam-row"].frame.maxY, "under the name, not in the header")
        XCTAssertFalse(app.buttons["jam-edit-page"].exists, "no Edit for a visitor")
        app.buttons["org-tab-Info"].tap()
        XCTAssertTrue(app.staticTexts["Short lessons for grades 3 to 5"].waitForExistence(timeout: 5), "Info: what it is about")
        XCTAssertTrue(any(app, "org-author-sam").exists, "and its authors")
    }
}
