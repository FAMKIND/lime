import XCTest

/// LIME-176: the composer grows for long messages, with an expand button.
@MainActor
final class Composer176UITests: LimeUITestCase {
    private func openChat() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat"]
        app.launch()
        app.buttons["conversation-row-dm:sam"].tap()
        return app
    }

    private func typeLong(_ app: XCUIApplication, lines: Int) {
        let field = app.textViews["composer-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 8))
        field.tap()
        field.typeText((1...lines).map { "line \($0)" }.joined(separator: "\n"))
        // Typing is queued behind layout: wait for the last line to be in, and the field to settle.
        let last = NSPredicate(format: "value CONTAINS %@", "line \(lines)")
        expectation(for: last, evaluatedWith: field)
        waitForExpectations(timeout: 30)
        sleep(2)
    }

    func testALongTextGrowsTheFieldPastFiveLinesAndKeepsItBelowTheHeader() {
        let app = openChat()
        let field = app.textViews["composer-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 8))
        field.tap()
        field.typeText("short")
        let short = field.frame.height
        field.typeText("\n" + (1...30).map { "line \($0)" }.joined(separator: "\n"))
        let long = field.frame.height
        XCTAssertGreaterThan(long, short * 4, "the field grew with the text (\(short) → \(long))")
        XCTAssertGreaterThan(long, 120, "more than five lines")
        let window = app.windows.firstMatch.frame
        XCTAssertGreaterThan(field.frame.minY, window.height * 0.2, "the header and the top of the messages stay visible")
    }

    func testTheKeyboardHiddenMakesTheFieldTaller() {
        let app = openChat()
        typeLong(app, lines: 40)
        let field = app.textViews["composer-field"]
        let up = field.frame.height
        app.buttons["composer-hide-keyboard"].tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.keyboards.firstMatch)
        waitForExpectations(timeout: 5)
        sleep(1)
        XCTAssertGreaterThan(field.frame.height, up, "taller without the keyboard (\(up) → \(field.frame.height))")
    }

    func testExpandFillsBelowTheHeaderAndCollapseGoesBack() {
        let app = openChat()
        typeLong(app, lines: 40)
        let field = app.textViews["composer-field"]
        let before = field.frame.height
        XCTAssertFalse(app.buttons["composer-collapse"].exists)
        app.buttons["composer-expand"].tap()
        XCTAssertTrue(app.buttons["composer-collapse"].waitForExistence(timeout: 5))
        sleep(1)
        XCTAssertGreaterThan(field.frame.height, before, "expanded is taller")
        XCTAssertGreaterThan(field.frame.minY, 60, "it stops below the status bar and header")
        XCTAssertTrue(app.buttons["composer-plus"].isHittable, "the tool row stays")
        app.buttons["composer-collapse"].tap()
        XCTAssertTrue(app.buttons["composer-expand"].waitForExistence(timeout: 5))
        sleep(1)
        XCTAssertEqual(field.frame.height, before, accuracy: 2)
    }

    func testSendingFromExpandedSendsTheWholeTextAndCollapses() {
        let app = openChat()
        typeLong(app, lines: 12)
        app.buttons["composer-expand"].tap()
        XCTAssertTrue(app.buttons["composer-collapse"].waitForExistence(timeout: 5))
        app.buttons["send-button"].tap()
        XCTAssertFalse(app.buttons["composer-collapse"].waitForExistence(timeout: 2), "sending collapses")
        XCTAssertFalse(app.buttons["composer-expand"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'line 12'")).firstMatch.waitForExistence(timeout: 5), "the whole message arrived")
    }

    /// LIME-176b: in landscape the whole composer, tool row included, sits between the header and the keyboard.
    func testInLandscapeTheWholeComposerFitsBetweenTheHeaderAndTheKeyboard() throws {
        let app = openChat()
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        sleep(2)
        typeLong(app, lines: 40)
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
        for id in ["composer-plus", "composer-aa"] {
            let button = app.buttons[id]
            XCTAssertTrue(button.isHittable, "\(id) is hittable in landscape")
            XCTAssertLessThanOrEqual(button.frame.maxY, keyboard.frame.minY + 1, "\(id) is above the keyboard")
        }
        let field = app.textViews["composer-field"]
        XCTAssertGreaterThan(field.frame.minY, 40, "the field's top is below the header (\(field.frame))")
        app.buttons["composer-expand"].tap()
        XCTAssertTrue(app.buttons["composer-collapse"].waitForExistence(timeout: 5))
        sleep(1)
        XCTAssertTrue(app.buttons["composer-plus"].isHittable, "expanded, the tool row is still reachable")
        XCTAssertGreaterThan(app.textViews["composer-field"].frame.minY, 40)
    }
}
