import XCTest

/// LIME-195: edit or delete a post you published (demo).
@MainActor
final class Jam195UITests: LimeUITestCase {
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "jam-mine"]
        app.launch()
        return app
    }

    private func openMyArticle(_ app: XCUIApplication) {
        app.showJamArticles()
        let card = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Our first circle'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10)); card.tap()
        XCTAssertTrue(app.buttons["jam-article-more"].waitForExistence(timeout: 8))
    }

    func testEditFromTheMenuOpensTheEditorFilledInAndUpdateShowsTheChangeAndEdited() {
        let app = launch()
        openMyArticle(app)
        app.buttons["jam-article-more"].tap()
        XCTAssertTrue(app.buttons["options-edit"].waitForExistence(timeout: 5), "Edit is first in the writer's menu")
        app.buttons["options-edit"].tap()
        let title = app.textFields["jam-article-title"].exists ? app.textFields["jam-article-title"] : app.textViews["jam-article-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 8))
        XCTAssertEqual(title.value as? String, "Our first circle", "prefilled")
        let body = app.textViews["composer-field"]
        XCTAssertTrue(body.waitForExistence(timeout: 5))
        expectation(for: NSPredicate(format: "value CONTAINS 'aloud'"), evaluatedWith: body)
        waitForExpectations(timeout: 8)
        title.tap(); title.typeText(" again")
        XCTAssertTrue(app.buttons["jam-next"].isEnabled)
        postNow(app, id: "jam-update")
        XCTAssertTrue(app.staticTexts["jam-reader-title"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["jam-reader-title"].label.contains("again"), app.staticTexts["jam-reader-title"].label)
        XCTAssertTrue(app.buttons["jam-article-dates"].label.contains("edited"), app.buttons["jam-article-dates"].label)
    }

    func testDeleteAsksFirstAndTheArticleDisappears() {
        let app = launch()
        openMyArticle(app)
        app.buttons["jam-article-more"].tap()
        let delete = app.buttons["options-delete"]
        for _ in 0..<4 where !delete.exists || !delete.isHittable { app.swipeUp() }
        delete.tap()
        app.buttons["options-delete-confirm"].firstMatch.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Our first circle'")).firstMatch.waitForNonExistence(timeout: 8), "gone from the feed")
    }
}
