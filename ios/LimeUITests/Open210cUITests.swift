import XCTest

/// LIME-210c: audiences, the Preview and Discover (demo).
@MainActor
final class Open210cUITests: LimeUITestCase {
    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    func testChoosingEveryoneShowsTheCopyAndTheCardGetsAGlobe() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "jam-mine", "-lime-demo-open"]
        app.launch()
        XCTAssertTrue(app.buttons["new-jam-post"].waitForExistence(timeout: 10))
        app.buttons["new-jam-post"].tap()
        let chip = any(app, "jam-audience")
        XCTAssertTrue(chip.waitForExistence(timeout: 8), "the audience chip is beside Post as")
        XCTAssertTrue(chip.label.contains("subscribers"), chip.label)
        chip.tap()
        any(app, "audience-everyone").tap()
        XCTAssertTrue(app.staticTexts["Everyone on lime can read this, and so can lime's server."].waitForExistence(timeout: 5), "the exact copy")
        // Keeping it for subscribers leaves the chip alone.
        any(app, "audience-keep").tap()
        XCTAssertTrue(any(app, "jam-audience").label.contains("subscribers"))
        any(app, "jam-audience").tap(); any(app, "audience-everyone").tap()
        any(app, "audience-confirm-everyone").tap()
        XCTAssertTrue(any(app, "jam-audience").label.contains("everyone"), any(app, "jam-audience").label)
        let body = app.textViews["composer-field"]
        XCTAssertTrue(body.waitForExistence(timeout: 5))
        body.tap(); body.typeText("Open to all")
        app.buttons["jam-post"].tap()
        let globe = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'jam-card-globe-'")).firstMatch
        XCTAssertTrue(globe.waitForExistence(timeout: 10), "an open post shows the globe by its date")
    }

    func testTheChipIsHiddenWhileTheServerDoesNotTakeOpenPosts() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "jam-mine"]
        app.launch()
        XCTAssertTrue(app.buttons["new-jam-post"].waitForExistence(timeout: 10))
        app.buttons["new-jam-post"].tap()
        XCTAssertTrue(app.textViews["composer-field"].waitForExistence(timeout: 8))
        XCTAssertFalse(any(app, "jam-audience").exists, "hidden, not disabled")
        app.buttons["jam-compose-cancel"].tap()
        XCTAssertFalse(app.buttons["jam-segment-Discover"].exists, "no Discover either")
    }

    func testDiscoverGroupsAWritersPostsFiltersOnThePhoneAndAPreviewAsksToSubscribe() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "jam-discover"]
        app.launch()
        XCTAssertTrue(any(app, "jam-discover").waitForExistence(timeout: 10))
        // Sam's four posts are one row; the other writers' posts are cards with a globe.
        let group = app.buttons["discover-group-sam"]
        XCTAssertTrue(group.waitForExistence(timeout: 5))
        XCTAssertTrue(group.label.contains("posted 4 articles"), group.label)
        XCTAssertFalse(any(app, "discover-post-demo-open-sam-2").exists, "grouped until opened")
        XCTAssertTrue(any(app, "discover-post-demo-open-lee-1").exists)
        XCTAssertTrue(any(app, "discover-globe-demo-open-lee-1").exists)
        // The filter is the phone's: a chip for a topic hides the rest.
        any(app, "discover-topics").swipeLeft()
        app.buttons["discover-topic-Reading"].tap()
        XCTAssertTrue(any(app, "discover-post-demo-open-lee-1").exists)
        XCTAssertFalse(group.exists, "Sam's posts are not about Reading")
        any(app, "discover-topics").swipeRight()
        app.buttons["discover-topic-all"].tap()
        XCTAssertTrue(group.waitForExistence(timeout: 3))
        // Opening the group lists them; the first is a Preview (lock).
        group.tap()
        XCTAssertTrue(any(app, "discover-preview-demo-post-1").waitForExistence(timeout: 3), "the lock and Preview")
        XCTAssertTrue(any(app, "discover-post-demo-open-sam-2").exists)
        // The Preview page: the open part, then Subscribe to read the rest. A like asks to subscribe.
        any(app, "discover-post-demo-post-1").tap()
        XCTAssertTrue(any(app, "open-post-page").waitForExistence(timeout: 5))
        XCTAssertTrue(any(app, "open-post-title").exists)
        let subscribe = app.buttons["open-post-subscribe"]
        XCTAssertTrue(subscribe.exists)
        XCTAssertEqual(subscribe.label, "Subscribe to read the rest")
        app.buttons["open-post-heart"].tap()
        XCTAssertTrue(any(app, "open-post-subscribe-prompt").waitForExistence(timeout: 3))
        XCTAssertEqual(any(app, "open-post-subscribe-prompt").label, "Subscribe to like and comment")
        // Subscribing opens the whole post.
        subscribe.tap()
        XCTAssertTrue(any(app, "jam-reader-title").waitForExistence(timeout: 8), "the whole post opens")
        XCTAssertFalse(any(app, "open-post-subscribe").exists)
    }

    func testAnOpenPostWithoutACutShowsItsGlobeAndNoSubscribePrompt() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "jam-discover"]
        app.launch()
        let card = any(app, "discover-post-demo-open-lee-1")
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.tap()
        XCTAssertTrue(any(app, "open-post-page").waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["open-post-subscribe"].exists, "nothing is cut")
        XCTAssertTrue(any(app, "open-post-body").exists)
    }
}
