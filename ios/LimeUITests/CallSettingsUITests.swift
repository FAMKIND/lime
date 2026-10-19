import XCTest

/// LIME-169: Settings → Calls.
@MainActor
final class CallSettingsUITests: XCTestCase {
    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    func testTheCallsPageHasThreeControlsEachWithItsLine() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "settings/calls"]
        app.launch()
        let recents = app.switches["calls-recents"]
        XCTAssertTrue(recents.waitForExistence(timeout: 8), "Include in Recents")
        XCTAssertEqual(recents.value as? String, "0", "off by default")
        XCTAssertEqual(app.switches["calls-low-data"].value as? String, "0", "Low Data Mode is off by default")
        XCTAssertTrue(app.staticTexts["Shows lime calls in the Phone app's Recents. Your iPhone may sync that list to iCloud."].exists)
        XCTAssertTrue(app.staticTexts["Uses less data. Video looks softer but holds up better on a weak connection."].exists)
        XCTAssertTrue(app.staticTexts["Changes how loud others sound in lime calls, on top of your phone's volume."].exists)
        // The switches turn on.
        recents.switches.firstMatch.tap()
        XCTAssertEqual(app.switches["calls-recents"].value as? String, "1")
        app.switches["calls-low-data"].switches.firstMatch.tap()
        XCTAssertEqual(app.switches["calls-low-data"].value as? String, "1")
    }

    func testTheVolumeSliderSaysItsPercentageToVoiceOverAndMovesFromHalfToDouble() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "settings/calls"]
        app.launch()
        let slider = app.sliders["calls-volume"]
        XCTAssertTrue(slider.waitForExistence(timeout: 8))
        XCTAssertEqual(slider.value as? String, "100%", "the phone's own volume to start")
        slider.adjust(toNormalizedSliderPosition: 1.0)
        XCTAssertEqual(slider.value as? String, "200%")
        slider.adjust(toNormalizedSliderPosition: 0.0)
        XCTAssertEqual(slider.value as? String, "50%")
        XCTAssertEqual(slider.label, "Call volume")
    }

    func testCallsIsARowInSettings() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "settings"]
        app.launch()
        XCTAssertTrue(app.buttons["settings-calls"].waitForExistence(timeout: 8), "Settings → Calls")
        app.buttons["settings-calls"].tap()
        XCTAssertTrue(app.switches["calls-recents"].waitForExistence(timeout: 5))
    }
}
