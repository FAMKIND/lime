import XCTest

/// LIME-279 (demo, two saved GIFs): 😊 opens a panel with Emoji, GIFs and Stickers; a GIF or a sticker sends in one tap; the last tab comes back.
@MainActor
final class Panel279UITests: LimeUITestCase {
    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
    private func gifBubbles(_ app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'attachment-image-' AND (label == 'GIF' OR label == 'Sticker')"))
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

    /// LIME-279b: on GIFs and Stickers the tabs are inside the panel (one surface), and the search is ours, above the keyboard it brings up.
    func testSearchIsOursAndCancelGoesBackToThePanel() {
        let app = chat()
        let before = gifBubbles(app).count
        app.buttons["composer-emoji"].tap()
        app.segmentedControls["panel-tabs"].buttons["GIFs"].tap()
        let search = app.buttons["panel-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5), "🔍 is in the panel's top")
        let bar = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] 'Search Emoji' OR identifier CONTAINS[c] 'Search Emoji' OR placeholderValue CONTAINS[c] 'Search Emoji'")).firstMatch
        XCTAssertFalse(bar.exists, "no system emoji search bar on GIFs")
        search.tap()
        let field = app.textFields["panel-search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("birth")
        XCTAssertTrue(any(app, "panel-found-gif-demo-gif-0").waitForExistence(timeout: 5), "my birthday GIF is found")
        XCTAssertFalse(any(app, "panel-found-gif-demo-gif-1").exists, "not the thank-you one")
        app.buttons["panel-search-cancel"].tap()
        XCTAssertTrue(app.segmentedControls["panel-tabs"].waitForExistence(timeout: 5), "Cancel returns to the panel")
        XCTAssertFalse(field.exists)
        // And a search that sends.
        app.buttons["panel-search"].tap()
        let again = app.textFields["panel-search-field"]
        XCTAssertTrue(again.waitForExistence(timeout: 5)); again.typeText("birth")
        any(app, "panel-found-gif-demo-gif-0").tap()
        expectation(for: NSPredicate(format: "count > %d", before), evaluatedWith: gifBubbles(app))
        waitForExpectations(timeout: 8)
        XCTAssertFalse(app.segmentedControls["panel-tabs"].exists, "everything closed")
    }

    func testAStickerSitsBareInTheChatAtAFixedSize() {
        let app = chat()
        app.buttons["composer-emoji"].tap()
        app.segmentedControls["panel-tabs"].buttons["Stickers"].tap()
        app.buttons["panel-search"].tap()
        let field = app.textFields["panel-search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.typeText("snow")
        let found = any(app, "panel-found-sticker-snow-day")
        XCTAssertTrue(found.waitForExistence(timeout: 5))
        found.tap()
        let images = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'attachment-image-' AND label == 'Sticker'"))
        XCTAssertTrue(images.firstMatch.waitForExistence(timeout: 8), "it is a sticker in the chat")
        let frame = images.firstMatch.frame
        XCTAssertEqual(frame.width, 160, accuracy: 2); XCTAssertEqual(frame.height, 160, accuracy: 2)
        XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "label == 'GIF'")).element(boundBy: 99).exists)
    }

    func testTheSlashStripStillWorks() {
        let app = chat()
        let field = app.textViews["composer-field"]
        field.tap(); field.typeText("/birth")
        XCTAssertTrue(any(app, "gif-slash-demo-gif-0").waitForExistence(timeout: 5))
    }
}
