import XCTest

/// LIME-227: the black studio: record a podcast on the player's own layout.
@MainActor
final class Studio227UITests: LimeUITestCase {
    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    private func studio() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "jam"]
        app.launch()
        app.buttons["new-jam-post"].tap()
        return app
    }

    func testThePlusOffersWriteAnArticleAndRecordAPodcast() {
        let app = studio()
        XCTAssertTrue(app.buttons["jam-write-article"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.buttons["jam-record"].label, "Record a podcast")
        XCTAssertEqual(app.buttons["jam-write-article"].label, "Write an article")
    }

    func testTheTitleIsBelowTheStageAndReachableWithTheKeyboardUp() throws {
        try XCTSkipIf(true, "superseded by LIME-239a/b (the recorder is full screen; the words page follows): rewritten with 239b")
        let app = studio()
        app.buttons["jam-record"].tap()
        let stage = any(app, "podcast-audio-layer")
        XCTAssertTrue(stage.waitForExistence(timeout: 8))
        let title = app.textFields["podcast-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(title.frame.minY, stage.frame.maxY, "the title is under the stage: \(title.frame) \(stage.frame)")
        title.tap()
        title.typeText("Pine")
        XCTAssertTrue(title.isHittable, "still reachable with the keyboard up")
        let keyboard = app.keyboards.firstMatch.frame
        XCTAssertLessThan(title.frame.maxY, keyboard.minY, "above the keyboard: \(title.frame) \(keyboard)")
        XCTAssertFalse(title.frame.intersects(stage.frame), "never over the stage")
        XCTAssertEqual(app.textFields["podcast-title"].value as? String, "Pine")
        // The pencils.
        XCTAssertTrue(app.buttons["Edit title"].exists && app.buttons["Edit subtitle"].exists && app.buttons["Edit description"].exists)
    }

    func testRecordingThenReRecordAsksFirstAndPostMakesThePodcast() throws {
        try XCTSkipIf(true, "superseded by LIME-239a/b (the recorder is full screen; the words page follows): rewritten with 239b")
        let app = studio()
        app.buttons["jam-record"].tap()
        app.buttons["podcast-record"].tap()
        sleep(1)
        app.buttons["podcast-stop"].tap()
        XCTAssertTrue(app.buttons["podcast-play"].waitForExistence(timeout: 8), "the stage plays the take")
        app.buttons["podcast-again"].tap()
        XCTAssertTrue(app.buttons["podcast-rerecord-confirm"].firstMatch.waitForExistence(timeout: 5), "Replace this recording?")
        app.buttons["Keep it"].firstMatch.tap()
        XCTAssertTrue(app.buttons["podcast-play"].exists, "kept")
        app.textFields["podcast-title"].tap(); app.textFields["podcast-title"].typeText("Pine walk")
        app.buttons["podcast-post"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'jam-audio-card-'")).firstMatch.waitForExistence(timeout: 12), "the podcast is posted")
    }
}
