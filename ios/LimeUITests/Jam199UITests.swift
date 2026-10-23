import XCTest

/// LIME-199: the ⋯ on every card.
@MainActor
final class Jam199UITests: LimeUITestCase {
    private func launch(_ screen: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", screen]
        app.launch()
        return app
    }

    func testSomeoneElsesCardHasHideAndShareAndNoEdit() {
        let app = launch("jam-following")
        let more = app.buttons["card-more-demo-post-2"]
        XCTAssertTrue(more.waitForExistence(timeout: 10)); more.tap()
        XCTAssertTrue(app.buttons["Hide post"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Share in lime…"].exists && app.buttons["Save"].exists)
        XCTAssertFalse(app.buttons["Edit"].exists || app.buttons["Delete"].exists)
    }

    func testMyCardHasEditAndDeleteAndNoHide() {
        let app = launch("jam-mine")
        let more = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'card-more-'")).firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 10)); more.tap()
        XCTAssertTrue(app.buttons["Edit"].waitForExistence(timeout: 5) && app.buttons["Delete"].exists)
        XCTAssertFalse(app.buttons["Hide post"].exists)
    }

    func testAPodcastsMenuHasThePlaybackItems() {
        let app = launch("jam-following")
        let more = app.buttons["card-more-demo-post-4"]
        for _ in 0..<4 where !more.exists || !more.isHittable { app.swipeUp() }
        XCTAssertTrue(more.waitForExistence(timeout: 8)); more.tap()
        for id in ["Play now", "Play next", "Add to queue", "Mark as played"] { XCTAssertTrue(app.buttons[id].waitForExistence(timeout: 5), id) }
    }
}
