import XCTest

/// LIME-188g: Record is a podcast: the dark recorder (audio by default, a camera toggle), co-hosts, and a player with a waveform to scrub.
@MainActor
final class Jam188gUITests: LimeUITestCase {
    private func launch(_ screen: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat"] + (screen.map { ["-lime-demo-screen", $0] } ?? [])
        app.launch()
        return app
    }

    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    func testARecordingGetsATitleAndCoHostsThenPostsAsAPodcast() {
        let app = launch("jam")
        app.buttons["new-jam-post"].tap()
        app.buttons["jam-record"].tap()
        XCTAssertTrue(any(app, "podcast-audio-layer").waitForExistence(timeout: 8), "audio first: your picture and the sound")
        XCTAssertEqual(any(app, "podcast-sharing").label, "Shared with your subscribers")
        XCTAssertFalse(app.buttons["podcast-next"].isEnabled)
        app.buttons["podcast-record"].tap()
        XCTAssertTrue(app.buttons["podcast-stop"].waitForExistence(timeout: 5))
        app.buttons["podcast-pause"].tap()
        XCTAssertEqual(app.buttons["podcast-pause"].label, "Resume recording")
        app.buttons["podcast-pause"].tap()
        sleep(2)
        XCTAssertNotEqual(any(app, "podcast-time").label, "0:00", "the timer runs")
        app.buttons["podcast-stop"].tap()
        XCTAssertTrue(app.buttons["podcast-next"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["podcast-next"].isEnabled)
        app.textFields["podcast-title"].tap(); app.textFields["podcast-title"].typeText("Sunday planning")
        app.buttons["podcast-next"].tap()
        let sam = app.buttons["jam-coauthor-choice-sam"]
        XCTAssertTrue(sam.waitForExistence(timeout: 5), "co-hosts come from your contacts")
        sam.tap()
        app.buttons["jam-coauthor-done"].tap()
        XCTAssertTrue(app.buttons["jam-recorded-0"].waitForExistence(timeout: 5), "the recording is attached")
        XCTAssertTrue(app.buttons["jam-coauthor-sam"].exists, "and the co-host is asked")
        app.buttons["jam-post"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Sunday planning'")).firstMatch.waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'podcast-play-'")).firstMatch.waitForExistence(timeout: 5), "the player sits in the card")
    }

    func testTheCameraButtonSwitchesTheScreenToThePreviewAndBack() {
        let app = launch("jam")
        app.buttons["new-jam-post"].tap()
        app.buttons["jam-record"].tap()
        XCTAssertTrue(any(app, "podcast-audio-layer").waitForExistence(timeout: 8))
        app.buttons["podcast-camera"].tap()
        XCTAssertTrue(any(app, "podcast-camera-layer").waitForExistence(timeout: 5))
        XCTAssertFalse(any(app, "podcast-audio-layer").exists, "the preview takes the whole screen")
        XCTAssertTrue(app.buttons["podcast-flip"].exists)
        app.buttons["podcast-camera"].tap()
        XCTAssertTrue(any(app, "podcast-audio-layer").waitForExistence(timeout: 5), "camera off: your picture again")
    }

    func testThePlayerScrubsSkipsAndChangesSpeed() {
        let app = launch("jam-following")
        let scrubber = any(app, "podcast-scrubber-demo-audio-1")
        for _ in 0..<6 where !scrubber.exists || !scrubber.isHittable { app.swipeUp() }
        XCTAssertTrue(scrubber.waitForExistence(timeout: 8))
        XCTAssertEqual(scrubber.label, "Position")
        XCTAssertTrue((scrubber.value as? String ?? "").hasPrefix("0 seconds of 18 minutes"))
        let elapsed = any(app, "podcast-elapsed-demo-audio-1")
        app.buttons["podcast-skip-30-demo-audio-1"].tap()
        XCTAssertEqual(elapsed.label, "0:30")
        app.buttons["podcast-skip--15-demo-audio-1"].tap()
        XCTAssertEqual(elapsed.label, "0:15")
        scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(elapsed.label.hasPrefix("9:0"), "dragging or tapping the waveform moves the position")
        XCTAssertTrue((scrubber.value as? String ?? "").hasPrefix("9 minutes"))
        app.buttons["podcast-speed-demo-audio-1"].tap()
        XCTAssertEqual(app.buttons["podcast-speed-demo-audio-1"].label, "Playback speed 1.5")
        app.buttons["podcast-play-demo-audio-1"].tap()
        XCTAssertEqual(app.buttons["podcast-play-demo-audio-1"].label, "Pause")
    }
}
