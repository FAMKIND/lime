import XCTest

/// LIME-273: a band's writer sends an article for review; the owner sees it waiting (demo).
@MainActor
final class Review273UITests: LimeUITestCase {
    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    func testAWriterOfABandSendsAnArticleForReviewInsteadOfPublishing() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "jam-mine", "-lime-demo-review-writer"]
        app.launch()
        XCTAssertTrue(app.buttons["new-jam-post"].waitForExistence(timeout: 10))
        app.buttons["new-jam-post"].tap()
        XCTAssertTrue(app.buttons["jam-write-article"].waitForExistence(timeout: 8))
        app.buttons["jam-write-article"].tap()
        let title = app.textFields["jam-article-title"].exists ? app.textFields["jam-article-title"] : app.textViews["jam-article-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 8))
        title.tap(); title.typeText("Seed swap\n")
        // Return in the subtitle does not always move on to the body: tap it.
        let body = app.textViews["composer-field"]
        XCTAssertTrue(body.waitForExistence(timeout: 5))
        body.tap()
        body.typeText("Bring packets of seeds.")
        app.buttons["jam-post-as"].tap()
        let band = app.buttons["jam-post-as-review-demo-band-writer"]
        XCTAssertTrue(band.waitForExistence(timeout: 5), "a band I write for is offered, marked for review")
        band.tap()
        XCTAssertTrue(app.buttons["jam-send-for-review"].waitForExistence(timeout: 5), "the button says what happens")
        XCTAssertFalse(app.buttons["jam-next"].exists, "not Next: nothing is published by a writer")
        app.buttons["jam-send-for-review"].tap()
        XCTAssertTrue(app.alerts["Sent for review"].waitForExistence(timeout: 8), "told it went to the owners")
    }

    func testAnOwnersBandPageShowsWhatIsWaitingForReview() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "jam-mine-profile", "-lime-demo-band-people", "-lime-demo-review-owner"]
        app.launch()
        XCTAssertTrue(app.buttons["profile-tab-Orgs"].waitForExistence(timeout: 10))
        app.buttons["profile-tab-Orgs"].tap()
        any(app, "profile-org-demo-band-demo-my-jam").tap()
        let waiting = any(app, "org-waiting-review")
        XCTAssertTrue(waiting.waitForExistence(timeout: 10), "owners see what is waiting")
        XCTAssertTrue(waiting.label.contains("1"), waiting.label)
        waiting.tap()
        XCTAssertTrue(any(app, "review-item-demo-review-1").waitForExistence(timeout: 5), "the draft is listed")
    }
}
