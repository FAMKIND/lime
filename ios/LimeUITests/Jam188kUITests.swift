import XCTest

/// LIME-188k: a recording is a card with a cover, play and length; playing shows the mini player; it opens in a now-playing screen.
@MainActor
final class Jam188kUITests: LimeUITestCase {
    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    func testAnAudioPostIsACardThatPlaysInTheMiniPlayerAndOpensNowPlaying() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "jam-following"]
        app.launch()
        let card = any(app, "jam-audio-card-demo-audio-1")
        for _ in 0..<6 where !card.exists { app.swipeUp() }
        XCTAssertTrue(card.waitForExistence(timeout: 10), "the recording is a card")
        XCTAssertFalse(app.buttons["audio-mini-open"].exists, "no mini player before playing")
        app.buttons["jam-audio-play-demo-audio-1"].tap()
        // LIME-200: pressing play on the card opens the full-screen player; closing it leaves the mini player.
        XCTAssertTrue(any(app, "jam-video-screen").waitForExistence(timeout: 5))
        app.buttons["jam-video-close"].tap()
        XCTAssertTrue(app.buttons["audio-mini-open"].waitForExistence(timeout: 5), "playing shows the mini player")
        XCTAssertTrue(app.buttons["audio-mini-open"].label.contains("Sunday planning"))
        // The mini player stays across tabs.
        app.buttons["link"].tap()
        XCTAssertTrue(app.buttons["audio-mini-open"].waitForExistence(timeout: 5), "and on another tab")
        app.buttons["audio-mini-open"].tap()
        XCTAssertTrue(any(app, "jam-video-screen").waitForExistence(timeout: 5), "tapping it opens the now-playing screen")
        XCTAssertTrue(any(app, "jam-audio-cover").exists)
        let elapsed = any(app, "jam-video-elapsed")
        let before = elapsed.label
        app.buttons["jam-video-fwd10"].tap()
        XCTAssertNotEqual(elapsed.label, before, "+10 s moves the position")
        app.buttons["jam-video-back10"].tap()
        app.buttons["jam-video-speed"].tap()
        app.buttons["jam-video-close"].tap()
        XCTAssertTrue(app.buttons["audio-mini-open"].waitForExistence(timeout: 5), "closing the screen keeps playing")
        app.buttons["audio-mini-close"].tap()
        XCTAssertFalse(app.buttons["audio-mini-open"].waitForExistence(timeout: 2), "close stops it")
    }
}
