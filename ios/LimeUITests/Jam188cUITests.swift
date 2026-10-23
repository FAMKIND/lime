import XCTest

/// LIME-188c: jam as home: the featured row above the feed; an unread dot on articles; "more" on long quick posts.
@MainActor
final class Jam188cUITests: LimeUITestCase {
    private func launch(_ screen: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", screen]
        app.launch()
        return app
    }

    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    func testTheFeaturedRowShowsTenOfTwelveAboveTheFilterRowInBothSegments() {
        let app = launch("jam-featured")
        let row = any(app, "jam-featured")
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertEqual(row.label, "Featured")
        XCTAssertTrue((row.value as? String ?? "").hasPrefix("1 of 10"), "ten at most: \(row.value as? String ?? "")")
        XCTAssertLessThan(row.frame.minY, app.segmentedControls["jam-filter-segments"].frame.minY, "above Posts | Articles | Saved")
        app.segmentedControls["jam-filter-segments"].buttons["Articles"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5), "and in Articles too")
    }

    func testTheFeaturedRowIsGoneWhenThereIsNothingToFeature() {
        let app = launch("jam")
        XCTAssertTrue(any(app, "jam-feed-empty").waitForExistence(timeout: 10))
        XCTAssertFalse(any(app, "jam-featured").exists)
    }

    func testAnUnreadArticleHasADotAndOpeningItClearsIt() {
        let app = launch("jam-following")
        app.showJamArticles()
        let dot = any(app, "jam-unread-demo-post-1")
        XCTAssertTrue(dot.waitForExistence(timeout: 10))
        XCTAssertEqual(dot.label, "Unread")
        app.buttons["jam-post-demo-post-1"].tap()
        XCTAssertTrue(any(app, "jam-article-page").waitForExistence(timeout: 8))
        app.buttons["jam-article-back"].tap()
        XCTAssertTrue(app.segmentedControls["jam-filter-segments"].waitForExistence(timeout: 8))
        XCTAssertTrue(dot.waitForNonExistence(timeout: 5), "read: the dot is gone")
    }

    func testMoreOpensALongQuickPostInPlace() {
        let app = launch("jam-mine-asjam")
        let more = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'jam-more-'")).firstMatch
        for _ in 0..<5 where !more.exists { app.swipeUp() }
        XCTAssertTrue(more.waitForExistence(timeout: 8), "a note of 14 lines is cut")
        more.tap()
        XCTAssertTrue(more.waitForNonExistence(timeout: 5), "opened in place")
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Line 14 of a long note'")).firstMatch.waitForExistence(timeout: 5), "the whole note")
    }
}
