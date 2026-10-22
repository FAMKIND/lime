import XCTest

/// LIME-188n: the article editor like Substack's: ⊕ menu, undo, divider and freewall, co-author as an icon, one scrolling page, the exit pill.
@MainActor
final class Jam188nUITests: LimeUITestCase {
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "jam"]
        app.launch()
        return app
    }

    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    private func openArticle(_ app: XCUIApplication) {
        app.buttons["new-jam-post"].tap()
        app.buttons["jam-write-article"].tap()
    }

    func testTheCoauthorIconSitsOnTheNameLineWithNoTextLabel() {
        let app = launch()
        openArticle(app)
        let chip = app.buttons["jam-post-as"], icon = app.buttons["jam-add-coauthor"]
        XCTAssertEqual(icon.frame.midY, chip.frame.midY, accuracy: 6, "one line")
        XCTAssertEqual(icon.label, "Add co-author")
        XCTAssertFalse(app.staticTexts["Add co-author"].exists, "no text label")
        icon.tap()
        let sam = app.buttons["jam-coauthor-choice-sam"]
        XCTAssertTrue(sam.waitForExistence(timeout: 5)); sam.tap()
        app.buttons["jam-coauthor-done"].tap()
        XCTAssertTrue(app.buttons["jam-coauthors"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["jam-coauthors"].frame.midY, chip.frame.midY, accuracy: 8, "the avatars stay on the line")
    }

    func testThePlusMenuHasTheItemsAndDividerAndFreewallInsertAndUndoTakesOneBack() {
        let app = launch()
        openArticle(app)
        let title = app.textFields["jam-article-title"].exists ? app.textFields["jam-article-title"] : app.textViews["jam-article-title"]
        title.tap(); title.typeText("Ten minutes\n\n")
        let body = app.textViews["composer-field"]
        expectation(for: NSPredicate(format: "hasKeyboardFocus == true"), evaluatedWith: body)
        waitForExpectations(timeout: 5)
        body.typeText("Intro")
        app.buttons["jam-add"].tap()
        for id in ["Image", "Video", "Audio", "Button", "Divider", "Freewall"] {
            XCTAssertTrue(app.buttons[id].waitForExistence(timeout: 3), id)
        }
        app.buttons["Divider"].tap()
        sleep(1)
        XCTAssertTrue((body.value as? String ?? "").contains("---"), body.value as? String ?? "")
        app.buttons["jam-add"].tap()
        app.buttons["Freewall"].tap()
        sleep(1)
        XCTAssertTrue((body.value as? String ?? "").contains("[[freewall]]"))
        app.buttons["jam-add"].tap()
        XCTAssertFalse(app.buttons["Freewall"].isEnabled, "one freewall per post")
        app.buttons["Divider"].coordinate(withNormalizedOffset: .zero).tap()   // close by choosing another divider
        app.buttons["jam-format"].tap()
        XCTAssertTrue(app.buttons["fmt-undo"].isEnabled)
        app.buttons["fmt-undo"].tap()
        let afterUndo = body.value as? String ?? ""
        XCTAssertEqual(afterUndo.components(separatedBy: "---").count - 1, 1, "undo took the last divider back: \(afterUndo)")
        XCTAssertTrue(afterUndo.contains("[[freewall]]"))
        app.buttons["jam-post"].tap()
        let card = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Ten minutes'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 8))
        card.tap()
        XCTAssertTrue(any(app, "post-divider").waitForExistence(timeout: 8), "the reader draws the rule")
        XCTAssertTrue(any(app, "post-freewall").exists, "and where the subscribers' part starts")
    }

    func testTheExitPillShowsOnAnEmptyArticleHidesOnTypingAndTheWholePageScrolls() {
        let app = launch()
        openArticle(app)
        let pill = app.buttons["jam-exit-article"]
        XCTAssertTrue(pill.exists, "shown on an empty article")
        XCTAssertFalse(app.buttons["Back"].exists, "no Back in the bar")
        let title = app.textFields["jam-article-title"].exists ? app.textFields["jam-article-title"] : app.textViews["jam-article-title"]
        title.tap(); title.typeText("T")
        XCTAssertFalse(pill.waitForExistence(timeout: 2), "hidden once typing starts")
        title.typeText(XCUIKeyboardKey.delete.rawValue)
        XCTAssertTrue(pill.waitForExistence(timeout: 3), "back when it is empty again")
        title.typeText("Long one\n\n")
        let body = app.textViews["composer-field"]
        expectation(for: NSPredicate(format: "hasKeyboardFocus == true"), evaluatedWith: body)
        waitForExpectations(timeout: 5)
        let startY = title.frame.minY
        body.typeText((1...40).map { "Line \($0) of the article" }.joined(separator: "\n"))
        sleep(2)
        XCTAssertTrue(!title.exists || !title.isHittable || title.frame.minY < startY - 40, "the title moved up with the page as the body grew")
    }
}
