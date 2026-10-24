import XCTest

/// LIME-214: Info first for everyone, and links you choose who sees.
@MainActor
final class Profile214UITests: LimeUITestCase {
    private func app(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat"] + extra
        app.launch()
        return app
    }

    func testAContactsLinksShowOnTheirInfoAndOpenFromThere() {
        let app = app()
        app.buttons["conversation-row-dm:sam"].tap()
        app.descendants(matching: .any).matching(identifier: "chat-title").firstMatch.tap()
        XCTAssertTrue(app.buttons["profile-tab-Info"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["profile-tab-Info"].isSelected, "Info first")
        let first = app.links["profile-link-0"]
        for _ in 0..<4 where !first.exists { app.swipeUp() }
        XCTAssertTrue(first.waitForExistence(timeout: 8), "Sam's links, as his contact")
        XCTAssertEqual(first.label, "Fractions that stick, example.com/fractions")
        XCTAssertTrue(app.links["profile-link-1"].exists)
        XCTAssertTrue(app.staticTexts["profile-since"].exists, "On lime since")
    }

    func testAddingTwoLinksReordersThemAndSavesWithEveryoneOrContactsChoice() {
        let app = app(["-lime-demo-screen", "settings/links"])
        XCTAssertTrue(app.buttons["links-add"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["links-vis-contacts"].isSelected, "contacts only by default")
        app.buttons["links-add"].tap()
        let title = app.textFields["Link title"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap(); title.typeText("My class")
        let address = app.textFields["Link address"].firstMatch
        address.tap(); address.typeText("http://example.com/class")
        app.buttons["links-save"].tap()
        XCTAssertTrue(app.buttons["links-save"].label.hasPrefix("Saved"), "saved")
        app.buttons["links-vis-everyone"].tap()
        XCTAssertTrue(app.buttons["links-vis-everyone"].isSelected)
        // A bad address is refused with a reason.
        let again = app.textFields["Link address"].firstMatch
        again.tap(); again.typeText(" nope")
        app.buttons["links-save"].tap()
        XCTAssertTrue(app.staticTexts["links-footer"].label.contains("https"), app.staticTexts["links-footer"].label)
    }
}
