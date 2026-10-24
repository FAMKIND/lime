import XCTest

/// LIME-205: find teachers from Search (demo).
@MainActor
final class Search205UITests: LimeUITestCase {
    private func launch(_ screen: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", screen]
        app.launch()
        return app
    }

    func testTypingAContactsNameShowsThemUnderPeople() {
        let app = launch("search-name")   // "lee"
        XCTAssertTrue(app.textFields["search-field"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.textFields["search-field"].placeholderValue, "Search people, chats, messages and jam")
        XCTAssertTrue(app.buttons["search-person-lee"].waitForExistence(timeout: 5), "Lee Wong under People")
        XCTAssertTrue(app.buttons["search-invite"].exists, "Invite a teacher is the last row")
        XCTAssertTrue(app.buttons["search-find-on-lime"].exists, "\"lee\" is also a whole username, so the exact lookup is offered under People")
    }

    func testAUsernameOffersTheExactLookupAndPressingItShowsThePersonWithMessage() {
        let app = launch("search")
        let field = app.textFields["search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        if app.buttons["search-clear"].exists { app.buttons["search-clear"].tap() }
        field.tap(); field.typeText("grace.h")
        let find = app.buttons["search-find-on-lime"]
        XCTAssertTrue(find.waitForExistence(timeout: 5))
        XCTAssertEqual(find.label, "Find @grace.h on lime, button")
        XCTAssertFalse(app.staticTexts["find-result-name"].exists, "nothing is looked up while typing")
        find.tap()
        XCTAssertTrue(app.staticTexts["find-result-name"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["find-result-name"].label, "Grace Hopper")
    }

    func testTheHintOffersTheLookupAndInvite() {
        let app = launch("search")
        XCTAssertTrue(app.textFields["search-field"].waitForExistence(timeout: 10))
        if app.buttons["search-clear"].exists { app.buttons["search-clear"].tap() }
        XCTAssertTrue(app.staticTexts["Find a teacher by their username or email."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["search-invite"].exists)
    }
}
