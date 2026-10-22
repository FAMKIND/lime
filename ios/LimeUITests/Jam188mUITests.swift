import XCTest

/// LIME-188m: the post-as chip lines up with the text; Post stays enabled after a button; the button sheet shows the https address it will open.
@MainActor
final class Jam188mUITests: LimeUITestCase {
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "jam"]
        app.launch()
        return app
    }

    func testThePostAsChipSitsAtTheTextMarginInBothModes() {
        let app = launch()
        app.buttons["new-jam-post"].tap()
        let chip = app.buttons["jam-post-as"]
        XCTAssertTrue(chip.waitForExistence(timeout: 8))
        XCTAssertEqual(chip.frame.minX, 20, accuracy: 1, "the avatar's left edge is the text's margin")
        app.buttons["jam-write-article"].tap()
        let title = app.textFields["jam-article-title"].exists ? app.textFields["jam-article-title"] : app.textViews["jam-article-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(chip.frame.minX, title.frame.minX, accuracy: 1, "and the title's")
    }

    func testPostStaysEnabledAfterAButtonAndTheSheetShowsTheHttpsAddress() {
        let app = launch()
        app.buttons["new-jam-post"].tap()
        app.buttons["jam-write-article"].tap()
        let title = app.textFields["jam-article-title"].exists ? app.textFields["jam-article-title"] : app.textViews["jam-article-title"]
        title.tap(); title.typeText("Ten minutes\n\n")
        let body = app.textViews["composer-field"]
        expectation(for: NSPredicate(format: "hasKeyboardFocus == true"), evaluatedWith: body)
        waitForExpectations(timeout: 5)
        body.typeText("Words first")
        app.buttons["jam-add"].tap()
        let tile = app.descendants(matching: .any).matching(identifier: "add-recent-0").firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 8))
        tile.tap(); app.buttons["add-selected"].tap()
        sleep(1)
        XCTAssertTrue(app.buttons["jam-post"].isEnabled, "enabled with a title, words and a photo")
        app.buttons["jam-format"].tap()
        let scroll = app.scrollViews["fmt-scroll"]
        for _ in 0..<4 where !app.buttons["fmt-button"].isHittable { scroll.swipeLeft() }
        app.buttons["fmt-button"].tap()
        let text = app.textFields["button-text"]
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        text.typeText("Worksheet")
        let url = app.textFields["button-url"]
        url.tap(); url.typeText("limemessenger.com")
        XCTAssertTrue(app.staticTexts["button-shown"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.staticTexts["button-shown"].label, "Opens https://limemessenger.com")
        app.buttons["button-apply"].tap()
        sleep(1)
        XCTAssertTrue(app.buttons["jam-post"].isEnabled, "Post is still enabled after the button")
        XCTAssertTrue((body.value as? String ?? "").contains("[[Worksheet]](https://limemessenger.com)"), body.value as? String ?? "")
    }
}
