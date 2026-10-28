import XCTest

/// LIME-212: editing a podcast looks like a podcast; the players follow edits (demo).
@MainActor
final class Jam212UITests: LimeUITestCase {
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "jam-mine-podcast"]
        app.launch()
        return app
    }

    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    private func openEditor(_ app: XCUIApplication) {
        any(app, "jam-filter-segments").buttons["Podcasts"].tap()
        let more = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'card-more-'")).firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 10)); more.tap()
        app.buttons["Edit"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["podcast-title"].waitForExistence(timeout: 8), "the black studio")
    }

    func testEditOnARecordingIsAPodcastPageNotTheArticleEditor() {
        let app = launch()
        openEditor(app)
        // LIME-239b: the details page in edit mode: Update on top, who it is from, Record again in the ⋯ (it asks first).
        XCTAssertEqual(app.descendants(matching: .any)["podcast-title"].value as? String, "Songs for the circle")
        XCTAssertEqual(app.descendants(matching: .any)["podcast-subtitle"].value as? String, "Korean children's songs")
        XCTAssertTrue(app.buttons["podcast-update"].exists, "Update on top")
        XCTAssertTrue(app.buttons["jam-post-as"].exists == false, "the article editor's bar is gone")
        XCTAssertTrue(app.buttons["podcast-post-as"].exists, "who it is from")
        app.buttons["podcast-more"].tap()
        app.buttons["Record again"].tap()
        XCTAssertTrue(app.buttons["podcast-rerecord-confirm"].waitForExistence(timeout: 5), "Record again asks first")
        app.buttons["Keep it"].tap()
        XCTAssertFalse(app.buttons["podcast-record"].exists, "the recording stays until they confirm")
    }

    func testTheMiniPlayerShowsAnEditedTitleAndTheBlackPlayerTheSubtitle() {
        let app = launch()
        any(app, "jam-filter-segments").buttons["Podcasts"].tap()
        let pill = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'jam-audio-play-'")).firstMatch
        XCTAssertTrue(pill.waitForExistence(timeout: 10)); pill.tap()
        XCTAssertTrue(any(app, "jam-video-screen").waitForExistence(timeout: 5))
        XCTAssertTrue(any(app, "jam-video-text").label.contains("Korean children's songs"), "the subtitle under the title: \(any(app, "jam-video-text").label)")
        // The player's ⋯ has Edit for your own post.
        app.buttons["jam-video-more"].tap()
        XCTAssertTrue(app.buttons["Edit"].waitForExistence(timeout: 5))
        app.buttons["Edit"].tap()
        let title = app.descendants(matching: .any)["podcast-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 8))
        title.tap(); title.typeText(" again")
        app.buttons["podcast-update"].tap()
        app.buttons["jam-video-close"].tap()
        let mini = app.buttons["audio-mini-open"]
        XCTAssertTrue(mini.waitForExistence(timeout: 5))
        expectation(for: NSPredicate(format: "label CONTAINS 'again'"), evaluatedWith: mini)
        waitForExpectations(timeout: 5)
    }
}
