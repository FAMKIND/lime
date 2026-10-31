import XCTest

/// LIME-208 (demo, two saved GIFs): "/" and words show matching GIFs above the field; a tap sends one and clears the words; deleting "/" closes the strip;
/// Send without picking sends the text as typed.
@MainActor
final class GIF208UITests: LimeUITestCase {
    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
    private func gifBubbles(_ app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'attachment-image-' AND label == 'GIF'"))
    }
    private func chat() -> (XCUIApplication, XCUIElement) {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "attachments-gif", "-lime-demo-my-gifs"]
        app.launch()
        let field = app.textViews["composer-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        return (app, field)
    }

    func testSlashAndWordsShowTheMatchingGIFAndATapSendsItAndEmptiesTheField() {
        let (app, field) = chat()
        let before = gifBubbles(app).count
        field.tap(); field.typeText("/birth")
        let strip = any(app, "gif-slash-strip")
        XCTAssertTrue(strip.waitForExistence(timeout: 5), "the strip is above the field")
        XCTAssertTrue(any(app, "gif-slash-demo-gif-0").exists, "the birthday GIF")
        XCTAssertFalse(any(app, "gif-slash-demo-gif-1").exists, "not the thank-you one")
        any(app, "gif-slash-demo-gif-0").tap()
        expectation(for: NSPredicate(format: "count > %d", before), evaluatedWith: gifBubbles(app))
        waitForExpectations(timeout: 8)
        XCTAssertFalse(strip.exists, "the strip closes")
        XCTAssertFalse((field.value as? String ?? "").contains("/birth"), "and the /words are cleared")
    }

    func testAnEmptySlashShowsRecentOnesNoMatchSaysSoAndDeletingTheSlashClosesTheStrip() {
        let (app, field) = chat()
        field.tap(); field.typeText("/")
        XCTAssertTrue(any(app, "gif-slash-demo-gif-0").waitForExistence(timeout: 5) && any(app, "gif-slash-demo-gif-1").exists, "an empty / shows my recent GIFs")
        field.typeText("zzzz")
        XCTAssertTrue(any(app, "gif-slash-empty").waitForExistence(timeout: 5))
        XCTAssertTrue(any(app, "gif-slash-empty").label.contains("zzzz"), any(app, "gif-slash-empty").label)
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 5))
        XCTAssertFalse(any(app, "gif-slash-strip").waitForExistence(timeout: 2), "no slash, no strip")
        XCTAssertFalse(any(app, "gif-slash-empty").exists)
    }

    func testSendingASlashMessageWithoutPickingSendsTheTextAsTyped() {
        let (app, field) = chat()
        field.tap(); field.typeText("/hello")
        XCTAssertTrue(any(app, "gif-slash-empty").waitForExistence(timeout: 5))
        app.buttons["send-button"].tap()
        XCTAssertTrue(app.staticTexts["/hello"].waitForExistence(timeout: 8), "the text went as typed")
    }
}
