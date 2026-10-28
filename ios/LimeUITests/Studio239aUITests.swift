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
        XCTAssertTrue(app.buttons["podcast-cancel"].exists && any(app, "podcast-mode").exists && app.buttons["podcast-torch"].exists, "✕ · audio | video · flash")
        XCTAssertFalse(any(app, "podcast-mode-pill").exists || app.staticTexts["Preview mode"].exists, "no Preview mode (LIME-241)")
        XCTAssertTrue(any(app, "podcast-mic").exists && app.buttons["podcast-record"].exists && app.buttons["podcast-flip"].exists, "mic · shutter · flip")
        // The toggle is in the top centre; the audio side shows the avatar, no flash, no flip.
        let window = app.windows.firstMatch.frame
        XCTAssertEqual(any(app, "podcast-mode").frame.midX, window.midX, accuracy: 3, "centred")
        XCTAssertLessThan(any(app, "podcast-mode").frame.minY, 120, "at the top")
        app.segmentedControls["podcast-mode"].buttons["Audio"].tap()
        XCTAssertTrue(any(app, "podcast-avatar").waitForExistence(timeout: 5) || any(app, "podcast-recorder").exists)
        XCTAssertFalse(app.buttons["podcast-torch"].exists, "no flash in audio")
        XCTAssertFalse(app.buttons["podcast-flip"].exists, "no flip in audio")
        // Recording: the pill is a red timer, the shutter is the stop button; ✕ asks before discarding.
        app.buttons["podcast-record"].tap()
        XCTAssertTrue(any(app, "podcast-timer").waitForExistence(timeout: 5), "the red timer")
        XCTAssertGreaterThan(any(app, "podcast-timer").frame.minY, any(app, "podcast-mode").frame.maxY - 2, "just below the toggle")
        XCTAssertFalse(app.segmentedControls["podcast-mode"].isEnabled, "held still while recording")
        XCTAssertTrue(app.buttons["podcast-stop"].exists)
        sleep(2)
        app.buttons["podcast-cancel"].tap()
        XCTAssertTrue(app.buttons["podcast-discard-confirm"].waitForExistence(timeout: 3), "asks first")
        app.buttons["Keep recording"].tap()
        app.buttons["podcast-stop"].tap()
        XCTAssertTrue(any(app, "podcast-title").waitForExistence(timeout: 8), "stop opens the words page")
    }

    func testTheMicMenuListsTheInputsAndRemembersTheChoice() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "jam-mine"]
        app.launch()
        app.buttons["new-jam-post"].tap(); app.buttons["jam-record"].tap()
        let mic = any(app, "podcast-mic")
        XCTAssertTrue(mic.waitForExistence(timeout: 8))
        XCTAssertTrue(mic.label.hasPrefix("Microphone: "), mic.label)
        mic.tap()
        for name in ["iPhone microphone", "AirPods", "USB microphone"] { XCTAssertTrue(app.buttons[name].waitForExistence(timeout: 3), name) }
        app.buttons["AirPods"].tap()
        XCTAssertEqual(any(app, "podcast-mic").label, "Microphone: AirPods")
        // The choice is remembered on the phone, so put the usual one back for the next run.
        any(app, "podcast-mic").tap(); app.buttons["iPhone microphone"].tap()
        XCTAssertEqual(any(app, "podcast-mic").label, "Microphone: iPhone microphone")
    }
}
