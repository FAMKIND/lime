import XCTest

/// LIME-188: the jam tab (demo data, no core): Following and Your jam, starting a jam, writing a post, reading one, subscribing from a profile.
@MainActor
final class Jam188UITests: LimeUITestCase {
    private func launch(_ screen: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat"] + (screen.map { ["-lime-demo-screen", $0] } ?? [])
        app.launch()
        return app
    }

    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any)[id] }

    func testFollowingIsEmptyWithAHintAndYourJamOffersToStartOne() {
        let app = launch("jam")
        XCTAssertTrue(any(app, "jam-following-empty").waitForExistence(timeout: 10))
        XCTAssertEqual(any(app, "jam-following-empty").label, "Subscribe to a teacher\u{2019}s jam from their profile.")
        app.segmentedControls["jam-parts"].buttons["Your jam"].tap()
        XCTAssertTrue(app.buttons["jam-start"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["jam-start"].label, "Start your jam")
        XCTAssertFalse(app.buttons["jam-new-post"].exists)
    }

    func testStartingAJamShowsItInYourJamAndAPostCanBeWrittenAndListed() {
        let app = launch("jam")
        app.segmentedControls["jam-parts"].buttons["Your jam"].tap()
        app.buttons["jam-start"].tap()
        let title = app.textFields["jam-title-field"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["jam-details-save"].isEnabled, "a title is needed")
        title.tap(); title.typeText("Reading circles")
        app.buttons["jam-topic-Reading"].tap()
        app.buttons["jam-topic-Grade 2"].tap()
        app.buttons["jam-details-save"].tap()
        XCTAssertTrue(app.staticTexts["jam-mine-title"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["jam-mine-title"].label, "Reading circles")
        XCTAssertTrue(app.buttons["jam-subscribers"].label.contains("Subscribers: 0"), "the writer sees the count")

        app.buttons["jam-new-post"].tap()
        let postTitle = app.textFields["jam-post-title-field"].exists ? app.textFields["jam-post-title-field"] : app.textViews["jam-post-title-field"]
        XCTAssertTrue(postTitle.waitForExistence(timeout: 8))
        app.buttons["jam-publish"].tap()
        XCTAssertTrue(any(app, "jam-post-problem").waitForExistence(timeout: 3), "a post needs a title")
        postTitle.tap(); postTitle.typeText("Our first circle")
        app.textViews["composer-field"].tap()
        app.textViews["composer-field"].typeText("We read aloud together.")
        app.buttons["jam-publish"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Our first circle'")).firstMatch.waitForExistence(timeout: 8), "the post is listed")
    }

    func testAJamIFollowListsItsPostsAndOpeningOneShowsTheBodyAndThePhoto() {
        let app = launch("jam-following")
        let list = any(app, "jam-following-list")
        XCTAssertTrue(list.waitForExistence(timeout: 10))
        let newest = app.buttons["jam-post-demo-post-2"], first = app.buttons["jam-post-demo-post-1"]
        XCTAssertTrue(newest.exists && first.exists)
        XCTAssertLessThan(newest.frame.minY, first.frame.minY, "newest first")
        XCTAssertTrue(first.label.contains("Sam Park") && first.label.contains("Equivalent fractions"), first.label)
        first.tap()
        XCTAssertTrue(any(app, "jam-reader-title").waitForExistence(timeout: 8))
        XCTAssertEqual(any(app, "jam-reader-title").label, "Equivalent fractions in ten minutes")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Start with a pizza'")).firstMatch.waitForExistence(timeout: 5), "the bold line is drawn")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'compare the pieces'")).firstMatch.exists, "and the list")
        XCTAssertTrue(any(app, "jam-photo").waitForExistence(timeout: 8), "the photo")
    }

    func testTheWritersProfileShowsTheirJamAndSubscribeFlipsToSubscribedAndTheirPostsAppear() {
        let app = launch()
        app.buttons["conversation-row-dm:sam"].tap()
        any(app, "chat-title").tap()
        XCTAssertTrue(any(app, "profile-screen").waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["profile-jam-row"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["profile-jam-row"].label, "Fractions that stick")
        let subscribe = app.buttons["profile-jam-subscribe"]
        XCTAssertEqual(subscribe.label, "Subscribe to Fractions that stick")
        subscribe.tap()
        let subscribed = NSPredicate(format: "label BEGINSWITH 'Subscribed'")
        expectation(for: subscribed, evaluatedWith: app.buttons["profile-jam-subscribe"])
        waitForExpectations(timeout: 8)
        // Back out of the profile and the chat to the tab bar: their posts are in Following.
        for _ in 0..<4 where !app.tabBars.buttons["jam"].isHittable { app.navigationBars.buttons.element(boundBy: 0).tap() }
        app.tabBars.buttons["jam"].tap()
        XCTAssertTrue(app.buttons["jam-post-demo-post-1"].waitForExistence(timeout: 8))
    }

    func testTheWriterSeesWhoFollowsAndCanRemoveSomeone() {
        let app = launch("jam-mine")
        app.segmentedControls["jam-parts"].buttons["Your jam"].tap()
        XCTAssertTrue(app.buttons["jam-subscribers"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["jam-subscribers"].label.contains("Subscribers: 2"))
        app.buttons["jam-subscribers"].tap()
        XCTAssertTrue(app.buttons["jam-remove-sam"].waitForExistence(timeout: 8))
        app.buttons["jam-remove-sam"].tap()
        app.buttons["jam-remove-confirm"].tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.buttons["jam-remove-sam"])
        waitForExpectations(timeout: 8)
        XCTAssertTrue(app.buttons["jam-remove-lee"].exists)
    }
}
