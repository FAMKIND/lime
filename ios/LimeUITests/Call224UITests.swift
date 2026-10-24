import XCTest

/// LIME-224: one call control everywhere (the camera, Voice or Video), separate profile bubbles, and the call tab's search is the one Search.
@MainActor
final class Call224UITests: LimeUITestCase {
    private func app(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat"] + extra
        app.launch()
        return app
    }

    func testTheChatHeadersCallButtonOffersVoiceOrVideo() {
        let app = app()
        app.buttons["conversation-row-dm:sam"].tap()
        let call = app.buttons["chat-call-button"]
        XCTAssertTrue(call.waitForExistence(timeout: 8))
        call.tap()
        XCTAssertTrue(app.buttons["Voice call"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Video call"].firstMatch.exists)
    }

    func testAProfileHasThreeSeparateBubblesAndCallOpensTheMenu() {
        let app = app()
        app.buttons["conversation-row-dm:sam"].tap()
        app.descendants(matching: .any).matching(identifier: "chat-title").firstMatch.tap()
        let message = app.buttons["profile-message"], call = app.buttons["profile-call-button"], more = app.buttons["profile-more"]
        XCTAssertTrue(call.waitForExistence(timeout: 10))
        XCTAssertTrue(message.frame.maxX < call.frame.minX && call.frame.maxX < more.frame.minX, "in order: Message, Call, More")
        XCTAssertGreaterThan(call.frame.minX - message.frame.maxX, 2, "apart, not one group")
        XCTAssertFalse(app.buttons["profile-voice"].exists || app.buttons["profile-video"].exists)
        call.tap()
        XCTAssertTrue(app.buttons["Voice call"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Video call"].firstMatch.exists)
    }

    func testNewCallRowsHaveOneCallButtonEach() {
        let app = app(["-lime-demo-calls"])
        app.tabBars.buttons["call"].tap()
        app.buttons["new-call-button"].tap()
        XCTAssertTrue(app.buttons["new-call-lee-button"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["new-call-voice-lee"].exists || app.buttons["new-call-video-lee"].exists)
    }

    func testTheCallTabsMagnifierIsTheOneSearchWithCallsFirst() {
        let app = app(["-lime-demo-calls"])
        app.tabBars.buttons["call"].tap()
        app.buttons["calls-search-button"].tap()
        let field = app.textFields["search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 8))
        XCTAssertEqual(field.placeholderValue, "Search people, chats, messages and jam")
        field.tap(); field.typeText("lee")
        let lee = app.buttons["calls-search-lee-button"]
        XCTAssertTrue(lee.waitForExistence(timeout: 8), "Lee under Calls with the call control")
        XCTAssertTrue(app.staticTexts["Calls"].exists)
    }
}
