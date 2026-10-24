import XCTest

/// LIME-222: Subscribe at the top right of another jam's article; a short date line whose tap shows the full times.
@MainActor
final class Jam222UITests: LimeUITestCase {
    private func launch(_ screen: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", screen]
        app.launch()
        return app
    }

    func testAnotherJamsArticleHasSubscribeBesideMoreAndTheDateLineIsShort() {
        let app = launch("jam-following")
        app.showJamArticles()
        let card = app.buttons["jam-post-demo-post-1"]
        XCTAssertTrue(card.waitForExistence(timeout: 10)); card.tap()
        let subscribe = app.buttons["jam-article-subscribe"]
        XCTAssertTrue(subscribe.waitForExistence(timeout: 8))
        XCTAssertLessThan(subscribe.frame.maxX, app.buttons["jam-article-more"].frame.minX + 1, "left of the ⋯")
        XCTAssertTrue(subscribe.label.hasPrefix("Subscribed"), "Sam's jam is followed here: \(subscribe.label)")
        let dates = app.buttons["jam-article-dates"]
        XCTAssertTrue(dates.waitForExistence(timeout: 5))
        XCTAssertTrue(dates.label.contains("minute read"), dates.label)
        XCTAssertFalse(dates.label.contains(" at ") || dates.label.contains("AM") || dates.label.contains("PM"), "no clock time: \(dates.label)")
        dates.tap()
        XCTAssertTrue(app.staticTexts["jam-article-published"].waitForExistence(timeout: 5), "the full times")
        XCTAssertTrue(app.staticTexts["jam-article-published"].label.hasPrefix("Published "))
    }

    func testYourOwnArticleHasNoSubscribe() {
        let app = launch("jam-mine-asjam")
        app.showJamArticles()
        let card = app.buttons.matching(NSPredicate(format: "label CONTAINS 'How we read together'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10)); card.tap()
        XCTAssertTrue(app.buttons["jam-article-more"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["jam-article-subscribe"].exists)
    }
}
