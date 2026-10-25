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

    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    private func card(_ app: XCUIApplication, containing text: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    /// An article's ⊕ menu: Image (demo: a made-up picture goes in at the caret).
    private func addArticlePhoto(_ app: XCUIApplication) {
        app.buttons["jam-add"].tap()
        app.buttons["Photo"].tap(); app.buttons["Library"].tap()
        sleep(1)
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

    func testAQuickPostWithThreePhotosPostsAndTheTextSitsAtTheTop() {
        let app = launch("jam")
        app.buttons["new-jam-post"].tap()
        write(app, "Our field trip")
        let field = app.textViews["composer-field"]
        XCTAssertLessThan(field.frame.minY, app.windows.firstMatch.frame.height * 0.35, "the words are at the top, under the name")
        for _ in 0..<3 { app.buttons["jam-add-photo"].tap() }
        XCTAssertTrue(any(app, "jam-photo-2").waitForExistence(timeout: 8), "three photos in a row under the words")
        XCTAssertGreaterThan(any(app, "jam-photos").frame.minY, field.frame.minY, "under the text")
        app.buttons["jam-post"].tap()
        XCTAssertTrue(card(app, containing: "Our field trip").waitForExistence(timeout: 8), "it posts")
        XCTAssertTrue(any(app, "jam-photo-row").waitForExistence(timeout: 8), "the photos are one row that scrolls sideways")
        XCTAssertEqual(any(app, "jam-photo-counter").label, "1 / 3")
        let first = app.descendants(matching: .any).matching(identifier: "jam-row-photo-0").firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 8))
        first.tap()
        XCTAssertTrue(any(app, "attachment-viewer").waitForExistence(timeout: 5), "a tap opens the same viewer chats use")
        XCTAssertEqual(any(app, "attachment-viewer-count").label, "1 of 3")
    }

    func testAnArticleIsAPageWithPhotosPutInTheTextAndTheReaderShowsThemInOrder() {
        let app = launch("jam")
        app.buttons["new-jam-post"].tap()
        app.buttons["jam-write-article"].tap()
        XCTAssertTrue(app.buttons["jam-exit-article"].exists)
        XCTAssertFalse(app.buttons["jam-post"].isEnabled)
        let title = app.textFields["jam-article-title"].exists ? app.textFields["jam-article-title"] : app.textViews["jam-article-title"]
        title.tap(); title.typeText("Exit tickets that work")
        let subtitle = app.textFields["jam-article-subtitle"].exists ? app.textFields["jam-article-subtitle"] : app.textViews["jam-article-subtitle"]
        subtitle.tap()
        subtitle.typeText(String(repeating: "x", count: 200)); sleep(3)   // the cap trims after the last key
        XCTAssertLessThanOrEqual((subtitle.value as? String ?? "").count, 160, "a subtitle never takes more than 160")
        subtitle.typeText("\n")   // Return moves to the body
        let body = app.textViews["composer-field"]
        expectation(for: NSPredicate(format: "hasKeyboardFocus == true"), evaluatedWith: body)
        waitForExpectations(timeout: 5)   // Return in the subtitle moved the caret to the body
        body.typeText("Ask one question as they leave.\n\n")
        addArticlePhoto(app)
        body.typeText((1...20).map { "Line \($0) of the plan" }.joined(separator: "\n") + "\n\n")
        addArticlePhoto(app)
        XCTAssertFalse((subtitle.value as? String ?? "").contains("Ask one question"), "the subtitle never holds the article")
        app.buttons["jam-post"].tap()
        app.showJamArticles()
        let article = card(app, containing: "Exit tickets that work")
        XCTAssertTrue(article.waitForExistence(timeout: 8))
        article.tap()
        XCTAssertEqual(any(app, "jam-reader-title").label, "Exit tickets that work")
        XCTAssertEqual((any(app, "jam-reader-subtitle").label).count, 160)
        let firstWords = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Ask one question'")).firstMatch
        let firstPhoto = any(app, "jam-inline-0"), secondPhoto = any(app, "jam-inline-1")
        XCTAssertTrue(firstWords.waitForExistence(timeout: 8) && firstPhoto.waitForExistence(timeout: 8))
        XCTAssertLessThan(any(app, "jam-reader-title").frame.minY, any(app, "jam-reader-subtitle").frame.minY)
        XCTAssertLessThan(any(app, "jam-reader-subtitle").frame.minY, firstWords.frame.minY)
        XCTAssertLessThan(firstWords.frame.minY, firstPhoto.frame.minY, "the first photo stands after the first paragraph")
        if secondPhoto.exists { XCTAssertLessThan(firstPhoto.frame.minY, secondPhoto.frame.minY) }
    }

    func testTheFeedShowsWhatIFollowAsCardsOfThreeKindsAndAnArticleOpensToItsBody() {
        let app = launch("jam-following")
        XCTAssertTrue(any(app, "jam-feed").waitForExistence(timeout: 10))
        let record = any(app, "jam-card-byline-demo-post-3"), quick = app.buttons["jam-post-demo-post-2"]
        XCTAssertTrue(record.exists && quick.exists, "All: the recording and the quick post")
        XCTAssertLessThan(record.frame.minY, quick.frame.minY, "newest first")
        app.showJamArticles()
        let article = app.buttons["jam-post-demo-post-1"]
        XCTAssertTrue(article.waitForExistence(timeout: 5))
        XCTAssertTrue(article.label.contains("Equivalent fractions") && article.label.contains("Fold, cut, compare"))
        XCTAssertTrue(app.buttons["jam-card-writer-demo-post-1"].label.contains("Sam Park"), "who wrote it, tap for their profile")
        article.tap()
        XCTAssertEqual(any(app, "jam-reader-title").label, "Equivalent fractions in ten minutes")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Start with a pizza'")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(any(app, "jam-row-photo-0").waitForExistence(timeout: 8))
    }

    func testTheProfileIsTheJamPageWithACountSubscribeAndPostsThatOpenOnceSubscribed() {
        let app = launch()
        app.buttons["conversation-row-dm:sam"].tap()
        any(app, "chat-title").tap()
        XCTAssertTrue(any(app, "profile-screen").waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["profile-tab-Orgs"].waitForExistence(timeout: 8))
        app.buttons["profile-tab-Orgs"].tap()   // the jam page is reached from the Orgs tab (LIME-188x)
        any(app, "profile-org-demo-sam-jam").tap()
        XCTAssertTrue(app.staticTexts["profile-jam-row"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["profile-jam-row"].label, "Fractions that stick")
        XCTAssertEqual(app.staticTexts["profile-jam-subscribers"].label, "12 subscribers")
        XCTAssertTrue(app.staticTexts["profile-jam-locked"].exists, "posts are for subscribers")
        XCTAssertFalse(app.buttons["jam-post-demo-post-1"].exists)
        app.navigationBars.buttons.firstMatch.tap()   // back from the org's profile (LIME-216: pushed, not a sheet)
        XCTAssertTrue(app.buttons["profile-jam-subscribe"].exists, "Subscribe is a link under the name (LIME-188x)")
        app.buttons["profile-jam-subscribe"].tap()
        expectation(for: NSPredicate(format: "label BEGINSWITH 'Subscribed'"), evaluatedWith: app.buttons["profile-jam-subscribe"])
        waitForExpectations(timeout: 8)
        app.showProfileArticles()   // Sam's articles
        XCTAssertTrue(app.buttons["jam-post-demo-post-1"].waitForExistence(timeout: 8), "their posts are on the page now")
    }

    func testMyProfileShowsMyPostsWhoFollowsAndEditJamPageAndTheWriterCanRemoveSomeone() {
        let app = launch("jam-mine-profile")
        XCTAssertTrue(app.buttons["profile-tab-Orgs"].waitForExistence(timeout: 10))
        app.buttons["profile-tab-Orgs"].tap()
        any(app, "profile-org-demo-my-jam").tap()
        XCTAssertTrue(app.buttons["jam-edit-page"].waitForExistence(timeout: 10))
        XCTAssertEqual(any(app, "profile-jam-subscribers").label, "2 subscribers")
        XCTAssertFalse(app.buttons["profile-jam-subscribe"].exists || app.buttons["profile-org-page-subscribe"].exists, "no Subscribe on my own page")
        any(app, "profile-jam-subscribers").tap()   // the owner taps the count for the list
        XCTAssertTrue(app.buttons["jam-remove-sam"].waitForExistence(timeout: 8))
        app.buttons["jam-remove-sam"].tap()
        app.buttons["jam-remove-confirm"].tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.buttons["jam-remove-sam"])
        waitForExpectations(timeout: 8)
        XCTAssertTrue(app.buttons["jam-remove-lee"].exists)
    }

    // MARK: LIME-188f

    func testTheArticlePageHasPostAsExitArticleAndAVideoInTheTextAndACoauthor() {
        let app = launch("jam")
        app.buttons["new-jam-post"].tap()
        XCTAssertEqual(app.buttons["jam-post-as"].label, "Posting as \(app.buttons["jam-post-as"].label.dropFirst("Posting as ".count))", "the chooser names who it is")
        XCTAssertTrue(app.buttons["jam-post-as"].label.hasPrefix("Posting as "))
        app.buttons["jam-write-article"].tap()
        XCTAssertEqual(app.buttons["jam-exit-article"].label, "Exit article mode")
        XCTAssertTrue(app.buttons["jam-post-as"].exists, "also in article mode")
        let title = app.textFields["jam-article-title"].exists ? app.textFields["jam-article-title"] : app.textViews["jam-article-title"]
        title.tap(); title.typeText("What is liming?")
        title.typeText("\n")
        app.typeText("\n")   // past the subtitle, into the body
        let body = app.textViews["composer-field"]
        expectation(for: NSPredicate(format: "hasKeyboardFocus == true"), evaluatedWith: body)
        waitForExpectations(timeout: 5)
        body.typeText("Start of the article\n\n")
        addArticlePhoto(app)
        app.buttons["jam-add"].tap(); app.buttons["Video"].tap(); app.buttons["Record video"].tap()   // in an article the camera item takes a video (demo: a made-up clip)
        sleep(1)
        // A co-author.
        app.buttons["jam-add-coauthor"].tap()
        let sam = app.buttons["jam-coauthor-choice-sam"]
        XCTAssertTrue(sam.waitForExistence(timeout: 5))
        sam.tap()
        app.buttons["jam-coauthor-done"].tap()
        XCTAssertTrue(app.buttons["jam-coauthors"].waitForExistence(timeout: 5), "the co-author's avatar on the name line")
        app.buttons["jam-post"].tap()
        app.showJamArticles()
        let article = card(app, containing: "What is liming?")
        XCTAssertTrue(article.waitForExistence(timeout: 8))
        XCTAssertTrue(any(app, "jam-card-byline-\(article.identifier.dropFirst("jam-post-".count))").label.contains("with Sam Park"), "the card says who it is with")
        article.tap()
        XCTAssertTrue(any(app, "jam-inline-0").waitForExistence(timeout: 8), "the photo in place")
        // The video stands in the text after the photo: its card (a mute button) is on the page.
        for _ in 0..<4 where !app.buttons["jam-video-mute"].exists { app.swipeUp() }
        XCTAssertTrue(app.buttons["jam-video-mute"].waitForExistence(timeout: 8), "and the video, in place after the photo")
    }

    func testARequestToBeCreditedIsACalmPromptThatAcceptOrDeclineClears() {
        let app = launch("jam-request")
        let prompt = any(app, "jam-request-demo-request-post")
        XCTAssertTrue(prompt.waitForExistence(timeout: 10))
        XCTAssertTrue(prompt.label.contains("added you as co-author of") && prompt.label.contains("What is liming?"), prompt.label)
        app.buttons["jam-request-accept-demo-request-post"].tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: prompt)
        waitForExpectations(timeout: 5)
    }
}
