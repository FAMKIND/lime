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

    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    func testTheFeedIsOneScrollViewFromTheTopOfTheScreenSoItScrollsUnderTheHeader() {
        let app = launch("jam-following")
        let feed = app.scrollViews["jam-feed"]
        XCTAssertTrue(feed.waitForExistence(timeout: 10))
        XCTAssertLessThan(feed.frame.minY, 5, "the scroll view starts at the top edge: the header floats over it, with nothing behind its icons")
        XCTAssertTrue(app.buttons["jam-search-button"].exists && app.buttons["settings-button"].exists)
        XCTAssertTrue(app.segmentedControls["jam-filter-segments"].exists, "the filter row is inside it")
    }

    func testThreeSegmentsAndSavedListsASavedPostOrSaysNothingYet() {
        let app = launch("jam-following")
        let control = app.segmentedControls["jam-filter-segments"]
        XCTAssertTrue(control.waitForExistence(timeout: 10))
        XCTAssertEqual(control.buttons.count, 3)
        XCTAssertTrue(control.buttons["Posts"].exists && control.buttons["Articles"].exists && control.buttons["Saved"].exists)
        XCTAssertFalse(app.buttons["jam-saved-row"].exists, "the Saved (n) row is gone")
        control.buttons["Saved"].tap()
        XCTAssertTrue(any(app, "jam-saved-empty").waitForExistence(timeout: 5))
        XCTAssertEqual(any(app, "jam-saved-empty").label, "Nothing saved yet.")
        control.buttons["Articles"].tap()
        let save = app.buttons["jam-article-save-demo-post-1"]
        XCTAssertTrue(save.waitForExistence(timeout: 8))
        save.tap()
        control.buttons["Saved"].tap()
        XCTAssertTrue(app.buttons["jam-post-demo-post-1"].waitForExistence(timeout: 5), "the saved article")
        XCTAssertFalse(any(app, "jam-saved-empty").exists)
        // Put it back so the next run starts clean.
        app.buttons["jam-article-save-demo-post-1"].tap()
        XCTAssertTrue(any(app, "jam-saved-empty").waitForExistence(timeout: 5))
    }

    func testTheFilterFromJamsAndGroupsShowsOnlyPostsShownAsTheJam() {
        let app = launch("jam-mine-asjam")
        let control = app.segmentedControls["jam-filter-segments"]
        XCTAssertTrue(control.waitForExistence(timeout: 10))
        app.buttons["jam-filter-button"].tap()
        let toggle = app.buttons["From jams & groups"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.tap()
        XCTAssertTrue(app.staticTexts["Welcome from the circle"].waitForExistence(timeout: 5) || app.buttons.matching(NSPredicate(format: "label CONTAINS 'Welcome from the circle'")).firstMatch.exists, "the post shown as the jam")
        control.buttons["Articles"].tap()
        XCTAssertTrue(any(app, "filter-clear-empty").waitForExistence(timeout: 5), "my article is as myself: nothing matches")
    }

    func testAProfileWithAJamTitleOfItsOwnHasAPillAfterActivityWithTheHeadAndPostsHasNone() {
        let app = launch("jam-mine-asjam")
        // Open my profile from the header's avatar.
        app.buttons["settings-button"].tap()
        let jam = app.buttons["profile-tab-Jam"]
        XCTAssertTrue(jam.waitForExistence(timeout: 10))
        XCTAssertTrue(jam.label.hasPrefix("Reading circles, tab"), jam.label)
        XCTAssertGreaterThan(jam.frame.minX, app.buttons["profile-tab-Activity"].frame.minX)
        XCTAssertLessThan(jam.frame.minX, app.buttons["profile-tab-Posts"].frame.minX)
        jam.tap()
        XCTAssertTrue(app.staticTexts["profile-jam-row"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["jam-edit-page"].exists)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Welcome from the circle'")).firstMatch.exists || app.staticTexts["Welcome from the circle"].exists, "the post shown as the jam")
        app.buttons["profile-tab-Posts"].tap()
        XCTAssertFalse(app.staticTexts["profile-jam-row"].exists, "no head under Posts")
        XCTAssertFalse(app.staticTexts["Welcome from the circle"].exists, "and not the jam's posts")
    }
}
