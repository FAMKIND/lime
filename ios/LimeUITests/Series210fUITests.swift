import XCTest

/// LIME-210f: series of articles, videos and podcasts (demo).
@MainActor
final class Series210fUITests: LimeUITestCase {
    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    func testASeriesPageListsThePartsInOrderWithProgressAndAPreviewsLock() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "jam-series"]
        app.launch()
        let line = any(app, "jam-card-series-demo-post-1")
        for _ in 0..<5 where !line.exists { app.swipeUp() }
        XCTAssertTrue(line.waitForExistence(timeout: 10), "the card says which part it is")
        XCTAssertEqual(line.label, "Part 1 of 3 of the series Fractions that stick")
        line.tap()
        XCTAssertTrue(any(app, "series-page").waitForExistence(timeout: 5))
        XCTAssertEqual(any(app, "series-page-title").label, "Fractions that stick")
        let one = any(app, "series-part-demo-post-1"), two = any(app, "series-part-demo-open-sam-part2"), three = any(app, "series-part-demo-post-2")
        XCTAssertTrue(one.exists && two.exists && three.exists)
        XCTAssertLessThan(one.frame.minY, two.frame.minY, "in order")
        XCTAssertLessThan(two.frame.minY, three.frame.minY, "in order")
        XCTAssertTrue(any(app, "series-lock-demo-open-sam-part2").exists, "the open part is a Preview")
        XCTAssertTrue(any(app, "series-read-demo-post-1").exists, "progress is kept on the phone")
        XCTAssertEqual(any(app, "series-progress").label, "1 of 3 read")
    }

    func testMakingANewSeriesOnBeforeYouPublishPutsPartOneOnTheCard() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "jam-mine"]
        app.launch()
        XCTAssertTrue(app.buttons["new-jam-post"].waitForExistence(timeout: 10))
        app.buttons["new-jam-post"].tap()
        XCTAssertTrue(app.buttons["jam-write-article"].waitForExistence(timeout: 8))
        app.buttons["jam-write-article"].tap()
        let title = app.textFields["jam-article-title"].exists ? app.textFields["jam-article-title"] : app.textViews["jam-article-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 8))
        XCTAssertFalse(any(app, "jam-series").exists, "the series is on step 2, not while writing")
        title.tap(); title.typeText("Halves\n\n")
        let body = app.textViews["composer-field"]
        XCTAssertTrue(body.waitForExistence(timeout: 5))
        body.tap(); body.typeText("Cut it in two")
        app.buttons["jam-next"].tap()
        XCTAssertTrue(any(app, "jam-series").waitForExistence(timeout: 8))
        XCTAssertEqual(any(app, "jam-series").label, "Add to a series")
        any(app, "jam-series").tap()
        any(app, "series-new").tap()
        let name = app.textFields["series-title"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText("Fractions")
        app.buttons["sheet-close"].tap()
        XCTAssertTrue(any(app, "jam-series").waitForExistence(timeout: 5))
        XCTAssertEqual(any(app, "jam-series").label, "Series: Fractions, Part 1")
        app.buttons["jam-post"].tap()
        // The article opens on its own page (LIME-243); its series line is above the title and says Part 1.
        let line = any(app, "jam-article-series")
        XCTAssertTrue(line.waitForExistence(timeout: 12))
        XCTAssertTrue(line.label.contains("Part 1"), line.label)
    }
}
