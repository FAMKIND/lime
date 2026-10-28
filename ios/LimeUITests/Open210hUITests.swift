import XCTest

/// LIME-210h: Report on open posts, open posts in search, chips at publish, series for podcasts (demo).
@MainActor
final class Open210hUITests: LimeUITestCase {
    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    private func discover() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "jam-discover"]
        app.launch()
        return app
    }

    func testReportOnAnOpenPostFromItsCardCarriesTheOpenPostsId() {
        let app = discover()
        let more = any(app, "discover-more-demo-open-lee-1")
        XCTAssertTrue(more.waitForExistence(timeout: 10)); more.tap()
        app.buttons["Report"].tap()
        XCTAssertTrue(app.buttons["report-send"].waitForExistence(timeout: 8))
        app.buttons["report-reason-spam"].tap()
        app.buttons["report-send"].tap()
        XCTAssertTrue(any(app, "report-thanks").waitForExistence(timeout: 8))
        XCTAssertEqual(any(app, "report-probe").label, "jam_post demo-open-lee-1,demo-lee-jam,lee,open", "the id of the open post, marked open")
    }

    func testReportOnAnOpenPostFromItsPage() {
        let app = discover()
        let card = any(app, "discover-post-demo-open-lee-1")
        XCTAssertTrue(card.waitForExistence(timeout: 10)); card.tap()
        XCTAssertTrue(any(app, "open-post-page").waitForExistence(timeout: 5))
        any(app, "open-post-more").tap()
        app.buttons["Report"].tap()
        XCTAssertTrue(app.buttons["report-send"].waitForExistence(timeout: 8))
        app.buttons["report-reason-inappropriate"].tap()
        app.buttons["report-send"].tap()
        XCTAssertTrue(any(app, "report-thanks").waitForExistence(timeout: 8))
        XCTAssertTrue(any(app, "report-probe").label.hasSuffix("open"))
    }

    func testSearchFindsAnOpenPostThePhoneFetched() {
        let app = discover()
        let card = any(app, "discover-post-demo-open-lee-1")
        XCTAssertTrue(card.waitForExistence(timeout: 10)); card.tap()   // fetching it puts it in the index
        XCTAssertTrue(any(app, "open-post-page").waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["jam-search-button"].tap()
        let field = app.textFields["search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 8))
        field.tap(); field.typeText("chairs")
        XCTAssertTrue(any(app, "search-jam-demo-open-lee-1").waitForExistence(timeout: 8), "the fetched open post is found")
    }

    func testChipsAtPublishAreUsedByDiscoversFilters() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "jam-mine", "-lime-demo-open"]
        app.launch()
        XCTAssertTrue(app.buttons["new-jam-post"].waitForExistence(timeout: 10))
        app.buttons["new-jam-post"].tap()
        let chips = any(app, "jam-topics")
        XCTAssertTrue(chips.waitForExistence(timeout: 8))
        XCTAssertTrue(chips.label.contains("Reading"), "the jam's topics are preselected: \(chips.label)")
        chips.tap()
        let custom = app.textFields["topics-custom"]
        XCTAssertTrue(custom.waitForExistence(timeout: 5))
        custom.tap(); custom.typeText("Science")
        app.buttons["topics-add"].tap()
        app.buttons["topics-done"].tap()
        XCTAssertTrue(any(app, "jam-topics").label.contains("Science"))
        any(app, "jam-audience").tap(); any(app, "audience-everyone").tap(); any(app, "audience-confirm-everyone").tap()
        let body = app.textViews["composer-field"]
        XCTAssertTrue(body.waitForExistence(timeout: 5))
        body.tap(); body.typeText("Open science")
        app.buttons["jam-post"].tap()
        XCTAssertTrue(app.buttons["jam-segment-Discover"].waitForExistence(timeout: 10))
        app.buttons["jam-segment-Discover"].tap()
        let chip = app.buttons["discover-topic-Science"]
        XCTAssertTrue(chip.waitForExistence(timeout: 8), "Discover filters by the chips")
        chip.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'discover-post-'")).firstMatch.waitForExistence(timeout: 5))
    }

    func testAPodcastCanJoinASeriesFromTheDetailsPage() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "jam"]
        app.launch()
        app.buttons["new-jam-post"].tap()
        app.buttons["jam-record"].tap()
        app.buttons["podcast-record"].tap()
        sleep(2)
        app.buttons["podcast-stop"].tap()
        let chip = any(app, "jam-series")
        XCTAssertTrue(chip.waitForExistence(timeout: 8), "the series row on the details page")
        XCTAssertEqual(chip.label, "Add to a series")
        chip.tap()
        any(app, "series-new").tap()
        let name = app.textFields["series-title"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText("Songs")
        app.buttons["series-done"].tap()
        XCTAssertTrue(any(app, "jam-series").waitForExistence(timeout: 5))
        XCTAssertEqual(any(app, "jam-series").label, "Series: Songs, Part 1")
    }
}
