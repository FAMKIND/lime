import XCTest

/// LIME-242 and LIME-243 (demo): step titles, About's formatting, an old account's Everyone, the publishing state and where it lands, series in the cards, skeletons.
@MainActor
final class Fix242UITests: LimeUITestCase {
    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    private func launch(_ screen: String, _ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", screen] + extra
        app.launch()
        return app
    }

    func testAnArticlesTwoStepsAreTitledAsAPairAndAnOldAccountsEveryoneIsAvailable() {
        let app = launch("jam-mine", ["-lime-demo-open"])
        XCTAssertTrue(app.buttons["new-jam-post"].waitForExistence(timeout: 10)); app.buttons["new-jam-post"].tap()
        app.buttons["jam-write-article"].tap()
        XCTAssertTrue(app.navigationBars["Step 1 of 2"].waitForExistence(timeout: 8))
        let title = app.textFields["jam-article-title"].exists ? app.textFields["jam-article-title"] : app.textViews["jam-article-title"]
        title.tap(); title.typeText("Pairs\n\n")
        let body = app.textViews["composer-field"]; body.tap(); body.typeText("Two steps")
        app.buttons["jam-next"].tap()
        XCTAssertTrue(app.navigationBars["Step 2 of 2"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["Before you publish"].exists, "no second title")
        any(app, "jam-audience").tap()
        XCTAssertTrue(any(app, "audience-everyone").isEnabled, "an old account is not held back")
        XCTAssertEqual(any(app, "audience-everyone").label, "Everyone on lime")
    }

    func testTheAboutSheetRendersTheDescriptionsHeading() {
        let app = launch("jam-mine-podcast")
        any(app, "jam-filter-segments").buttons["Podcasts"].tap()
        let pill = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'jam-audio-play-'")).firstMatch
        XCTAssertTrue(pill.waitForExistence(timeout: 10)); pill.tap()
        XCTAssertTrue(any(app, "jam-video-screen").waitForExistence(timeout: 5))
        app.buttons["jam-video-text"].tap()
        let description = any(app, "jam-about-description")
        XCTAssertTrue(description.waitForExistence(timeout: 5))
        let text = (description.label + " " + app.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " "))
        XCTAssertTrue(text.contains("Explore the different types of songs."), text)
        XCTAssertFalse(text.contains("##"), "the heading is drawn, not printed: \(text)")
    }

    func testPublishingShowsASpinnerThenJamOpensOnTheNewVideoPodcastNeverBackToNewPost() {
        let app = launch("jam-mine", ["-lime-demo-slow-publish"])
        XCTAssertTrue(app.buttons["new-jam-post"].waitForExistence(timeout: 10)); app.buttons["new-jam-post"].tap()
        app.buttons["jam-record"].tap()
        app.buttons["podcast-record"].tap(); sleep(2); app.buttons["podcast-stop"].tap()
        let name = any(app, "podcast-title"); XCTAssertTrue(name.waitForExistence(timeout: 8)); name.tap(); name.typeText("Landing podcast")
        app.buttons["podcast-next"].tap()
        let publish = app.buttons["podcast-post"]
        XCTAssertTrue(publish.waitForExistence(timeout: 8)); XCTAssertEqual(publish.label, "Publish")
        publish.tap()
        let working = app.buttons["Publishing\u{2026}"]
        XCTAssertTrue(working.waitForExistence(timeout: 3), "a spinner and \"Publishing…\" while it goes out")
        // Then the whole flow closes and jam shows the new post; it never lands on New post / step 1.
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.buttons["podcast-post"])
        waitForExpectations(timeout: 20)
        XCTAssertFalse(app.buttons["jam-next"].exists || any(app, "podcast-recorder").exists || app.navigationBars["Step 1 of 2"].exists, "the whole flow closed")
        XCTAssertTrue(app.buttons["new-jam-post"].waitForExistence(timeout: 5), "back on jam")
        let card = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Landing podcast'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 8), "the new post is in the feed")
    }

    func testAQuickPostShowsPostingThenLandsOnItInTheFeed() {
        let app = launch("jam-mine", ["-lime-demo-slow-publish"])
        XCTAssertTrue(app.buttons["new-jam-post"].waitForExistence(timeout: 10)); app.buttons["new-jam-post"].tap()
        let body = app.textViews["composer-field"]; XCTAssertTrue(body.waitForExistence(timeout: 8)); body.tap(); body.typeText("A fresh quick post")
        app.buttons["jam-next"].tap()
        app.buttons["jam-post"].tap()
        XCTAssertTrue(app.buttons["Posting\u{2026}"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["new-jam-post"].waitForExistence(timeout: 15))
        let card = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'A fresh quick post'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 8))
    }

    func testTheSeriesLineIsInsideTheArticleCoverAndUnderThePodcastsTitles() {
        let app = launch("jam-series")
        let article = any(app, "jam-card-series-demo-post-1")
        for _ in 0..<5 where !article.exists { app.swipeUp() }
        XCTAssertTrue(article.waitForExistence(timeout: 10))
        let cover = any(app, "jam-post-demo-post-1")
        XCTAssertTrue(cover.frame.contains(article.frame), "inside the cover card: \(article.frame) in \(cover.frame)")
        // The small audio card and the big video card: a line under the title.
        for id in ["demo-post-4", "demo-post-3"] {
            let line = any(app, "jam-card-series-\(id)")
            for _ in 0..<8 where !line.exists { app.swipeUp() }
            XCTAssertTrue(line.waitForExistence(timeout: 5), id)
        }
        XCTAssertTrue(any(app, "jam-card-series-demo-post-3").label.hasPrefix("Part 2 of 2"))
        any(app, "jam-card-series-demo-post-3").tap()
        XCTAssertTrue(any(app, "series-page").waitForExistence(timeout: 5), "opens the series")
    }

    func testASlowFeedShowsSkeletonCardsFirst() {
        let app = launch("jam-following", ["-lime-demo-slow-feed"])
        XCTAssertTrue(any(app, "skeleton-feed").waitForExistence(timeout: 5), "placeholders in the shape of the cards")
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'jam-post-'")).firstMatch.waitForExistence(timeout: 12), "then the posts")
        XCTAssertFalse(any(app, "skeleton-feed").exists)
    }
}
