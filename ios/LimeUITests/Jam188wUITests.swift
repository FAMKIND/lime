import XCTest

/// LIME-188w: the article's title pill and the byline avatar.
@MainActor
final class Jam188wUITests: LimeUITestCase {
    private func launch(_ screen: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", screen]
        app.launch()
        return app
    }

    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    private func scrollPastTheHead(_ app: XCUIApplication) {
        for _ in 0..<3 { app.swipeUp(velocity: .slow) }
        app.swipeDown(velocity: .slow)   // the bar comes back when you scroll up
    }

    func testAnArticleByAPersonShowsThePillWithTheirNameOnlyAfterTheHeadScrollsAway() {
        let app = launch("jam-mine-asjam")
        app.showJamArticles()
        let card = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Notes from the circle'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10)); card.tap()
        XCTAssertTrue(any(app, "jam-article-page").waitForExistence(timeout: 8))
        XCTAssertFalse(any(app, "jam-article-pill").exists, "the head shows the title: no pill yet")
        scrollPastTheHead(app)
        let pill = any(app, "jam-article-pill")
        XCTAssertTrue(pill.waitForExistence(timeout: 5))
        XCTAssertEqual(pill.label, "Notes from the circle, by Test Teacher", "their name only")
    }

    func testAnArticleShownAsTheJamHasTheJamAndItsPeopleInThePill() {
        let app = launch("jam-mine-asjam")
        app.showJamArticles()
        let card = app.buttons.matching(NSPredicate(format: "label CONTAINS 'How we read together'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10)); card.tap()
        XCTAssertTrue(any(app, "jam-article-page").waitForExistence(timeout: 8))
        scrollPastTheHead(app)
        let pill = any(app, "jam-article-pill")
        XCTAssertTrue(pill.waitForExistence(timeout: 5))
        XCTAssertTrue(pill.label.hasPrefix("How we read together, by Reading circles \u{00B7} "), pill.label)
        XCTAssertTrue(pill.label.contains("Sam Park") && pill.label.contains("Lee Wong"), pill.label)
        pill.tap()
        XCTAssertTrue(app.buttons["Reading circles"].waitForExistence(timeout: 5), "several people: a small menu, the jam first")
    }
}
