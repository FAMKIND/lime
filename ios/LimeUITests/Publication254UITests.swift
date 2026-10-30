import XCTest

/// LIME-254: a third card in jam's + makes a publication in two steps and lands on its page; Post as lists it; "my jam" stays the first one.
@MainActor
final class Publication254UITests: LimeUITestCase {
    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    func testCreateAPublicationFromThePlusThenItsPageOpensAndPostAsListsIt() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "jam-mine"]
        app.launch()
        XCTAssertTrue(app.buttons["new-jam-post"].waitForExistence(timeout: 10))
        app.buttons["new-jam-post"].tap()
        let card = app.buttons["jam-create-publication"]
        XCTAssertTrue(card.waitForExistence(timeout: 8))
        XCTAssertEqual(card.label, "Create a band")
        XCTAssertGreaterThan(card.frame.minX, app.buttons["jam-record"].frame.maxX - 1, "after Record podcast")
        card.tap()
        let name = app.textFields["publication-name-field"]
        XCTAssertTrue(name.waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["publication-next"].isEnabled, "a name is required")
        XCTAssertTrue(app.staticTexts["band-explainer"].exists, "the one-line explainer")
        name.tap(); name.typeText("Science Corner")
        app.buttons["publication-next"].tap()
        XCTAssertTrue(app.buttons["jam-topic-Science"].waitForExistence(timeout: 5))
        app.buttons["jam-topic-Science"].tap()
        app.buttons["publication-create"].tap()
        XCTAssertTrue(app.staticTexts["profile-jam-row"].waitForExistence(timeout: 10), "the new publication's page")
        XCTAssertEqual(app.staticTexts["profile-jam-row"].label, "Science Corner")
        XCTAssertTrue(app.staticTexts["org-fresh-hint"].exists, "the hint about posting as it")
    }

    func testPostAsListsThePublicationAndMyJamIsStillTheFirstOne() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "jam-mine"]
        app.launch()
        app.buttons["new-jam-post"].tap()
        app.buttons["jam-create-publication"].tap()
        let name = app.textFields["publication-name-field"]
        XCTAssertTrue(name.waitForExistence(timeout: 8))
        name.tap(); name.typeText("Science Corner")
        app.buttons["publication-next"].tap()
        app.buttons["publication-create"].tap()
        XCTAssertTrue(app.staticTexts["profile-jam-row"].waitForExistence(timeout: 10))
        // Back out, open New post again: Post as lists both.
        app.buttons["back-button"].tap()
        app.buttons["new-jam-post"].tap()
        XCTAssertTrue(app.buttons["jam-post-as"].waitForExistence(timeout: 8))
        app.buttons["jam-post-as"].tap()
        XCTAssertTrue(app.buttons["jam-post-as-me"].waitForExistence(timeout: 5))
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'jam-post-as-jam-'"))
        XCTAssertEqual(rows.count, 2, "my jam and the publication")
        XCTAssertTrue(rows.allElementsBoundByIndex.contains { $0.label.hasPrefix("Science Corner") })
    }
}
