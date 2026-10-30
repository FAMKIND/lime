import XCTest

/// LIME-260b: the series page like a show page: a cover hero with the title, a play pill, the description with MORE, a meta line, Parts with dates and pills,
/// swipe to mark played, the filter, Hosts and Information (demo).
@MainActor
final class Series260bUITests: LimeUITestCase {
    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    private func openSeries() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "jam-series"]
        app.launch()
        let line = any(app, "jam-card-series-demo-post-1")
        for _ in 0..<5 where !line.exists { app.swipeUp() }
        XCTAssertTrue(line.waitForExistence(timeout: 10))
        line.tap()
        XCTAssertTrue(any(app, "series-page").waitForExistence(timeout: 8))
        return app
    }

    func testTheHeroHasTheTitleAPlayPillTheDescriptionWithMoreAndAMetaLine() {
        let app = openSeries()
        XCTAssertEqual(any(app, "series-page-title").label, "Fractions that stick")
        let play = any(app, "series-play")
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        XCTAssertTrue(play.label.contains("Part 2") || play.label.contains("Part 3"), "the next part you have not read: \(play.label)")
        let description = any(app, "series-description")
        XCTAssertTrue(description.waitForExistence(timeout: 5))
        let short = description.frame.height
        any(app, "series-more-text").tap()
        XCTAssertGreaterThan(any(app, "series-description").frame.height, short, "MORE expands the description")
        XCTAssertTrue(any(app, "series-meta").label.contains("3 parts"), any(app, "series-meta").label)
        XCTAssertEqual(any(app, "series-progress").label, "1 of 3 read")
    }

    func testPartsListInOrderSwipeMarksPlayedAndTheFilterShowsOnlyUnplayed() {
        let app = openSeries()
        let one = any(app, "series-part-demo-post-1"), three = any(app, "series-part-demo-post-2")
        for _ in 0..<4 where !three.exists { app.swipeUp() }
        XCTAssertTrue(one.waitForExistence(timeout: 5) && three.exists)
        XCTAssertTrue(any(app, "series-read-demo-post-1").exists, "played parts are marked")
        // Swipe right on a part: Read.
        three.swipeRight()
        let read = app.buttons["series-swipe-played-demo-post-2"]
        XCTAssertTrue(read.waitForExistence(timeout: 5), "swipe right: Read")
        read.tap()
        XCTAssertTrue(any(app, "series-read-demo-post-2").waitForExistence(timeout: 5))
        // The filter: Unplayed leaves the open part only.
        for _ in 0..<6 { app.swipeDown() }
        any(app, "series-filter").tap()
        app.buttons["Unplayed"].tap()
        XCTAssertFalse(any(app, "series-part-demo-post-1").exists, "a played part is not in Unplayed")
        XCTAssertTrue(any(app, "series-part-demo-open-sam-part2").waitForExistence(timeout: 5))
    }

    func testHostsAndInformationAtTheBottom() {
        let app = openSeries()
        for _ in 0..<8 where !any(app, "series-info-parts").exists { app.swipeUp() }
        XCTAssertTrue(any(app, "series-info-parts").label.hasSuffix("3"), any(app, "series-info-parts").label)
        XCTAssertTrue(any(app, "series-host-sam").exists, "the writer is a host")
    }
}
