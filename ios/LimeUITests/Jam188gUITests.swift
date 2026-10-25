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
        XCTAssertFalse(app.buttons["podcast-post"].isEnabled, "no Post without a take and a title")
        app.buttons["podcast-record"].tap()
        XCTAssertTrue(app.buttons["podcast-stop"].waitForExistence(timeout: 5))
        app.buttons["podcast-pause"].tap()
        XCTAssertEqual(app.buttons["podcast-pause"].label, "Resume recording")
        app.buttons["podcast-pause"].tap()
        sleep(2)
        XCTAssertNotEqual(any(app, "podcast-time").label, "0:00", "the timer runs")
        app.buttons["podcast-stop"].tap()
        XCTAssertTrue(app.buttons["podcast-post"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["podcast-post"].isEnabled, "a take but no title yet")
        app.textFields["podcast-title"].tap(); app.textFields["podcast-title"].typeText("Sunday planning")
        XCTAssertTrue(app.buttons["podcast-post"].isEnabled, "a take and a title: Post (lime)")
        any(app, "podcast-audio-layer").tap()   // a tap on the stage puts the keyboard away
        XCTAssertTrue(app.buttons["podcast-again"].exists, "Re-record beside it")
        app.buttons["podcast-hosts"].tap()
        let sam = app.buttons["jam-coauthor-choice-sam"]
        XCTAssertTrue(sam.waitForExistence(timeout: 5), "co-hosts come from your contacts")
        sam.tap()
        app.buttons["jam-coauthor-done"].tap()
        app.buttons["podcast-post"].tap()   // the studio's own Post (LIME-227): no second screen
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Sunday planning'")).firstMatch.waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'jam-audio-card-'")).firstMatch.waitForExistence(timeout: 5), "the recording is a card with a play button")
    }

    func testTheCameraButtonSwitchesTheScreenToThePreviewAndBack() {
        let app = launch("jam")
        app.buttons["new-jam-post"].tap()
        app.buttons["jam-record"].tap()
        XCTAssertTrue(any(app, "podcast-audio-layer").waitForExistence(timeout: 8))
        app.buttons["podcast-camera"].tap()
        XCTAssertTrue(any(app, "podcast-camera-layer").waitForExistence(timeout: 5))
        XCTAssertFalse(any(app, "podcast-audio-layer").exists, "the camera takes the stage in place of the cover")
        XCTAssertTrue(app.buttons["podcast-flip"].exists)
        app.buttons["podcast-camera"].tap()
        XCTAssertTrue(any(app, "podcast-audio-layer").waitForExistence(timeout: 5), "camera off: your picture again")
    }
}
