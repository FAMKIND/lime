import XCTest

/// LIME-188l: the article editor: "+ Add co-author" by your name, headings, quote, a button, "Back".
@MainActor
final class Jam188lUITests: LimeUITestCase {
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "jam"]
        app.launch()
        return app
    }

    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    func testCoauthorIsByYourNameTheBarHasNoPersonButtonAndHeadingsQuotesAndButtonsWork() {
        let app = launch()
        app.buttons["new-jam-post"].tap()
        app.buttons["jam-write-article"].tap()
        XCTAssertEqual(app.buttons["jam-exit-article"].label, "Exit article mode")
        let add = app.buttons["jam-add-coauthor"]
        XCTAssertTrue(add.exists)
        XCTAssertEqual(app.buttons.matching(identifier: "jam-add-coauthor").count, 1, "only the one by your name")
        XCTAssertEqual(add.frame.midY, app.buttons["jam-post-as"].frame.midY, accuracy: 6, "on the name's line")
        XCTAssertLessThan(add.frame.minY, app.buttons["jam-add"].frame.minY, "not in the bottom bar")

        let title = app.textFields["jam-article-title"].exists ? app.textFields["jam-article-title"] : app.textViews["jam-article-title"]
        title.tap(); title.typeText("Ten minutes of fractions\n\n")
        let body = app.textViews["composer-field"]
        expectation(for: NSPredicate(format: "hasKeyboardFocus == true"), evaluatedWith: body)
        waitForExpectations(timeout: 5)
        app.buttons["jam-format"].tap()
        body.typeText("Why it works")
        app.buttons["jam-heading"].tap(); app.buttons["jam-heading-2"].tap()
        XCTAssertEqual(body.value as? String, "## Why it works")
        body.typeText("\n")
        body.typeText("Fold it first")
        app.buttons["fmt-quote"].tap()
        XCTAssertTrue((body.value as? String ?? "").contains("> Fold it first"), body.value as? String ?? "")
        // A button.
        let scroll = app.scrollViews["fmt-scroll"]
        for _ in 0..<3 where !app.buttons["fmt-button"].isHittable { scroll.swipeLeft() }
        app.buttons["fmt-button"].tap()
        app.buttons["button-custom"].tap()
        let text = app.textFields["button-text"]
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        text.typeText("Get the worksheet")
        let url = app.textFields["button-url"]
        url.tap(); url.typeText("example.com/worksheet")
        app.buttons["button-apply"].tap()
        XCTAssertTrue((body.value as? String ?? "").contains("[[Get the worksheet]](https://example.com/worksheet)"), body.value as? String ?? "")
        postNow(app)
        app.showJamArticles()
        let card = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Ten minutes of fractions'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 8))
        card.tap()
        XCTAssertTrue(any(app, "post-button").waitForExistence(timeout: 8), "the reader draws the button")
        XCTAssertEqual(any(app, "post-button").label, "Get the worksheet")
    }
}
