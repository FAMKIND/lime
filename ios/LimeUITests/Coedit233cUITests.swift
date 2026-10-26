import XCTest

/// LIME-233c: the article editor works on a draft in the core (demo, with a throwaway core).
@MainActor
final class Coedit233cUITests: LimeUITestCase {
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "jam-mine", "-lime-coedit-sim-remote"]
        app.launch()
        return app
    }

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

    func testTheDraftFollowsWhatIsOnScreenSurvivesClosingAndKeepsTheCaretWhenAnotherAuthorTypes() {
        let app = launch()
        let title = openArticle(app)
        title.tap(); title.typeText("Fractions plan\n\n")
        let body = app.textViews["composer-field"]
        expectation(for: NSPredicate(format: "hasKeyboardFocus == true"), evaluatedWith: body)
        waitForExpectations(timeout: 5)
        body.typeText("Hello world")
        let probe = any(app, "coedit-probe")
        XCTAssertTrue(probe.waitForExistence(timeout: 8), "the draft exists once something is written")
        expectation(for: NSPredicate(format: "label == 'Hello world'"), evaluatedWith: probe)
        waitForExpectations(timeout: 5)
        // Another author types at the start; the caret stays at the end where this author is writing.
        expectation(for: NSPredicate(format: "label == 'REMOTE Hello world'"), evaluatedWith: probe)
        waitForExpectations(timeout: 15)
        XCTAssertEqual(body.value(forKey: "hasKeyboardFocus") as? Bool, true, "the editor keeps the keyboard when another author's words arrive")
        body.typeText("!")
        sleep(2)
        let shown = (body.value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(shown, "REMOTE Hello world!", "the typing landed at the caret, after the words, not at the start (draft: \(probe.label))")
        XCTAssertEqual(probe.label, "REMOTE Hello world!")
        // Close and reopen: the draft comes back from the core.
        app.buttons["jam-compose-cancel"].tap()
        app.buttons["new-jam-post"].tap()   // the unfinished article opens again by itself
        if app.buttons["jam-write-article"].waitForExistence(timeout: 2) { app.buttons["jam-write-article"].tap() }
        let again = app.textViews["composer-field"]
        XCTAssertTrue(again.waitForExistence(timeout: 8))
        expectation(for: NSPredicate(format: "value CONTAINS 'REMOTE Hello world!'"), evaluatedWith: again)
        waitForExpectations(timeout: 8)
    }
}
