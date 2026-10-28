import XCTest

/// LIME-239b: the details page (demo): the preview, the trim bar, Post as, Add cover and the three fields; a handle changes the length; Edit opens it too.
@MainActor
final class Studio239bUITests: LimeUITestCase {
    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    func testStopOpensTheDetailsPageAndADraggedHandleChangesTheLength() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "jam"]
        app.launch()
        app.buttons["new-jam-post"].tap()
        app.buttons["jam-record"].tap()
        app.buttons["podcast-record"].tap()
        sleep(2)
        app.buttons["podcast-stop"].tap()
        XCTAssertTrue(app.buttons["podcast-play"].waitForExistence(timeout: 8), "the preview")
        for id in ["podcast-trim-start", "podcast-trim-end", "podcast-post-as", "podcast-add-cover", "podcast-title", "podcast-subtitle", "podcast-description", "podcast-back", "podcast-post"] {
            XCTAssertTrue(any(app, id).waitForExistence(timeout: 3), id)
        }
        XCTAssertEqual(app.buttons["podcast-add-cover"].label, "Add cover")
        let length = any(app, "podcast-trim-length")
        let before = length.value as? String ?? ""
        let end = any(app, "podcast-trim-end")
        end.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.1, thenDragTo: any(app, "podcast-trim-start").coordinate(withNormalizedOffset: CGVector(dx: 3, dy: 0.5)))
        XCTAssertNotEqual(length.value as? String, before, "dragging the end handle changes the length: \(before) -> \(String(describing: length.value))")
        // ‹ asks before discarding the take.
        app.buttons["podcast-back"].tap()
        XCTAssertTrue(app.buttons["podcast-rerecord-confirm"].firstMatch.waitForExistence(timeout: 3))
        app.buttons["Keep it"].firstMatch.tap()
    }

    func testEditOnAPodcastOpensTheSamePageWithTheTrimBar() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "jam-mine-podcast"]
        app.launch()
        any(app, "jam-filter-segments").buttons["Podcasts"].tap()
        let more = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'card-more-'")).firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 10)); more.tap()
        app.buttons["Edit"].tap()
        XCTAssertTrue(any(app, "podcast-title").waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["podcast-update"].exists)
        XCTAssertTrue(any(app, "podcast-trim-start").waitForExistence(timeout: 5), "the trim bar is on the edit page too")
        XCTAssertTrue(any(app, "podcast-add-cover").exists)
    }
}
