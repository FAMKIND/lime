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
        XCTAssertEqual(any(app, "jam-audio-length").label, "Length 18 minutes")
        // LIME-188u: the card has the waveform to scrub and a mute button.
        let wave = any(app, "podcast-scrubber-demo-audio-1")
        XCTAssertTrue(wave.exists)
        for _ in 0..<4 where !wave.isHittable || wave.frame.maxY > app.windows.firstMatch.frame.height - 140 { app.swipeUp() }
        XCTAssertEqual(wave.label, "Position")
        XCTAssertTrue((wave.value as? String ?? "").hasPrefix("0 seconds of 18 minutes"))
        wave.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue((wave.value as? String ?? "").hasPrefix("9 minutes"), "tapping the wave scrubs: \(wave.value as? String ?? "")")
        let mute = app.buttons["jam-audio-mute-demo-audio-1"]
        XCTAssertEqual(mute.label, "Mute")
        mute.tap()
        XCTAssertEqual(mute.label, "Unmute")
        mute.tap()
        XCTAssertTrue(any(app, "jam-audio-title").exists, "the title and subtitle are on the card")
        XCTAssertFalse(app.buttons["audio-mini-open"].exists, "no mini player before playing")
        app.buttons["jam-audio-play-demo-audio-1"].tap()
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
