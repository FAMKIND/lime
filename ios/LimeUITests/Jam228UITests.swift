import XCTest

/// LIME-228: the player's comments sheet: a quiet send button, one-line comment heads (demo).
@MainActor
final class Jam228UITests: LimeUITestCase {
    func testSendIsDisabledUntilThereIsTextAndACommentsHeadIsOneLine() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "jam-mine-podcast"]
        app.launch()
        app.descendants(matching: .any).matching(identifier: "jam-filter-segments").firstMatch.buttons["Podcasts"].tap()
        let pill = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'jam-audio-play-'")).firstMatch
        XCTAssertTrue(pill.waitForExistence(timeout: 10)); pill.tap()
        let comments = app.buttons["jam-player-comments"]
        XCTAssertTrue(comments.waitForExistence(timeout: 8)); comments.tap()
        let field = app.textViews["jam-comment-field"].exists ? app.textViews["jam-comment-field"] : app.textFields["jam-comment-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["jam-comment-send"].isEnabled, "nothing to send yet")
        field.tap(); field.typeText("Lovely")
        XCTAssertTrue(app.buttons["jam-comment-send"].isEnabled)
        app.buttons["jam-comment-send"].tap()
        let date = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'jam-comment-date-'")).firstMatch
        XCTAssertTrue(date.waitForExistence(timeout: 8))
        XCTAssertLessThan(date.frame.height, 24, "the name and the date share one line")
    }
}
