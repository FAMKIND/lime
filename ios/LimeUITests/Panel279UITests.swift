import XCTest

/// LIME-279 (demo, two saved GIFs): 😊 opens a panel with Emoji, GIFs and Stickers; a GIF or a sticker sends in one tap; the last tab comes back.
@MainActor
final class Panel279UITests: LimeUITestCase {
    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
    private func gifBubbles(_ app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'attachment-image-' AND label == 'GIF'"))
    }
    private func chat() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "attachments-gif", "-lime-demo-my-gifs", "-lime.composerPanelTab", "Emoji"]
        app.launch()
        XCTAssertTrue(app.textViews["composer-field"].waitForExistence(timeout: 10))
        return app
    }

    func testTheEmojiButtonOpensThreeTabsAndThereIsNoSeparateGIFButton() {
        let app = chat()
        XCTAssertFalse(app.buttons["composer-gif"].exists, "the GIF button went into the panel")
        app.buttons["composer-emoji"].tap()
        let tabs = app.segmentedControls["panel-tabs"]
        XCTAssertTrue(tabs.waitForExistence(timeout: 5))
        for name in ["Emoji", "GIFs", "Stickers"] { XCTAssertTrue(tabs.buttons[name].exists, name) }
        XCTAssertTrue(tabs.buttons["Emoji"].isSelected, "Emoji is the first tab")
        XCTAssertFalse(app.buttons["panel-search"].exists, "Search is for GIFs and stickers")
    }

    func testAGIFInTheGIFsTabSendsInOneTapAndThePanelGoes() {
        let app = chat()
        let before = gifBubbles(app).count
        app.buttons["composer-emoji"].tap()
        app.segmentedControls["panel-tabs"].buttons["GIFs"].tap()
        let gif = any(app, "panel-gif-demo-gif-0")
        XCTAssertTrue(gif.waitForExistence(timeout: 5), "my GIFs are in the grid")
        gif.tap()
        expectation(for: NSPredicate(format: "count > %d", before), evaluatedWith: gifBubbles(app))
        waitForExpectations(timeout: 8)
        XCTAssertFalse(app.segmentedControls["panel-tabs"].exists, "the panel closed")
    }

    func testAStickerInTheStickersTabSendsAndTheLastTabComesBack() {
        let app = chat()
        let before = gifBubbles(app).count
        app.buttons["composer-emoji"].tap()
        app.segmentedControls["panel-tabs"].buttons["Stickers"].tap()
        let sticker = any(app, "panel-sticker-thank-you")
        XCTAssertTrue(sticker.waitForExistence(timeout: 5))
        XCTAssertEqual(sticker.label, "lime sticker: Thank you!")
        sticker.tap()
        expectation(for: NSPredicate(format: "count > %d", before), evaluatedWith: gifBubbles(app))
        waitForExpectations(timeout: 8)
        app.buttons["composer-emoji"].tap()
        let tabs = app.segmentedControls["panel-tabs"]
        XCTAssertTrue(tabs.waitForExistence(timeout: 5))
        XCTAssertTrue(tabs.buttons["Stickers"].isSelected, "the last tab used is remembered")
        tabs.buttons["Emoji"].tap()
        XCTAssertTrue(tabs.buttons["Emoji"].isSelected, "and back to the emoji keyboard")
    }

    func testTheSlashStripStillWorks() {
        let app = chat()
        let field = app.textViews["composer-field"]
        field.tap(); field.typeText("/birth")
        XCTAssertTrue(any(app, "gif-slash-demo-gif-0").waitForExistence(timeout: 5))
    }
}
