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
        XCTAssertTrue(app.buttons["profile-tab-Posts"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["profile-jam-subscribe"].exists)
    }

    func testTheJamTabTogglesPostsAndArticlesAndFiltersByMediaAndCoauthored() {
        let app = launch("jam-following")
        let control = app.segmentedControls["jam-filter-segments"]
        XCTAssertTrue(control.waitForExistence(timeout: 10))
        XCTAssertTrue(control.buttons["Posts"].isSelected, "Posts first, the default")
        XCTAssertFalse(app.buttons["jam-post-demo-post-1"].exists, "no article under Posts")
        XCTAssertTrue(app.buttons["jam-post-demo-post-2"].exists)
        control.buttons["Articles"].tap()
        XCTAssertTrue(app.buttons["jam-post-demo-post-1"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["jam-post-demo-post-2"].exists)
        control.buttons["Posts"].tap()
        // Media: Audio shows only the recording with audio.
        app.buttons["jam-filter-button"].tap()
        app.buttons["Audio"].tap()
        XCTAssertTrue(app.buttons["jam-post-demo-post-4"].waitForExistence(timeout: 5), "the audio recording")
        XCTAssertFalse(app.buttons["jam-post-demo-post-2"].exists)
        XCTAssertFalse(app.buttons["jam-post-demo-post-3"].exists)
        XCTAssertTrue(any(app, "jam-filter-badge").exists || app.buttons["jam-filter-button"].label.contains("1"), "the button counts the filters")
        // Co-authored: the article by Sam and Lee is under Articles.
        app.buttons["jam-filter-button"].tap()
        app.buttons["Clear filters"].tap()
        control.buttons["Articles"].tap()
        app.buttons["jam-filter-button"].tap()
        app.buttons["Co-authored"].tap()
        XCTAssertTrue(app.buttons["jam-post-demo-post-1"].waitForExistence(timeout: 5), "credited with Lee")
        XCTAssertFalse(app.staticTexts["Quick"].exists || app.buttons["Quick"].exists, "no \"Quick\" anywhere")
    }

    func testAnEmptyFilterSaysNoPostsMatchAndClears() {
        let app = launch("jam-following")
        XCTAssertTrue(app.segmentedControls["jam-filter-segments"].waitForExistence(timeout: 10))
        app.buttons["jam-filter-button"].tap()
        app.buttons["Co-authored"].tap()   // nothing in Posts is co-authored
        XCTAssertTrue(app.staticTexts["No posts match"].waitForExistence(timeout: 5))
        app.buttons["filter-clear-empty"].tap()
        XCTAssertTrue(app.buttons["jam-post-demo-post-2"].waitForExistence(timeout: 5))
    }
}
