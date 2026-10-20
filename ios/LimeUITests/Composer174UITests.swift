import XCTest

/// LIME-174: the composer stays above the keyboard through emoji and formatting, and the newest message stays above the composer.
@MainActor
final class Composer174UITests: LimeUITestCase {
    private func openChat(_ screen: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat"] + (screen.map { ["-lime-demo-screen", $0] } ?? [])
        app.launch()
        if screen == nil { app.buttons["conversation-row-dm:sam"].tap() }
        return app
    }

    private func assertAbove(_ app: XCUIApplication, _ note: String) {
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5), "\(note): the keyboard is up")
        sleep(1)
        for id in ["composer-plus", "composer-emoji", "composer-aa"] {
            let button = app.buttons[id]
            XCTAssertTrue(button.waitForExistence(timeout: 5), "\(note): \(id) exists")
            XCTAssertTrue(button.isHittable, "\(note): \(id) is hittable")
            XCTAssertLessThanOrEqual(button.frame.maxY, keyboard.frame.minY + 1, "\(note): \(id) is above the keyboard (\(button.frame) vs \(keyboard.frame))")
        }
    }

    private func type(_ app: XCUIApplication, _ text: String) {
        let field = app.textViews["composer-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 8))
        field.tap()
        field.typeText(text)
    }

    /// Type a word, then 😊, then Aa: the whole tool row stays above the keyboard, and Aa works at once (no emoji needs picking first).
    func testTypeThenEmojiThenAaKeepsEverythingAboveTheKeyboardAndAaWorksAtOnce() {
        let app = openChat()
        type(app, "hello")
        assertAbove(app, "typing")
        app.buttons["composer-emoji"].tap()
        XCTAssertEqual(app.buttons["composer-emoji"].label, "Emoji", "the 😊 stays a face")
        XCTAssertTrue(app.buttons["composer-emoji"].isSelected, "highlighted while the emoji keyboard shows")
        assertAbove(app, "emoji keyboard")
        app.buttons["composer-aa"].tap()
        XCTAssertTrue(app.buttons["fmt-bold"].waitForExistence(timeout: 5), "Aa opened the formatting strip with no emoji picked")
        XCTAssertFalse(app.buttons["composer-emoji"].isSelected, "and the emoji highlight is gone: the text keyboard is back")
        assertAbove(app, "after Aa")
    }

    /// 😊 then + opens the add sheet at once.
    func testEmojiThenPlusOpensTheAddSheetAtOnce() {
        let app = openChat()
        type(app, "hi")
        app.buttons["composer-emoji"].tap()
        assertAbove(app, "emoji keyboard")
        app.buttons["composer-plus"].tap()
        XCTAssertTrue(app.buttons["add-close"].waitForExistence(timeout: 5), "the add sheet opened without picking an emoji")
    }

    /// The same button again goes back to the text keyboard.
    func testTheEmojiButtonTogglesBetweenTheTwoKeyboards() {
        let app = openChat()
        type(app, "ok")
        for round in 1...3 {
            app.buttons["composer-emoji"].tap()
            XCTAssertTrue(app.buttons["composer-emoji"].isSelected, "round \(round): emoji keyboard up (highlighted)")
            XCTAssertEqual(app.buttons["composer-emoji"].label, "Emoji", "round \(round): still a face")
            assertAbove(app, "round \(round) emoji")
            app.buttons["composer-emoji"].tap()
            XCTAssertFalse(app.buttons["composer-emoji"].isSelected, "round \(round): text keyboard back (not highlighted)")
            assertAbove(app, "round \(round) text")
        }
    }

    /// Other orders: Aa then 😊 then type; 😊 then type.
    func testAaThenEmojiThenTypingAndEmojiThenTyping() {
        let app = openChat()
        type(app, "a")
        app.buttons["composer-aa"].tap()
        XCTAssertTrue(app.buttons["fmt-bold"].waitForExistence(timeout: 5))
        app.buttons["composer-emoji"].tap()
        assertAbove(app, "Aa then emoji")
        app.buttons["composer-emoji"].tap()
        app.textViews["composer-field"].typeText("b")
        assertAbove(app, "then typing")
        app.buttons["composer-emoji"].tap()
        assertAbove(app, "emoji again")
        app.buttons["composer-emoji"].tap()
        app.textViews["composer-field"].typeText("c")
        assertAbove(app, "typing again")
    }

    /// At the bottom of a chat, opening the keyboard keeps the newest message above the composer.
    func testFocusingTheComposerAtTheBottomOfAChatKeepsTheNewestMessageVisible() {
        let app = openChat()
        let newest = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Week 4 plan.pdf'")).firstMatch
        XCTAssertTrue(newest.waitForExistence(timeout: 8))
        app.textViews["composer-field"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        sleep(1)
        let composer = app.textViews["composer-field"].frame
        XCTAssertLessThanOrEqual(newest.frame.maxY, composer.minY + 2, "the newest message is above the composer: \(newest.frame) vs \(composer)")
        XCTAssertGreaterThan(newest.frame.minY, 0)
    }

    func testFocusingTheComposerInRepliesKeepsTheNewestReplyVisible() {
        let app = openChat("thread-many")
        let newest = app.staticTexts["Reply number 30"]
        XCTAssertTrue(newest.waitForExistence(timeout: 8))
        app.textViews["composer-field"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        sleep(1)
        let composer = app.textViews["composer-field"].frame
        XCTAssertLessThanOrEqual(newest.frame.maxY, composer.minY + 2, "the newest reply is above the composer: \(newest.frame) vs \(composer)")
    }

    // MARK: 😊 returns to the state before; the strip sits under the composer

    /// Reading (no keyboard): 😊 shows the emoji keyboard; 😊 again closes the keyboard and the whole chat shows.
    func testEmojiFromReadingClosesTheKeyboardOnTheSecondTap() {
        let app = openChat()
        XCTAssertTrue(app.buttons["composer-emoji"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.keyboards.firstMatch.exists, "reading: no keyboard")
        app.buttons["composer-emoji"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "the emoji keyboard is up")
        XCTAssertTrue(app.buttons["composer-emoji"].isSelected)
        app.buttons["composer-emoji"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5), "the second tap closes the keyboard: back to reading")
        XCTAssertFalse(app.buttons["composer-emoji"].isSelected)
        XCTAssertTrue(app.buttons["composer-plus"].isHittable, "the whole chat and the composer show")
    }

    /// Writing: 😊 shows the emoji keyboard; 😊 again returns to the text keyboard with the text and the caret where they were.
    func testEmojiFromWritingReturnsToTheTextKeyboardWithTheCaretKept() {
        let app = openChat()
        type(app, "ab")
        app.buttons["composer-emoji"].tap()
        XCTAssertTrue(app.buttons["composer-emoji"].isSelected)
        app.buttons["composer-emoji"].tap()
        XCTAssertFalse(app.buttons["composer-emoji"].isSelected)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "the keyboard stays: the text keyboard is back")
        let field = app.textViews["composer-field"]
        field.typeText("c")
        XCTAssertEqual(field.value as? String, "abc", "typing continues at the caret")
        assertAbove(app, "back on the text keyboard")
    }

    /// The formatting strip is wholly under the composer's tool row and above the keyboard: with the text keyboard, with the emoji keyboard, and with the
    /// strip already open when 😊 is tapped (the screenshot: the strip drew over + 😊 Aa).
    func testTheFormattingStripSitsBetweenTheComposerAndTheKeyboardWithEveryKeyboard() {
        func assertStripBelowComposerAboveKeyboard(_ app: XCUIApplication, _ note: String) {
            let keyboard = app.keyboards.firstMatch
            let strip = app.descendants(matching: .any).matching(identifier: "fmt-scroll").firstMatch
            XCTAssertTrue(strip.waitForExistence(timeout: 5), "\(note): the strip is there")
            sleep(1)
            for id in ["composer-plus", "composer-emoji", "composer-aa"] {
                let button = app.buttons[id]
                XCTAssertLessThanOrEqual(button.frame.maxY, strip.frame.minY + 1, "\(note): the strip does not cover \(id): \(button.frame) vs strip \(strip.frame)")
                XCTAssertTrue(button.isHittable, "\(note): \(id) is hittable")
            }
            XCTAssertLessThanOrEqual(strip.frame.maxY, keyboard.frame.minY + 1, "\(note): the strip is above the keyboard: \(strip.frame) vs \(keyboard.frame)")
        }
        let app = openChat()
        type(app, "x")
        app.buttons["composer-aa"].tap()
        assertStripBelowComposerAboveKeyboard(app, "text keyboard")
        app.buttons["composer-emoji"].tap()
        XCTAssertTrue(app.buttons["composer-emoji"].isSelected)
        assertStripBelowComposerAboveKeyboard(app, "emoji keyboard, strip already open")
        app.buttons["composer-aa"].tap()   // Aa from the emoji keyboard: the text keyboard with the strip
        assertStripBelowComposerAboveKeyboard(app, "Aa from the emoji keyboard")
    }
}
