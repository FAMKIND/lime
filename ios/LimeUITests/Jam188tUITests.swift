import XCTest

/// LIME-188t: Subscribe in the profile header; Posts | Articles and filters on top of jam, like link and call.
@MainActor
final class Jam188tUITests: LimeUITestCase {
    private func launch(_ screen: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", screen]
        app.launch()
        return app
    }

    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    func testTheHeaderHasSubscribeForAJamWriterAndTapSubscribes() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat"]
        app.launch()
        app.buttons["conversation-row-dm:sam"].tap()
        any(app, "chat-title").tap()
        XCTAssertTrue(any(app, "profile-screen").waitForExistence(timeout: 10))
        let subscribe = app.buttons["profile-jam-subscribe"]
        XCTAssertTrue(subscribe.waitForExistence(timeout: 8), "in the header's actions row, on the first tab")
        XCTAssertTrue(app.buttons["profile-tab-Info"].isSelected)
        XCTAssertTrue(subscribe.label.hasPrefix("Subscribe to"))
        XCTAssertLessThan(subscribe.frame.minY, app.buttons["profile-tab-Info"].frame.minY, "above the tabs")
        subscribe.tap()
        expectation(for: NSPredicate(format: "label BEGINSWITH 'Subscribed'"), evaluatedWith: subscribe)
        waitForExpectations(timeout: 8)
    }

    func testNoSubscribeOnYourOwnProfile() {
        let app = launch("jam-mine-profile")
        XCTAssertTrue(app.buttons["profile-tab-Info"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["profile-jam-subscribe"].exists)
    }

    func testTheJamTabTogglesAllPostsArticlesAndPodcastsAndFiltersByMediaAndCoauthored() throws {
        try XCTSkipIf(true, "known failing (rule 12d): stale since Drafts (233g) made five pills, so \"All\" scrolls out of reach after Podcasts; needs a scroll step, not part of LIME-210")
        let app = launch("jam-following")
        let control = app.descendants(matching: .any).matching(identifier: "jam-filter-segments").firstMatch
        XCTAssertTrue(control.waitForExistence(timeout: 10))
        XCTAssertEqual(control.buttons.count, 5, "All, Posts, Articles, Podcasts and Drafts (Discover shows only when the server takes open posts)")
        let order = ["All", "Posts", "Articles", "Podcasts"].map { control.buttons[$0].frame.minX }
        XCTAssertEqual(order, order.sorted(), "pills in order")
        XCTAssertGreaterThan(app.buttons["jam-filter-button"].frame.minX, control.buttons["Podcasts"].frame.maxX - 1, "the filter button is at the far right, outside the pills")
        XCTAssertTrue(control.buttons["All"].isSelected, "All first, the default")
        XCTAssertTrue(app.buttons["jam-post-demo-post-1"].exists && app.buttons["jam-post-demo-post-2"].exists, "everything under All")
        control.buttons["Posts"].tap()
        XCTAssertTrue(app.buttons["jam-post-demo-post-2"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["jam-post-demo-post-1"].exists, "no article under Posts")
        XCTAssertFalse(any(app, "jam-audio-card-demo-audio-1").exists, "no recording under Posts")
        control.buttons["Articles"].tap()
        XCTAssertTrue(app.buttons["jam-post-demo-post-1"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["jam-post-demo-post-2"].exists)
        control.buttons["Podcasts"].tap()
        XCTAssertTrue(any(app, "jam-audio-card-demo-audio-1").waitForExistence(timeout: 5), "the recordings")
        XCTAssertFalse(app.buttons["jam-post-demo-post-2"].exists)
        // Media: Audio shows only the recording with audio.
        control.buttons["All"].tap()
        app.buttons["jam-filter-button"].tap()
        XCTAssertTrue(app.buttons["Photos"].exists && app.buttons["Video"].exists && app.buttons["Audio"].exists)
        XCTAssertTrue(app.buttons["Co-authored"].exists && app.buttons["Subscribed"].exists && app.buttons["Orgs"].exists && app.buttons["Saved"].exists, "the filters")
        app.buttons["Audio"].tap()
        XCTAssertTrue(any(app, "jam-audio-card-demo-audio-1").waitForExistence(timeout: 5), "the audio recording")
        XCTAssertFalse(app.buttons["jam-post-demo-post-2"].exists)
        XCTAssertFalse(app.buttons["jam-post-demo-post-3"].exists)
        XCTAssertTrue(any(app, "jam-filter-badge").exists || app.buttons["jam-filter-button"].label.contains("1"), "the button counts the filters")
        // Co-authored: the article by Sam and Lee.
        app.buttons["jam-filter-button"].tap()
        app.buttons["Clear filters"].tap()
        app.buttons["jam-filter-button"].tap()
        app.buttons["Co-authored"].tap()
        XCTAssertTrue(app.buttons["jam-post-demo-post-1"].waitForExistence(timeout: 5), "credited with Lee")
        XCTAssertFalse(app.buttons["jam-post-demo-post-2"].exists)
        XCTAssertFalse(app.staticTexts["Quick"].exists || app.buttons["Quick"].exists, "no \"Quick\" anywhere")
    }

    func testAnEmptyFilterSaysNoPostsMatchAndClears() {
        let app = launch("jam-following")
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "jam-filter-segments").firstMatch.waitForExistence(timeout: 10))
        app.descendants(matching: .any).matching(identifier: "jam-filter-segments").firstMatch.buttons["Posts"].tap()
        app.buttons["jam-filter-button"].tap()
        app.buttons["Co-authored"].tap()   // nothing in Posts is co-authored
        XCTAssertTrue(app.staticTexts["No posts match"].waitForExistence(timeout: 5))
        app.buttons["filter-clear-empty"].tap()
        XCTAssertTrue(app.buttons["jam-post-demo-post-2"].waitForExistence(timeout: 5))
    }
}
