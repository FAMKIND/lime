import XCTest

/// LIME-142 (Debug builds): the "Help pass on nearby messages" switch in Settings → Privacy: on by default, with its one line.
final class MeshSettingsUITests: LimeUITestCase {
    func testTheHelpPassOnNearbyMessagesSwitchIsOnByDefaultAndEasyToHit() {
        let app = demoApp()
        app.launch()
        XCTAssertTrue(app.buttons["settings-button"].waitForExistence(timeout: 10))
        openSettingsFromAvatar(app)
        XCTAssertTrue(app.buttons["settings-privacy"].waitForExistence(timeout: 5))
        app.buttons["settings-privacy"].tap()
        let toggle = app.switches["privacy-mesh-help"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "the row is in Privacy")
        XCTAssertEqual(toggle.value as? String, "1", "on by default")
        XCTAssertTrue(app.staticTexts["Help pass on nearby messages"].exists, "the words are there for VoiceOver (the row is 58 pt tall, like the other Privacy rows)")
        XCTAssertTrue(app.staticTexts["Uses a little battery. Messages you carry are sealed; you can\u{2019}t read them."].exists)
    }
}
