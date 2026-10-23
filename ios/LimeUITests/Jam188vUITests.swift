import XCTest

/// LIME-188v: jam's header like link's; Posts | Articles | Saved; jams and groups as a filter and a profile tab.
@MainActor
final class Jam188vUITests: LimeUITestCase {
    private func launch(_ screen: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", screen]
        app.launch()
        return app
    }

    /// The menu's "Saved" (a saved article's bookmark has the same name).
    private func savedFilter(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == 'Saved' AND NOT identifier BEGINSWITH 'jam-article-save'")).firstMatch
    }

    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    func testTheFeedIsOneScrollViewFromTheTopOfTheScreenSoItScrollsUnderTheHeader() {
        let app = launch("jam-following")
        let feed = app.scrollViews["jam-feed"]
        XCTAssertTrue(feed.waitForExistence(timeout: 10))
        XCTAssertLessThan(feed.frame.minY, 5, "the scroll view starts at the top edge: the header floats over it, with nothing behind its icons")
        XCTAssertTrue(app.buttons["jam-search-button"].exists && app.buttons["settings-button"].exists)
        XCTAssertTrue(app.segmentedControls["jam-filter-segments"].exists, "the filter row is inside it")
    }

    func testSavedIsAFilterAndListsASavedPostOrSaysNothingYet() {
        let app = launch("jam-following")
        let control = app.segmentedControls["jam-filter-segments"]
        XCTAssertTrue(control.waitForExistence(timeout: 10))
        XCTAssertFalse(control.buttons["Saved"].exists, "Saved is in the filter menu now")
        XCTAssertFalse(app.buttons["jam-saved-row"].exists, "the Saved (n) row is gone")
        app.buttons["jam-filter-button"].tap()
        savedFilter(app).tap()
        XCTAssertTrue(any(app, "jam-saved-empty").waitForExistence(timeout: 5))
        XCTAssertEqual(any(app, "jam-saved-empty").label, "Nothing saved yet.")
        app.buttons["jam-filter-button"].tap()
        app.buttons["Clear filters"].tap()
        control.buttons["Articles"].tap()
        let save = app.buttons["jam-article-save-demo-post-1"]
        XCTAssertTrue(save.waitForExistence(timeout: 8))
        for _ in 0..<4 where !save.isHittable || save.frame.maxY > app.windows.firstMatch.frame.height - 150 { app.swipeUp() }
        save.tap()
        control.buttons["All"].tap()
        app.buttons["jam-filter-button"].tap()
        savedFilter(app).tap()
        XCTAssertTrue(app.buttons["jam-post-demo-post-1"].waitForExistence(timeout: 5), "the saved article")
        XCTAssertFalse(any(app, "jam-saved-empty").exists)
        // Put it back so the next run starts clean.
        for _ in 0..<4 where !app.buttons["jam-article-save-demo-post-1"].isHittable { app.swipeDown() }
        app.buttons["jam-article-save-demo-post-1"].tap()
        XCTAssertTrue(any(app, "jam-saved-empty").waitForExistence(timeout: 5))
    }

    func testTheOrgsFilterShowsOnlyPostsShownAsTheJam() {
        let app = launch("jam-mine-asjam")
        let control = app.segmentedControls["jam-filter-segments"]
        XCTAssertTrue(control.waitForExistence(timeout: 10))
        app.buttons["jam-filter-button"].tap()
        let toggle = app.buttons["Orgs"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.tap()
        XCTAssertTrue(app.staticTexts["Welcome from the circle"].waitForExistence(timeout: 5) || app.buttons.matching(NSPredicate(format: "label CONTAINS 'Welcome from the circle'")).firstMatch.exists, "the post shown as the jam")
        control.buttons["Articles"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS 'How we read together'")).firstMatch.waitForExistence(timeout: 5), "the article shown as the jam")
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Our first circle'")).firstMatch.exists, "not my article as myself")
    }

    func testAProfileWithAJamTitleOfItsOwnHasAnOrgsTabAndNoPerJamPill() {
        let app = launch("jam-mine-asjam")
        app.buttons["settings-button"].tap()
        let orgs = app.buttons["profile-tab-Orgs"]
        XCTAssertTrue(orgs.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Reading circles, tab'")).firstMatch.exists, "no pill named after the jam")
        orgs.tap()
        XCTAssertTrue(any(app, "profile-org-demo-my-jam").waitForExistence(timeout: 5), "the org's row")
        any(app, "profile-org-demo-my-jam").tap()
        XCTAssertTrue(app.staticTexts["profile-jam-row"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["jam-edit-page"].exists)
        XCTAssertTrue(app.segmentedControls["profile-org-segments"].exists)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Welcome from the circle'")).firstMatch.exists || app.staticTexts["Welcome from the circle"].exists, "the post shown as the org")
    }
}
