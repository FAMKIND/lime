import XCTest

/// LIME-212b: podcast cards look like jam's other cards (demo).
@MainActor
final class Jam212bUITests: LimeUITestCase {
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "jam-following"]
        app.launch()
        return app
    }

    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    func testTheBigVideoCardStartsWithTheWriterRowThenTheTitleThenTheVideo() {
        let app = launch()
        let video = any(app, "jam-video")
        for _ in 0..<6 where !video.exists { app.swipeUp() }
        XCTAssertTrue(video.waitForExistence(timeout: 8))
        let writer = any(app, "jam-card-writer-demo-post-3")
        XCTAssertTrue(writer.exists, "the writer row, like the post cards")
        let title = app.staticTexts.matching(NSPredicate(format: "identifier == 'jam-podcast-title' AND label CONTAINS 'fraction walls'")).firstMatch
        XCTAssertTrue(title.exists)
        XCTAssertLessThan(writer.frame.minY, title.frame.minY, "the row, then the title")
        XCTAssertLessThan(title.frame.minY, video.frame.minY, "then the video")
    }

    func testEveryCardHasTheSameActionRowAndRemixAndShareAreDisabled() {
        let app = launch()
        any(app, "jam-filter-segments").buttons["Podcasts"].tap()
        let like = app.buttons["jam-like-demo-post-4"]
        for _ in 0..<5 where !like.exists || !like.isHittable { app.swipeUp() }
        XCTAssertTrue(like.waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["jam-comment-demo-post-4"].exists)
        let remix = app.buttons["jam-action-remix-demo-post-4"], share = app.buttons["jam-action-share-demo-post-4"]
        XCTAssertTrue(remix.exists && share.exists)
        XCTAssertFalse(remix.isEnabled || share.isEnabled, "disabled until they exist")
        XCTAssertLessThan(like.frame.minX, remix.frame.minX)
        XCTAssertLessThan(remix.frame.minX, share.frame.minX, "spread across, in order")
    }

    func testThePodcastEditPageShowsTheCoHostsControl() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "jam-mine-podcast"]
        app.launch()
        any(app, "jam-filter-segments").buttons["Podcasts"].tap()
        let more = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'card-more-'")).firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 10)); more.tap()
        app.buttons["Edit"].tap()
        XCTAssertTrue(app.buttons["podcast-hosts"].waitForExistence(timeout: 8))
    }
}
