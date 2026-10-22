import XCTest

/// LIME-188r: arranging an article's blocks: a tap on a block opens Move up / Move down / Edit / Delete, the long-press drag moves it, undo puts it back.
@MainActor
final class Jam188rUITests: LimeUITestCase {
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "jam"]
        app.launch()
        return app
    }

    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    /// First, a picture, Second, a Subscribe button.
    private func build(_ app: XCUIApplication) -> XCUIElement {
        XCTAssertTrue(app.buttons["new-jam-post"].waitForExistence(timeout: 10))
        app.buttons["new-jam-post"].tap()
        XCTAssertTrue(app.buttons["jam-write-article"].waitForExistence(timeout: 8))
        app.buttons["jam-write-article"].tap()
        let title = app.textFields["jam-article-title"].exists ? app.textFields["jam-article-title"] : app.textViews["jam-article-title"]
        title.tap(); title.typeText("Arranged\n\n")
        let body = app.textViews["composer-field"]
        expectation(for: NSPredicate(format: "hasKeyboardFocus == true"), evaluatedWith: body)
        waitForExpectations(timeout: 5)
        body.typeText("First")
        app.buttons["jam-add"].tap(); app.buttons["Image"].tap(); sleep(1)
        body.typeText("Second")
        app.buttons["jam-add"].tap(); app.buttons["Button"].tap()
        app.buttons["button-preset-subscribe"].tap()
        sleep(1)
        return body
    }

    private func order(_ body: XCUIElement) -> [String] {
        let value = body.value as? String ?? ""
        return value.components(separatedBy: "\n").filter { !$0.isEmpty }.map { $0.hasPrefix("![") ? "picture" : $0.hasPrefix("[[") ? "button" : $0 }
    }

    func testMoveDownAndMoveUpFromTheBlockMenuReorderAndUndoPutsItBack() {
        let app = launch()
        let body = build(app)
        XCTAssertEqual(order(body), ["First", "picture", "Second", "button"])
        let picture = any(app, "block-0")
        XCTAssertTrue(picture.waitForExistence(timeout: 5), "each block has an accessible marker")
        XCTAssertEqual(picture.label, "Picture block")
        picture.tap()
        any(app, "block-move-down").tap()
        XCTAssertEqual(order(body), ["First", "Second", "picture", "button"], "Move down")
        // The button, up past the picture.
        let button = any(app, "block-1")
        XCTAssertTrue(button.label.hasPrefix("Button block"))
        button.tap()
        any(app, "block-move-up").tap()
        XCTAssertEqual(order(body), ["First", "Second", "button", "picture"], "Move up")
        // Undo, one step each.
        app.buttons["jam-format"].tap()
        app.buttons["fmt-undo"].tap()
        XCTAssertEqual(order(body), ["First", "Second", "picture", "button"], "undo puts it back")
        app.buttons["fmt-undo"].tap()
        XCTAssertEqual(order(body), ["First", "picture", "Second", "button"])
        // Delete.
        any(app, "block-1").tap()
        any(app, "block-delete").tap()
        XCTAssertEqual(order(body), ["First", "picture", "Second"], "Delete")
    }

    func testPostedArticleShowsTheArrangedOrder() {
        let app = launch()
        let body = build(app)
        any(app, "block-0").tap()
        any(app, "block-move-down").tap()
        XCTAssertEqual(order(body), ["First", "Second", "picture", "button"])
        app.buttons["jam-post"].tap()
        app.showJamArticles()
        let card = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Arranged'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 8))
        card.tap()
        let second = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Second'")).firstMatch
        XCTAssertTrue(second.waitForExistence(timeout: 8))
        let picture = any(app, "jam-inline-0")
        XCTAssertTrue(picture.waitForExistence(timeout: 8))
        XCTAssertGreaterThan(picture.frame.minY, second.frame.minY, "the reader shows the picture after the second paragraph")
    }
}
