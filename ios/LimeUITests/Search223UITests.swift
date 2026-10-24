import XCTest

/// LIME-223: jam posts are found by Search; opened from jam, the jam section is first.
@MainActor
final class Search223UITests: LimeUITestCase {
    private func launch(_ screen: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", screen]
        app.launch()
        return app
    }

    func testSearchingFromJamListsThePostUnderJamFirstAndOpensIt() {
        let app = launch("jam-following")
        app.buttons["jam-search-button"].tap()
        let field = app.textFields["search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 8))
        XCTAssertEqual(field.placeholderValue, "Search people, chats, messages and jam")
        field.tap(); field.typeText("fractions")
        let hit = app.buttons["search-jam-demo-post-1"]
        XCTAssertTrue(hit.waitForExistence(timeout: 8), "Equivalent fractions in ten minutes")
        XCTAssertTrue(hit.label.contains("Equivalent fractions"), hit.label)
        let people = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'search-person-'")).firstMatch
        if people.exists { XCTAssertLessThan(hit.frame.minY, people.frame.minY, "jam first") }
        hit.tap()
        XCTAssertTrue(app.descendants(matching: .any)["jam-article-page"].waitForExistence(timeout: 8), "the post opens")
    }

    func testFromLinkThePostIsFoundToo() {
        let app = launch("jam-following")
        app.tabBars.buttons["link"].tap()
        app.buttons["messages-search-button"].tap()
        let field = app.textFields["search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 8))
        field.tap(); field.typeText("fractions")
        XCTAssertTrue(app.buttons["search-jam-demo-post-1"].waitForExistence(timeout: 8))
    }
}
