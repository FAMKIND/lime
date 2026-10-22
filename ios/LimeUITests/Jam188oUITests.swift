import XCTest

/// LIME-188o: captions made on the writer's phone, corrected before posting, shown on the video with CC.
@MainActor
final class Jam188oUITests: LimeUITestCase {
    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    func testARecordedVideoGetsCaptionsTheWriterCorrectsAndTheCardShowsCC() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "jam"]
        app.launch()
        app.buttons["new-jam-post"].tap()
        app.buttons["jam-record"].tap()
        app.buttons["podcast-camera"].tap()
        app.buttons["podcast-record"].tap()
        app.buttons["podcast-stop"].tap()
        app.textFields["podcast-title"].tap(); app.textFields["podcast-title"].typeText("Fraction wall")
        app.buttons["podcast-next"].tap()
        app.buttons["jam-coauthor-done"].tap()   // Skip
        let status = any(app, "jam-captions-status")
        XCTAssertTrue(status.waitForExistence(timeout: 8))
        let ready = NSPredicate(format: "label CONTAINS 'Captions \u{00B7} 2 lines'")
        expectation(for: ready, evaluatedWith: status)
        waitForExpectations(timeout: 8)
        app.buttons["jam-captions-edit"].tap()
        let line = app.textFields["caption-line-0"].exists ? app.textFields["caption-line-0"] : app.textViews["caption-line-0"]
        XCTAssertTrue(line.waitForExistence(timeout: 5))
        line.tap(); line.typeText(" Fixed")
        app.buttons["captions-done"].tap()
        app.buttons["jam-post"].tap()
        let cc = app.buttons["jam-video-cc"]
        for _ in 0..<4 where !cc.exists { app.swipeUp() }
        XCTAssertTrue(cc.waitForExistence(timeout: 10), "CC shows when the video has captions")
        app.buttons["jam-video"].firstMatch.exists ? () : ()
        any(app, "jam-video").coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.5)).tap()
        XCTAssertTrue(any(app, "jam-video-screen").waitForExistence(timeout: 5))
        let chip = any(app, "jam-video-caption")
        XCTAssertTrue(chip.waitForExistence(timeout: 5))
                app.buttons["jam-video-more"].tap()
        app.buttons["Transcript"].tap()
        XCTAssertTrue(any(app, "jam-transcript-text").waitForExistence(timeout: 5))
        XCTAssertTrue(any(app, "jam-transcript-text").label.contains("Fixed"))
    }
}
