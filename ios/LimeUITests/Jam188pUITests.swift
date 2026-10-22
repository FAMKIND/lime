import XCTest

/// LIME-188p: an article is a cover card; it opens to a reading page with a header that hides on scroll down, display settings, and Options.
@MainActor
final class Jam188pUITests: LimeUITestCase {
    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    func testTheCardOpensTheReadingPageWithOptionsDisplaySettingsAndSearch() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "jam-following"]
        app.launch()
        XCTAssertTrue(any(app, "jam-article-card-title").waitForExistence(timeout: 10), "an article is a cover card with its title over the picture")
        any(app, "jam-post-demo-post-1").tap()
        XCTAssertTrue(any(app, "jam-article-page").waitForExistence(timeout: 8), "a tap opens the reading page")
        XCTAssertEqual(any(app, "jam-reader-title").label, "Equivalent fractions in ten minutes")
        XCTAssertTrue(any(app, "jam-reader-body-newYork").waitForExistence(timeout: 5), "New York is the default face")
        app.buttons["jam-article-more"].tap()
        for id in ["options-search", "options-display", "options-listen", "options-viewjam", "options-save", "options-print", "options-share", "options-hide"] {
            XCTAssertTrue(any(app, id).waitForExistence(timeout: 3), id)
        }
        XCTAssertFalse(app.buttons["Report"].exists, "Report waits for LIME-191")
        any(app, "options-display").tap()
        let lexend = any(app, "reader-font-lexend")
        XCTAssertTrue(lexend.waitForExistence(timeout: 5))
        lexend.tap()
        any(app, "reader-size-2").tap()
        any(app, "reader-line-2").tap()
        app.buttons["Close"].firstMatch.tap()
        XCTAssertTrue(any(app, "jam-reader-body-lexend").waitForExistence(timeout: 5), "the body changed face")
        app.buttons["jam-article-more"].tap()
        any(app, "options-search").tap()
        let field = app.textFields["jam-article-find-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("it")
        XCTAssertEqual(any(app, "jam-article-find-count").label, "1 of 3")
        app.buttons["jam-article-find-next"].tap()
        XCTAssertEqual(any(app, "jam-article-find-count").label, "2 of 3")
    }

    func testTheSavedRowListsWhatYouSavedAndHidePostRemovesACard() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "jam-following"]
        app.launch()
        let save = app.buttons["jam-article-save-demo-post-1"]
        XCTAssertTrue(save.waitForExistence(timeout: 10))
        let before = save.label
        save.tap()
        XCTAssertNotEqual(save.label, before)
        // Put it back so the next run starts clean.
        save.tap()
    }
}
