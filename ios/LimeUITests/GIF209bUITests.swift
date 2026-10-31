import XCTest

/// LIME-209b (demo, two saved GIFs): lime's stickers are the first row of the GIF button and answer "/"; hiding the pack removes them.
@MainActor
final class GIF209bUITests: LimeUITestCase {
    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
    private func gifBubbles(_ app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'attachment-image-' AND label == 'GIF'"))
    }
    private func chat(_ extra: [String] = []) -> (XCUIApplication, XCUIElement) {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "attachments-gif", "-lime-demo-my-gifs"] + extra
        app.launch()
        let field = app.textViews["composer-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        return (app, field)
    }

    private func openGIFSearch(_ app: XCUIApplication) {
        app.buttons["composer-emoji"].tap()
        let tabs = app.segmentedControls["panel-tabs"]
        XCTAssertTrue(tabs.waitForExistence(timeout: 5))
        tabs.buttons["GIFs"].tap()
        app.buttons["panel-search"].tap()
    }

    func testSlashBirthdayShowsLimesBirthdayStickerAndATapSendsIt() {
        let (app, field) = chat()
        let before = gifBubbles(app).count
        field.tap(); field.typeText("/birthday")
        let sticker = any(app, "sticker-slash-happy-birthday")
        XCTAssertTrue(sticker.waitForExistence(timeout: 5), "lime's birthday sticker")
        XCTAssertEqual(sticker.label, "lime sticker: Happy birthday!")
        sticker.tap()
        expectation(for: NSPredicate(format: "count > %d", before), evaluatedWith: gifBubbles(app))
        waitForExpectations(timeout: 8)
        XCTAssertFalse((field.value as? String ?? "").contains("/birthday"), "the /words are cleared")
    }

    func testTheGIFButtonShowsTheLimeRowFirstAndTypingNarrowsIt() {
        let (app, _) = chat()
        openGIFSearch(app)
        XCTAssertTrue(any(app, "sticker-row").waitForExistence(timeout: 5), "the lime row")
        XCTAssertTrue(any(app, "sticker-cell-thank-you").exists)
        XCTAssertTrue(any(app, "sticker-cell-summer").exists || any(app, "sticker-row").exists)
        let search = app.textFields["gif-search"]
        search.tap(); search.typeText("snow")
        XCTAssertTrue(any(app, "sticker-cell-snow-day").waitForExistence(timeout: 5))
        XCTAssertFalse(any(app, "sticker-cell-thank-you").exists)
    }

    func testHidingThePackRemovesTheRowAndTheSlashStickers() {
        let (app, field) = chat(["-lime.showStickers", "NO"])
        openGIFSearch(app)
        XCTAssertTrue(app.textFields["gif-search"].waitForExistence(timeout: 5))
        XCTAssertFalse(any(app, "sticker-row").exists, "no lime row")
        app.buttons["gif-close"].tap()
        field.tap(); field.typeText("/birthday")
        XCTAssertFalse(any(app, "sticker-slash-happy-birthday").waitForExistence(timeout: 2))
    }
}
