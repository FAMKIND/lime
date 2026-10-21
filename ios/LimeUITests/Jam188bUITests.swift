import XCTest

/// LIME-188b: the jam tab as a feed: a + to post (quick post, article, recording), your jam made on your first post, the profile as the jam page.
@MainActor
final class Jam188bUITests: LimeUITestCase {
    private func launch(_ screen: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat"] + (screen.map { ["-lime-demo-screen", $0] } ?? [])
        app.launch()
        return app
    }

    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any)[id] }

    private func card(_ app: XCUIApplication, containing text: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func write(_ app: XCUIApplication, _ text: String) {
        let field = app.textViews["composer-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 8))
        field.tap()
        field.typeText(text)
    }

    func testTheTabIsOneFeedWithAPlusAndNothingToSetUp() {
        let app = launch("jam")
        XCTAssertTrue(any(app, "jam-feed-empty").waitForExistence(timeout: 10))
        XCTAssertEqual(any(app, "jam-feed-empty").label, "Subscribe to teachers from their profiles. Your posts show here too.")
        XCTAssertTrue(app.buttons["new-jam-post"].exists)
        XCTAssertEqual(app.buttons["new-jam-post"].label, "New post")
        XCTAssertFalse(app.segmentedControls["jam-parts"].exists, "no Following / Your jam")
        XCTAssertFalse(app.buttons["jam-start"].exists, "no 'Start your jam'")
    }

    func testAQuickPostWithTheFirstPostMakingTheJamAndShowingFirstInTheFeed() {
        let app = launch("jam")
        app.buttons["new-jam-post"].tap()
        XCTAssertFalse(app.buttons["jam-post"].isEnabled, "nothing to post yet")
        write(app, "Thinking about fractions today")
        XCTAssertTrue(app.buttons["jam-post"].isEnabled)
        app.buttons["jam-post"].tap()
        XCTAssertTrue(card(app, containing: "Thinking about fractions today").waitForExistence(timeout: 8), "the post is in the feed")
        XCTAssertFalse(any(app, "jam-feed-empty").exists)
        for action in ["like", "comment", "remix", "share"] {
            XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", action)).firstMatch.exists, "the \(action) icon is there (dimmed until 189)")
        }
    }

    func testAnArticleHasATitleASubtitleAndABodyAndTheCardShowsTheFirstTwo() {
        let app = launch("jam")
        app.buttons["new-jam-post"].tap()
        app.buttons["jam-write-article"].tap()
        XCTAssertTrue(app.buttons["jam-exit-article"].exists)
        XCTAssertFalse(app.buttons["jam-post"].isEnabled)
        let title = app.textFields["jam-article-title"].exists ? app.textFields["jam-article-title"] : app.textViews["jam-article-title"]
        title.tap(); title.typeText("Exit tickets that work")
        let subtitle = app.textFields["jam-article-subtitle"].exists ? app.textFields["jam-article-subtitle"] : app.textViews["jam-article-subtitle"]
        subtitle.tap(); subtitle.typeText("Five questions for the door")
        write(app, "Ask one question as they leave.")
        app.buttons["jam-post"].tap()
        let article = card(app, containing: "Exit tickets that work")
        XCTAssertTrue(article.waitForExistence(timeout: 8))
        XCTAssertTrue(article.label.contains("Five questions for the door"))
        article.tap()
        XCTAssertEqual(any(app, "jam-reader-title").label, "Exit tickets that work")
        XCTAssertEqual(any(app, "jam-reader-subtitle").label, "Five questions for the door")
    }

    func testRecordingAttachesAClipAndTheCardPlaysItInline() {
        let app = launch("jam")
        app.buttons["new-jam-post"].tap()
        app.buttons["jam-record"].tap()
        XCTAssertTrue(app.buttons["jam-record-video"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["jam-record-next"].isEnabled)
        app.textFields["jam-record-title"].tap(); app.textFields["jam-record-title"].typeText("Ten seconds on fraction walls")
        app.buttons["jam-record-video"].tap()
        XCTAssertTrue(any(app, "jam-record-ready").waitForExistence(timeout: 8))
        app.buttons["jam-record-next"].tap()
        XCTAssertTrue(app.buttons["jam-recorded-0"].waitForExistence(timeout: 5), "the clip is attached")
        app.buttons["jam-post"].tap()
        XCTAssertTrue(card(app, containing: "Ten seconds on fraction walls").waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["jam-video"].waitForExistence(timeout: 5), "the video sits in the card")
    }

    func testTheFeedShowsWhatIFollowAsCardsOfThreeKindsAndAnArticleOpensToItsBody() {
        let app = launch("jam-following")
        XCTAssertTrue(any(app, "jam-feed").waitForExistence(timeout: 10))
        let record = app.buttons["jam-post-demo-post-3"], quick = app.buttons["jam-post-demo-post-2"], article = app.buttons["jam-post-demo-post-1"]
        XCTAssertTrue(record.exists && quick.exists && article.exists)
        XCTAssertLessThan(record.frame.minY, quick.frame.minY, "newest first")
        XCTAssertLessThan(quick.frame.minY, article.frame.minY)
        XCTAssertTrue(article.label.contains("Equivalent fractions") && article.label.contains("Fold, cut, compare"))
        XCTAssertTrue(app.buttons["jam-card-writer-demo-post-1"].label.contains("Sam Park"), "who wrote it, tap for their profile")
        article.tap()
        XCTAssertEqual(any(app, "jam-reader-title").label, "Equivalent fractions in ten minutes")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Start with a pizza'")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(any(app, "jam-photo").waitForExistence(timeout: 8))
    }

    func testTheProfileIsTheJamPageWithACountSubscribeAndPostsThatOpenOnceSubscribed() {
        let app = launch()
        app.buttons["conversation-row-dm:sam"].tap()
        any(app, "chat-title").tap()
        XCTAssertTrue(any(app, "profile-screen").waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["profile-jam-row"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["profile-jam-row"].label, "Fractions that stick")
        XCTAssertEqual(app.staticTexts["profile-jam-subscribers"].label, "12 subscribers")
        XCTAssertTrue(app.staticTexts["profile-jam-locked"].exists, "posts are for subscribers")
        XCTAssertFalse(app.buttons["jam-post-demo-post-1"].exists)
        app.buttons["profile-jam-subscribe"].tap()
        expectation(for: NSPredicate(format: "label BEGINSWITH 'Subscribed'"), evaluatedWith: app.buttons["profile-jam-subscribe"])
        waitForExpectations(timeout: 8)
        XCTAssertTrue(app.buttons["jam-post-demo-post-1"].waitForExistence(timeout: 8), "their posts are on the page now")
    }

    func testMyProfileShowsMyPostsWhoFollowsAndEditJamPageAndTheWriterCanRemoveSomeone() {
        let app = launch("jam-mine-profile")
        XCTAssertTrue(app.buttons["jam-edit-page"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["profile-jam-subscribers"].label, "2 subscribers")
        XCTAssertFalse(app.buttons["profile-jam-subscribe"].exists, "no Subscribe on my own page")
        XCTAssertTrue(card(app, containing: "We read aloud together").exists, "my post")
        app.buttons["jam-subscribers"].tap()
        XCTAssertTrue(app.buttons["jam-remove-sam"].waitForExistence(timeout: 8))
        app.buttons["jam-remove-sam"].tap()
        app.buttons["jam-remove-confirm"].tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.buttons["jam-remove-sam"])
        waitForExpectations(timeout: 8)
        XCTAssertTrue(app.buttons["jam-remove-lee"].exists)
    }
}
