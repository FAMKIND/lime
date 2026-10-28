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

    private func field(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.textFields[id].exists ? app.textFields[id] : app.textViews[id] }

    func testTheTitleIsBelowThePreviewAndReachableWithTheKeyboardUp() {
        let app = studio()
        app.buttons["jam-record"].tap()
        app.buttons["podcast-record"].tap()
        sleep(1)
        app.buttons["podcast-stop"].tap()
        let preview = app.buttons["podcast-play"]
        XCTAssertTrue(preview.waitForExistence(timeout: 8), "the details page shows the recording as a preview")
        let title = field(app, "podcast-title")
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(title.frame.minY, preview.frame.maxY, "the title is under the preview: \(title.frame) \(preview.frame)")
        title.tap()
        title.typeText("Pine")
        XCTAssertTrue(title.isHittable, "still reachable with the keyboard up")
        XCTAssertLessThan(title.frame.maxY, app.keyboards.firstMatch.frame.minY, "above the keyboard")
        XCTAssertEqual(field(app, "podcast-title").value as? String, "Pine")
    }

    func testBackAsksBeforeDiscardingTheTakeAndPostMakesThePodcast() {
        let app = studio()
        app.buttons["jam-record"].tap()
        app.buttons["podcast-record"].tap()
        sleep(1)
        app.buttons["podcast-stop"].tap()
        XCTAssertTrue(app.buttons["podcast-play"].waitForExistence(timeout: 8), "the preview plays the take")
        app.buttons["podcast-back"].tap()
        XCTAssertTrue(app.buttons["podcast-rerecord-confirm"].firstMatch.waitForExistence(timeout: 5), "Record again? This take will be discarded")
        app.buttons["Keep it"].firstMatch.tap()
        XCTAssertTrue(app.buttons["podcast-play"].exists, "kept")
        let title = field(app, "podcast-title")
        title.tap(); title.typeText("Pine walk")
        app.buttons["podcast-post"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'jam-audio-card-' OR identifier == 'jam-video'")).firstMatch.waitForExistence(timeout: 12), "the podcast is posted")
    }
}
