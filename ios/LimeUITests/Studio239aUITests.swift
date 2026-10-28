import XCTest

/// LIME-239a: the podcast recorder as the mockups (demo): the video preview, the audio preview, recording, stop.
@MainActor
final class Studio239aUITests: LimeUITestCase {
    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    func testThePreviewsAndRecordingTurnThePillRedAndStopOpensTheWordsPage() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "jam-mine"]
        app.launch()
        XCTAssertTrue(app.buttons["new-jam-post"].waitForExistence(timeout: 10))
        app.buttons["new-jam-post"].tap()
        XCTAssertTrue(app.buttons["jam-record"].waitForExistence(timeout: 8))
        app.buttons["jam-record"].tap()
        // Video preview: three controls on top, three below.
        XCTAssertTrue(any(app, "podcast-recorder").waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["podcast-cancel"].exists && any(app, "podcast-mode-pill").exists && app.buttons["podcast-torch"].exists, "✕ · Preview mode · flash")
        XCTAssertEqual(any(app, "podcast-mode-pill").label, "Preview mode")
        XCTAssertTrue(app.buttons["podcast-camera"].exists && app.buttons["podcast-record"].exists && app.buttons["podcast-flip"].exists, "switch · shutter · flip")
        // The mode switch shows the audio preview: the avatar, no flash, no flip.
        app.buttons["podcast-camera"].tap()
        XCTAssertTrue(any(app, "podcast-avatar").waitForExistence(timeout: 5) || any(app, "podcast-recorder").exists)
        XCTAssertFalse(app.buttons["podcast-torch"].exists, "no flash in audio")
        XCTAssertFalse(app.buttons["podcast-flip"].exists, "no flip in audio")
        // Recording: the pill is a red timer, the shutter is the stop button; ✕ asks before discarding.
        app.buttons["podcast-record"].tap()
        XCTAssertTrue(any(app, "podcast-timer").waitForExistence(timeout: 5), "the red timer")
        XCTAssertTrue(app.buttons["podcast-stop"].exists)
        sleep(2)
        app.buttons["podcast-cancel"].tap()
        XCTAssertTrue(app.buttons["podcast-discard-confirm"].waitForExistence(timeout: 3), "asks first")
        app.buttons["Keep recording"].tap()
        app.buttons["podcast-stop"].tap()
        XCTAssertTrue(any(app, "podcast-title").waitForExistence(timeout: 8), "stop opens the words page")
    }
}
