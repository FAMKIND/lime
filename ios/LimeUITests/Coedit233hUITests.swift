import XCTest

/// LIME-233h: carets sit on the line of the title/subtitle text; a co-author's top bar has the authors before Ready · Done (demo).
@MainActor
final class Coedit233hUITests: LimeUITestCase {
    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    private func openArticle(_ app: XCUIApplication) -> XCUIElement {
        XCTAssertTrue(app.buttons["new-jam-post"].waitForExistence(timeout: 10))
        app.buttons["new-jam-post"].tap()
        XCTAssertTrue(app.buttons["jam-write-article"].waitForExistence(timeout: 8))
        app.buttons["jam-write-article"].tap()
        let title = app.textFields["jam-article-title"].exists ? app.textFields["jam-article-title"] : app.textViews["jam-article-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 8))
        return title
    }

    func testAnotherAuthorsCaretInTheSubtitleIsOnTheSubtitlesLine() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "jam-mine", "-lime-coedit-sim-peer", "-lime-coedit-sim-peer-subtitle"]
        app.launch()
        let title = openArticle(app)
        title.tap(); title.typeText("The roots of the lime tree\n")
        let subtitle = app.textFields["jam-article-subtitle"].exists ? app.textFields["jam-article-subtitle"] : app.textViews["jam-article-subtitle"]
        subtitle.typeText("A short subtitle\n")
        let body = app.textViews["composer-field"]
        expectation(for: NSPredicate(format: "hasKeyboardFocus == true"), evaluatedWith: body)
        waitForExpectations(timeout: 5)
        body.typeText("Hello world")
        let caret = any(app, "coedit-caret-sim-jean")
        XCTAssertTrue(caret.waitForExistence(timeout: 12), "her caret shows in the subtitle")
        let line = subtitle.frame
        XCTAssertGreaterThanOrEqual(caret.frame.minY, line.minY - 2, "not above the subtitle's line: caret \(caret.frame) subtitle \(line)")
        XCTAssertLessThanOrEqual(caret.frame.maxY, line.maxY + 2, "not under the subtitle's line: caret \(caret.frame) subtitle \(line)")
        // Her tag is just above the caret.
        let tag = any(app, "coedit-cursor-sim-jean")
        XCTAssertTrue(tag.exists)
        XCTAssertLessThanOrEqual(tag.frame.maxY, caret.frame.minY + 2)
    }

    func testACoAuthorsTopBarHasTheAuthorsBeforeReadyAndDone() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "jam-mine", "-lime-coedit-sim-coauthor", "-lime-coedit-sim-peer"]
        app.launch()
        let title = openArticle(app)
        title.tap(); title.typeText("Plan\n\n")
        let body = app.textViews["composer-field"]
        expectation(for: NSPredicate(format: "hasKeyboardFocus == true"), evaluatedWith: body)
        waitForExpectations(timeout: 5)
        body.typeText("Hello world")
        let ready = app.buttons["coedit-ready"]
        XCTAssertTrue(ready.waitForExistence(timeout: 10))
        let authors = any(app, "coedit-authors")
        XCTAssertTrue(authors.waitForExistence(timeout: 5), "the authors are in a co-author's top bar")
        XCTAssertLessThan(authors.frame.minX, ready.frame.minX, "before Ready")
        XCTAssertLessThan(ready.frame.minX, app.buttons["jam-coedit-done"].frame.minX)
    }
}
