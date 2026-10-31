import XCTest

/// LIME-207 (demo): save a GIF from a chat to My GIFs, find it with a word in the GIF button's search, tap to send it; Remove all in Settings.
@MainActor
final class GIF207UITests: LimeUITestCase {
    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
    private func gifBubbles(_ app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'attachment-image-' AND label == 'GIF'"))
    }

    func testSaveAGIFFromAChatFindItByAWordAndTapToSendIt() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "attachments-gif"]
        app.launch()
        let bubble = gifBubbles(app).firstMatch
        XCTAssertTrue(bubble.waitForExistence(timeout: 10))
        let before = gifBubbles(app).count
        bubble.press(forDuration: 0.8)
        let save = app.buttons["action-save-gif"]
        XCTAssertTrue(save.waitForExistence(timeout: 5), "Save to my GIFs is in the long-press menu")
        save.tap()
        // The GIF button: a sheet with search; the message it came with ("Happy Friday!") finds it.
        let button = app.buttons["composer-gif"]
        XCTAssertTrue(button.waitForExistence(timeout: 8))
        button.tap()
        let search = app.textFields["gif-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap(); search.typeText("friday")
        let cell = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'gif-cell-'")).firstMatch
        XCTAssertTrue(cell.waitForExistence(timeout: 5), "found by a word of its message")
        XCTAssertTrue(cell.label.hasPrefix("GIF"), cell.label)
        search.clearText()
        search.typeText("zzzz")
        XCTAssertTrue(any(app, "gif-empty").waitForExistence(timeout: 5), "no match says so")
        search.clearText(); search.typeText("fri")
        XCTAssertTrue(cell.waitForExistence(timeout: 5))
        cell.tap()
        // One tap sent it.
        expectation(for: NSPredicate(format: "count > %d", before), evaluatedWith: gifBubbles(app))
        waitForExpectations(timeout: 8)
    }

    func testSettingsShowsTheCountAndSpaceAndRemoveAllWaitsForAGIF() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "settings/my-gifs"]
        app.launch()
        XCTAssertTrue(any(app, "my-gifs-count").waitForExistence(timeout: 10))
        XCTAssertEqual(any(app, "my-gifs-count").label, "0", "nothing saved yet")
        XCTAssertTrue(any(app, "my-gifs-space").exists)
        XCTAssertFalse(app.buttons["my-gifs-remove-all"].isEnabled, "nothing to remove")
    }
}

private extension XCUIElement {
    func clearText() {
        guard let text = value as? String, !text.isEmpty else { return }
        tap()
        typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: text.count))
    }
}
