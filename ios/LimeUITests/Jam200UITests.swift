import XCTest

/// LIME-200: the podcast card and one player for card, mini and full screen (demo).
@MainActor
final class Jam200UITests: LimeUITestCase {
    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    func testPlayOpensFullScreenCloseLeavesTheMiniPlayerAndThePillFollowsIt() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "jam-following"]
        app.launch()
        let pill = app.buttons["jam-audio-play-demo-audio-1"]
        for _ in 0..<5 where !pill.exists || !pill.isHittable { app.swipeUp() }
        XCTAssertTrue(pill.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier == 'jam-podcast-title' AND label CONTAINS 'Sunday planning'")).firstMatch.exists, "the title is on the card")
        XCTAssertTrue(pill.label.hasPrefix("Play") && pill.label.contains("18 minutes"), pill.label)
        XCTAssertEqual(pill.staticTexts.firstMatch.label, "18m")
        pill.tap()
        XCTAssertTrue(any(app, "jam-video-screen").waitForExistence(timeout: 5), "play opens the full-screen player")
        app.buttons["jam-video-close"].tap()
        XCTAssertTrue(app.buttons["audio-mini-open"].waitForExistence(timeout: 5), "closing leaves the mini player")
        for _ in 0..<2 where !pill.isHittable { app.swipeDown() }
        XCTAssertTrue(pill.label.hasPrefix("Pause") || pill.label.hasPrefix("Resume"), "the pill shows the state: \(pill.label)")
        app.buttons["audio-mini-play"].tap()   // pause in the mini player
        expectation(for: NSPredicate(format: "label BEGINSWITH 'Resume'"), evaluatedWith: pill)
        waitForExpectations(timeout: 5)
        XCTAssertTrue(pill.label.contains("left"), "paused: the time left")
        pill.tap()   // resume from the pill
        expectation(for: NSPredicate(format: "label BEGINSWITH 'Pause'"), evaluatedWith: pill)
        waitForExpectations(timeout: 5)
    }
}
