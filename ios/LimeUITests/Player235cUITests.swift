import XCTest

/// LIME-235c: pause settles the stage, a long title is one line, landscape layouts (demo).
@MainActor
final class Player235cUITests: LimeUITestCase {
    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    private func openAudioPlayer() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "jam-mine-podcast"]
        app.launch()
        any(app, "jam-filter-segments").buttons["Podcasts"].tap()
        let pill = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'jam-audio-play-'")).firstMatch
        XCTAssertTrue(pill.waitForExistence(timeout: 10)); pill.tap()
        XCTAssertTrue(any(app, "jam-video-screen").waitForExistence(timeout: 8))
        return app
    }

    func testPausingMakesTheCoverSmallerAndPlayingBringsItBack() {
        let app = openAudioPlayer()
        let cover = any(app, "jam-audio-cover")
        XCTAssertTrue(cover.waitForExistence(timeout: 5))
        let play = app.buttons["jam-video-play"]
        if play.label == "Play" { play.tap(); sleep(1) }   // playing
        let playing = cover.frame.width
        XCTAssertGreaterThan(playing, app.windows.firstMatch.frame.width * 0.8, "playing: about 88 % of the width")
        play.tap(); sleep(1)
        XCTAssertEqual(play.label, "Play")
        XCTAssertLessThan(cover.frame.width, playing * 0.9, "paused: it settles back")
        play.tap(); sleep(1)
        XCTAssertEqual(cover.frame.width, playing, accuracy: 6, "playing again: full size")
    }

    func testLandscapeAudioPutsTheCoverOnTheLeftAndTheControlsOnTheRight() {
        let app = openAudioPlayer()
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let cover = any(app, "jam-audio-cover")
        let play = app.buttons["jam-video-play"]
        XCTAssertTrue(play.waitForExistence(timeout: 8))
        sleep(1)
        XCTAssertLessThan(cover.frame.maxX, play.frame.minX, "cover left, controls right: \(cover.frame) \(play.frame)")
        XCTAssertGreaterThan(cover.frame.height, app.windows.firstMatch.frame.height * 0.6, "the cover is as tall as the window allows")
        XCTAssertLessThan(cover.frame.width, app.windows.firstMatch.frame.width * 0.6, "and only the left part of it")
        XCTAssertTrue(app.buttons["jam-video-upnext"].exists, "the bottom row is there")
    }

    func testALongVideoTitleIsOneLineAndLandscapeVideoFillsTheScreenWithGlassControls() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "jam-following"]
        app.launch()
        let card = any(app, "jam-video")
        for _ in 0..<5 where !card.exists { app.swipeUp() }
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.5)).tap()
        XCTAssertTrue(any(app, "jam-video-screen").waitForExistence(timeout: 5))
        let title = app.buttons["jam-video-text"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertLessThan(title.frame.height, 60, "title and subtitle are one line each (a marquee when long)")
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        XCTAssertTrue(app.buttons["jam-fullscreen-close"].waitForExistence(timeout: 10), "landscape Watch is the full-screen layout")
        if !app.buttons["jam-fullscreen-play"].exists { any(app, "jam-fullscreen-video").tap() }
        XCTAssertTrue(app.buttons["jam-fullscreen-play"].waitForExistence(timeout: 3), "glass controls over the video")
        XCTAssertTrue(app.buttons["jam-fullscreen-close"].exists)
        XCTAssertTrue(app.buttons["jam-fullscreen-sound"].exists)
        XCTAssertTrue(app.buttons["jam-fullscreen-listen"].exists, "speed and Listen bottom right")
        XCTAssertTrue(app.buttons["jam-fullscreen-speed"].exists)
        XCTAssertTrue(any(app, "jam-fullscreen-timeline").exists)
    }
}
