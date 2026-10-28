import XCTest

/// LIME-240: posting in two steps (demo): write, then "Before you post" / "Before you publish".
@MainActor
final class Post240UITests: LimeUITestCase {
    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    private func launch(_ screen: String = "jam-mine", _ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", screen] + extra
        app.launch()
        return app
    }

    func testAQuickPostGoesNextToBeforeYouPostWithAudienceAndTagsThenPost() {
        let app = launch("jam-mine", ["-lime-demo-open"])
        XCTAssertTrue(app.buttons["new-jam-post"].waitForExistence(timeout: 10)); app.buttons["new-jam-post"].tap()
        let next = app.buttons["jam-next"]
        XCTAssertTrue(next.waitForExistence(timeout: 8))
        XCTAssertTrue(app.navigationBars["Step 1 of 2"].exists, "step 1 is titled as a pair with step 2")
        XCTAssertFalse(next.isEnabled, "nothing to post yet")
        XCTAssertFalse(any(app, "jam-audience").exists || any(app, "jam-topics").exists || any(app, "jam-series").exists, "step 1 is writing only")
        let body = app.textViews["composer-field"]
        body.tap(); body.typeText("Step by step")
        XCTAssertTrue(next.isEnabled)
        next.tap()
        XCTAssertTrue(app.navigationBars["Step 2 of 2"].waitForExistence(timeout: 8), "the step title (LIME-242)")
        XCTAssertTrue(any(app, "jam-audience").exists && any(app, "jam-topics").exists)
        XCTAssertFalse(any(app, "jam-series").exists, "a post has no series")
        XCTAssertEqual(any(app, "before-summary").label, "Step by step")
        XCTAssertEqual(app.buttons["jam-post"].label, "Post")
        // Back keeps the text.
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue((app.textViews["composer-field"].value as? String ?? "").contains("Step by step"))
        app.buttons["jam-next"].tap()
        app.buttons["jam-post"].tap()
        XCTAssertTrue(app.buttons["new-jam-post"].waitForExistence(timeout: 10), "posted, back on the feed")
    }

    func testAnArticleGoesNextToBeforeYouPublishWithSeriesAudienceAndTagsThenPublish() {
        let app = launch("jam-mine", ["-lime-demo-open"])
        XCTAssertTrue(app.buttons["new-jam-post"].waitForExistence(timeout: 10)); app.buttons["new-jam-post"].tap()
        app.buttons["jam-write-article"].tap()
        let title = app.textFields["jam-article-title"].exists ? app.textFields["jam-article-title"] : app.textViews["jam-article-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["jam-next"].isEnabled)
        title.tap(); title.typeText("Wholes\n\n")
        let body = app.textViews["composer-field"]
        body.tap(); body.typeText("And parts")
        app.buttons["jam-next"].tap()
        XCTAssertTrue(app.navigationBars["Step 2 of 2"].waitForExistence(timeout: 8))
        for id in ["jam-series", "jam-audience", "jam-topics"] { XCTAssertTrue(any(app, id).exists, id) }
        XCTAssertEqual(app.buttons["jam-post"].label, "Publish")
        app.buttons["jam-post"].tap()
        // An article opens on its own page when it has gone (LIME-243).
        XCTAssertTrue(any(app, "jam-reader-title").waitForExistence(timeout: 12), "landed on the new article")
    }

    func testEveryoneWithAPhotoAsksForTheConfirmationOnStepTwo() {
        let app = launch("jam-mine", ["-lime-demo-open", "-lime-demo-compose-photo"])
        XCTAssertTrue(app.buttons["new-jam-post"].waitForExistence(timeout: 10)); app.buttons["new-jam-post"].tap()
        app.buttons["jam-next"].tap()
        any(app, "jam-audience").tap(); any(app, "audience-everyone").tap(); any(app, "audience-confirm-everyone").tap()
        XCTAssertTrue(any(app, "privacy-notice").waitForExistence(timeout: 5), "the student-privacy confirmation is on step 2")
        XCTAssertFalse(app.buttons["jam-post"].isEnabled)
        any(app, "privacy-confirm").tap()
        XCTAssertTrue(app.buttons["jam-post"].isEnabled)
    }

    func testEditsStepTwoSaysUpdate() {
        let app = launch("jam-mine")
        let more = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'card-more-'")).firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 10)); more.tap()
        app.buttons["Edit"].tap()
        XCTAssertTrue(app.buttons["jam-next"].waitForExistence(timeout: 10))
        app.buttons["jam-next"].tap()
        XCTAssertTrue(app.buttons["jam-update"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.buttons["jam-update"].label, "Update")
    }
}
