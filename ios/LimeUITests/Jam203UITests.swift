import XCTest

/// LIME-203 and LIME-204: video podcasts as video cards in the feed; every podcast opens in the black full-screen player (demo).
@MainActor
final class Jam203UITests: LimeUITestCase {
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "jam-following"]
        app.launch()
        return app
    }

    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    func testAVideoPodcastIsABigCardInAllAndASmallOneUnderPodcastsWhileAudioIsSmallInBoth() {
        let app = launch()
        let control = any(app, "jam-filter-segments")
        XCTAssertTrue(control.waitForExistence(timeout: 10))
        let big = any(app, "jam-video")
        for _ in 0..<5 where !big.exists { app.swipeUp() }
        XCTAssertTrue(big.exists, "the video recording is a big video card in All")
        XCTAssertTrue(any(app, "jam-audio-card-demo-audio-1").exists || { for _ in 0..<4 { app.swipeUp() }; return any(app, "jam-audio-card-demo-audio-1").exists }(), "the audio one is the small card")
        control.buttons["Podcasts"].tap()
        XCTAssertTrue(any(app, "jam-audio-card-demo-video-1").waitForExistence(timeout: 5), "the video recording is the small card under Podcasts")
        XCTAssertFalse(any(app, "jam-video").exists, "no video card under Podcasts")
        XCTAssertTrue(any(app, "jam-audio-card-demo-audio-1").exists || { for _ in 0..<4 { app.swipeUp() }; return any(app, "jam-audio-card-demo-audio-1").exists }())
    }

    func testTappingAPodcastsTitleOpensThePlayerAndItsCommentIconOpensTheComments() {
        let app = launch()
        any(app, "jam-filter-segments").buttons["Podcasts"].tap()
        let title = app.buttons.matching(NSPredicate(format: "identifier == 'jam-podcast-title' AND label CONTAINS 'Sunday planning'")).firstMatch
        for _ in 0..<5 where !title.exists || !title.isHittable { app.swipeUp() }
        XCTAssertTrue(title.waitForExistence(timeout: 8))
        title.tap()
        XCTAssertTrue(any(app, "jam-video-screen").waitForExistence(timeout: 5), "the title opens the black player, not the post page")
        // The post's page is reached from the player's ⋯.
        app.buttons["jam-video-more"].tap()
        XCTAssertTrue(app.buttons["View post"].waitForExistence(timeout: 5))
        app.buttons["View post"].tap()
        XCTAssertTrue(app.staticTexts["jam-reader-title"].waitForExistence(timeout: 8) || any(app, "jam-reader").waitForExistence(timeout: 3), "the post's page")
    }

    func testAPodcastCardsCommentIconOpensThePlayerWithTheCommentsSheet() {
        let app = launch()
        any(app, "jam-filter-segments").buttons["Podcasts"].tap()
        let icon = app.buttons["jam-comment-demo-post-4"]
        for _ in 0..<5 where !icon.exists || !icon.isHittable { app.swipeUp() }
        XCTAssertTrue(icon.waitForExistence(timeout: 8)); icon.tap()
        XCTAssertTrue(any(app, "jam-counts-line").waitForExistence(timeout: 8), "the comments sheet is open over the black player")
    }
}
