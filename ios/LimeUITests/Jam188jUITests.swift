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
        for _ in 0..<5 where !card.exists { app.swipeUp() }
        XCTAssertTrue(card.waitForExistence(timeout: 10), "the video card")
        XCTAssertTrue(app.buttons["jam-video-mute"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.buttons["jam-video-mute"].label, "Unmute", "it starts muted")
        XCTAssertTrue(app.buttons["jam-video-cc"].waitForExistence(timeout: 5), "the demo video has captions (LIME-188o), so CC shows")
        card.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.5)).tap()
        XCTAssertTrue(any(app, "jam-video-screen").waitForExistence(timeout: 5), "a tap opens the full screen")
        app.buttons["jam-video-more"].tap()
        for item in ["Share in lime", "Transcript", "Auto-advance", "Hide post", "Closed captions"] {
            let match = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", item)).firstMatch
            XCTAssertTrue(match.waitForExistence(timeout: 3), item)
        }
        XCTAssertFalse(app.buttons["Copy link"].exists)
        XCTAssertFalse(app.buttons["Report"].exists)
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.55)).tap()   // closes the menu (away from its items)
        let text = app.buttons["jam-video-text"]
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        text.tap()
        if !any(app, "jam-about-sheet").waitForExistence(timeout: 3) { text.tap() }   // the first tap may only have closed the menu
        XCTAssertTrue(any(app, "jam-about-sheet").waitForExistence(timeout: 5), "the About sheet opens (LIME-235e)")
        app.buttons["jam-about-close"].tap()
        XCTAssertFalse(any(app, "jam-about-sheet").waitForExistence(timeout: 2), "and closes")
        app.buttons["jam-video-close"].tap()
        XCTAssertFalse(any(app, "jam-video-screen").waitForExistence(timeout: 2))
    }
}
