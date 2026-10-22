import XCTest

/// LIME-188j: the video card (muted, mute button, no CC without captions), the full-screen screen, the post's words over the video, the ⋯ menu.
@MainActor
final class Jam188jUITests: LimeUITestCase {
    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    func testTheVideoCardHasAMuteButtonAndNoCaptionsToggleAndOpensFullScreenWithItsMenuAndText() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "jam-following"]
        app.launch()
        let card = any(app, "jam-video")
        for _ in 0..<5 where !card.exists || !card.isHittable { app.swipeUp() }
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["jam-video-mute"].exists)
        XCTAssertEqual(app.buttons["jam-video-mute"].label, "Unmute", "it starts muted")
        XCTAssertFalse(app.buttons["jam-video-cc"].exists, "no captions toggle without captions")
        card.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.5)).tap()
        XCTAssertTrue(any(app, "jam-video-screen").waitForExistence(timeout: 5), "a tap opens the full screen")
        app.buttons["jam-video-more"].tap()
        for item in ["Share in lime\u{2026}", "Auto-advance", "Hide post"] { XCTAssertTrue(app.buttons[item].waitForExistence(timeout: 3) || app.switches[item].exists, item) }
        XCTAssertFalse(app.buttons["Copy link"].exists)
        XCTAssertFalse(app.buttons["Report"].exists)
        XCTAssertFalse(app.buttons["Closed captions"].exists && app.switches["Closed captions"].exists, "only with captions")
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)).tap()   // closes the menu
        let text = app.buttons["jam-video-text"]
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        text.tap()
        if !any(app, "jam-video-text-open").waitForExistence(timeout: 3) { text.tap() }   // the first tap may only have closed the menu
        XCTAssertTrue(any(app, "jam-video-text-open").waitForExistence(timeout: 5), "the words open over the video")
        any(app, "jam-video-text-open").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)).tap()
        XCTAssertFalse(any(app, "jam-video-text-open").waitForExistence(timeout: 2), "and fold back")
        app.buttons["jam-video-close"].tap()
        XCTAssertFalse(any(app, "jam-video-screen").waitForExistence(timeout: 2))
    }
}
