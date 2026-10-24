import XCTest

/// LIME-219: an article's cover can be added, changed and removed in the editor.
@MainActor
final class Jam219UITests: LimeUITestCase {
    private func editMyArticle() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "jam-mine-asjam"]
        app.launch()
        app.showJamArticles()
        let more = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'card-more-'")).firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 10)); more.tap()
        app.buttons["Edit"].firstMatch.tap()
        XCTAssertTrue(app.buttons["jam-cover-change"].waitForExistence(timeout: 10), "Add cover is under the Post as line")
        return app
    }

    func testAddChangeAndRemoveACover() {
        let app = editMyArticle()
        XCTAssertEqual(app.buttons["jam-cover-change"].label, "Add cover")
        XCTAssertFalse(app.buttons["jam-cover-remove"].exists)
        XCTAssertLessThan(app.buttons["jam-post-as"].frame.minY, app.buttons["jam-cover-change"].frame.minY, "under the Post as line")
        XCTAssertLessThan(app.buttons["jam-cover-change"].frame.minY, app.descendants(matching: .any)["jam-article-title"].frame.minY + 1, "above the title")
        app.buttons["jam-cover-change"].tap()
        app.buttons["Choose a photo"].tap()
        let cover = app.buttons["jam-article-cover"]
        XCTAssertTrue(cover.waitForExistence(timeout: 5), "the thumbnail")
        XCTAssertEqual(cover.frame.height, 72, accuracy: 3)
        XCTAssertEqual(app.buttons["jam-cover-change"].label, "Change cover")
        cover.tap()
        XCTAssertTrue(app.descendants(matching: .any)["jam-cover-viewer"].waitForExistence(timeout: 5), "full size")
        app.buttons["jam-cover-close"].tap()
        app.buttons["jam-cover-remove"].tap()
        XCTAssertTrue(cover.waitForNonExistence(timeout: 5))
        XCTAssertEqual(app.buttons["jam-cover-change"].label, "Add cover")
    }

    func testAPhotoFromAnArticleWithNoPhotosSaysSo() {
        let app = editMyArticle()
        app.buttons["jam-cover-change"].tap()
        app.buttons["Use a photo from this article"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["jam-cover-none"].waitForExistence(timeout: 5))
    }
}
