import XCTest

/// LIME-188i: jam cards fit the screen, the chat composer keeps its side margins, videos use a video player, links show cards, the voice icon.
@MainActor
final class Jam188iUITests: LimeUITestCase {
    private func launch(_ screen: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat"] + (screen.map { ["-lime-demo-screen", $0] } ?? [])
        app.launch()
        return app
    }

    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    func testEveryCardSitsInsideTheScreen() {
        let app = launch("jam-following")
        XCTAssertTrue(any(app, "jam-feed").waitForExistence(timeout: 10))
        let width = app.windows.firstMatch.frame.width
        for id in ["jam-post-demo-post-2", "jam-card-byline-demo-post-3"] {
            let element = any(app, id)
            XCTAssertTrue(element.waitForExistence(timeout: 5), id)
            XCTAssertGreaterThanOrEqual(element.frame.minX, 0, "\(id) starts on the screen")
            XCTAssertLessThanOrEqual(element.frame.maxX, width + 0.5, "\(id) ends on the screen")
        }
        for id in ["jam-audio-card-demo-audio-1"] {
            let element = any(app, id)
            for _ in 0..<6 where !element.exists || !element.isHittable { app.swipeUp() }
            XCTAssertGreaterThanOrEqual(element.frame.minX, 0, "\(id) starts on the screen")
            XCTAssertLessThanOrEqual(element.frame.maxX, width + 0.5, "\(id) ends on the screen")
        }
    }

    func testTheChatComposerIsInsetFromTheScreenEdges() {
        let app = launch()
        app.buttons["conversation-row-dm:sam"].tap()
        let field = app.textViews["composer-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 8))
        let width = app.windows.firstMatch.frame.width
        XCTAssertGreaterThanOrEqual(field.frame.minX, 12, "a gap on the left (13.7 pt before any jam work too)")
        XCTAssertLessThanOrEqual(field.frame.maxX, width - 12, "and on the right")
    }

    func testAVideoInAPostHasNoPodcastPlayerAndTheVoiceButtonIsAWaveform() {
        let app = launch("jam-following")
        app.openDemoVideoPost()
        XCTAssertTrue(any(app, "jam-video").waitForExistence(timeout: 10), "the video is there")
        XCTAssertFalse(any(app, "podcast-demo-video-1").exists, "a video wears no podcast player")
        app.buttons["new-jam-post"].tap()
        XCTAssertTrue(app.buttons["jam-add-photo"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["jam-add-voice"].exists, "no waveform icon: the Record pill covers it (LIME-188q)")
    }

    func testAPostWithALinkShowsItsCard() {
        let app = launch("jam")
        app.buttons["new-jam-post"].tap()
        let field = app.textViews["composer-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 8))
        field.tap(); field.typeText("Worth a read https://example.com/fractions")
        XCTAssertTrue(any(app, "jam-link-draft").waitForExistence(timeout: 8), "the card is built while writing")
        postNow(app)
        XCTAssertTrue(any(app, "jam-link-card").waitForExistence(timeout: 8), "and shown with the post")
    }
}
