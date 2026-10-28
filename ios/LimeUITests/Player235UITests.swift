import XCTest

/// LIME-235: the black player as the mockups (demo): audio and video layouts, Listen/Watch, full screen, Up next.
@MainActor
final class Player235UITests: LimeUITestCase {
    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    func testAnAudioPodcastShowsTheCoverTheControlsAboveTheTitleAndTheBottomBar() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "jam-mine-podcast"]
        app.launch()
        any(app, "jam-filter-segments").buttons["Podcasts"].tap()
        let pill = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'jam-audio-play-'")).firstMatch
        XCTAssertTrue(pill.waitForExistence(timeout: 10)); pill.tap()
        XCTAssertTrue(any(app, "jam-video-screen").waitForExistence(timeout: 8))
        XCTAssertTrue(any(app, "jam-audio-cover").exists, "the cover is the stage")
        let play = app.buttons["jam-video-play"], title = app.buttons["jam-video-text"]
        XCTAssertTrue(play.exists && title.exists)
        for id in ["jam-video-speed", "jam-video-back10", "jam-video-fwd30", "jam-video-captions"] { XCTAssertTrue(app.buttons[id].exists, id) }
        // The same order as a video podcast: the info block, the progress bar, then the controls row.
        let timeline = any(app, "jam-video-timeline")
        XCTAssertTrue(any(app, "jam-info-cover").exists, "the thumbnail beside the details")
        XCTAssertLessThan(title.frame.maxY, timeline.frame.minY + 4, "the info block is above the progress bar")
        XCTAssertLessThan(timeline.frame.maxY, play.frame.minY + 4, "and the controls are under it")
        // The toggle: Listen is on, Watch is dimmed for an audio podcast.
        // An audio podcast has no video: just the waveform, no toggle to operate.
        XCTAssertTrue(any(app, "jam-player-audio-only").exists, "only the waveform")
        XCTAssertFalse(app.segmentedControls["jam-player-mode"].exists, "no Listen | Watch")
        XCTAssertFalse(app.buttons["Watch"].exists)
        // The bottom bar: AirPlay, ♥ 💬 remix share, Up next.
        XCTAssertTrue(any(app, "jam-video-airplay").exists)
        XCTAssertTrue(app.buttons["jam-pill-share"].exists)
        // Tapping the info block opens About: the title, the writer, the description, a close button.
        title.tap()
        XCTAssertTrue(any(app, "jam-about-sheet").waitForExistence(timeout: 5), "the About sheet")
        XCTAssertTrue(any(app, "jam-about-title").exists)
        XCTAssertTrue(any(app, "jam-about-description").exists || any(app, "jam-about-empty").exists, "the description, or No description")
        app.buttons["jam-about-close"].tap()
        XCTAssertFalse(any(app, "jam-about-sheet").waitForExistence(timeout: 2), "closed")
        let upNext = app.buttons["jam-video-upnext"]
        XCTAssertTrue(upNext.exists)
        upNext.tap()
        XCTAssertTrue(any(app, "jam-upnext").waitForExistence(timeout: 5), "Up next opens the queue")
    }

    func testAVideoPodcastShowsTheVideoTheInfoBlockTheVolumeAndATapGoesFullScreen() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "jam-following"]
        app.launch()
        let card = any(app, "jam-video")
        for _ in 0..<5 where !card.exists { app.swipeUp() }
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.5)).tap()
        XCTAssertTrue(any(app, "jam-video-screen").waitForExistence(timeout: 5))
        XCTAssertTrue(any(app, "jam-video-stage").waitForExistence(timeout: 5), "the video is the stage")
        // The info block: the cover on the left, the title (one line) on its right.
        let title = app.buttons["jam-video-text"]
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        XCTAssertLessThan(any(app, "jam-video-stage").frame.maxY, title.frame.minY + 200)
        XCTAssertLessThan(title.frame.height, 50, "title and subtitle are one line each: \(title.frame)")
        // The info block's text fits within the (smaller, 82 pt) cover's height.
        XCTAssertLessThanOrEqual(title.frame.maxY - any(app, "jam-video-stage").frame.maxY, 120, "close under the stage")
        XCTAssertTrue(any(app, "jam-video-volume").exists, "the volume slider")
        XCTAssertFalse(any(app, "jam-audio-cover").exists)
        // A tap on the video: full screen with ✕ and sound.
        any(app, "jam-video-stage").tap()
        XCTAssertTrue(any(app, "jam-fullscreen").waitForExistence(timeout: 5))
        // The video fills the window to every edge (no band at the bottom), and the volume capsule is as high as the ✕ with the slider inside it.
        let window = app.windows.firstMatch.frame
        let picture = any(app, "jam-fullscreen-video").frame
        XCTAssertEqual(picture.height, window.height, accuracy: 1, "reaches the bottom edge: \(picture) vs \(window)")
        XCTAssertEqual(picture.width, window.width, accuracy: 1)
        let volume = any(app, "jam-fullscreen-volume")
        if !volume.exists { any(app, "jam-fullscreen-video").tap() }
        XCTAssertTrue(volume.waitForExistence(timeout: 3))
        XCTAssertEqual(volume.frame.width, 180, accuracy: 2, "a fixed-width capsule")
        XCTAssertEqual(volume.frame.height, app.buttons["jam-fullscreen-close"].frame.height, accuracy: 1, "as high as the ✕")
        XCTAssertLessThanOrEqual(volume.frame.maxX, window.width - 8, "inside the screen")
        XCTAssertTrue(app.buttons["jam-fullscreen-close"].exists)
        XCTAssertTrue(app.buttons["jam-fullscreen-sound"].exists)
        // The controls go after 3 s while it plays; a tap brings them back.
        if !app.buttons["jam-fullscreen-play"].exists { any(app, "jam-fullscreen-video").tap() }
        XCTAssertTrue(app.buttons["jam-fullscreen-play"].waitForExistence(timeout: 3))
        XCTAssertTrue(any(app, "jam-fullscreen-timeline").exists)
        app.buttons["jam-fullscreen-close"].tap()
        XCTAssertTrue(any(app, "jam-video-stage").waitForExistence(timeout: 5), "back at the player")
    }

    /// KNOWN FAILING (rule 12d): in the simulator a tap on the Watch half of the Listen | Watch toggle never reaches the control (Listen's does; the
    /// log shows no change for Watch, with a custom glass toggle and with the system segmented control alike). Not diagnosed; the user checks it on the
    /// phones.
    func testListenPutsTheCoverOnTheStageAndWatchBringsTheVideoBack() throws {
        try XCTSkipIf(true, "known failing (rule 12d): a tap on the Watch half of the toggle does not take effect in the simulator")
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "jam-following"]
        app.launch()
        let card = any(app, "jam-video")
        for _ in 0..<5 where !card.exists { app.swipeUp() }
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.5)).tap()
        XCTAssertTrue(any(app, "jam-video-stage").waitForExistence(timeout: 5))
        // Listen puts the cover on the stage (the sound goes on); Watch brings the video back.
        let mode = app.segmentedControls["jam-player-mode"]
        mode.buttons["Listen"].tap()
        mode.buttons["Watch"].tap()
        XCTAssertFalse(any(app, "jam-audio-cover").exists, "Watch took the cover off the stage")
        let back = any(app, "jam-video-stage").waitForExistence(timeout: 3)
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/player235-b.png"))
        XCTAssertTrue(back, "Watch brings the video back")
    }
}
