import XCTest

/// LIME-277d (demo): a chat's own wallpaper and bubble colour: only that chat changes; Use for all chats; Reset.
@MainActor
final class Chat277dUITests: LimeUITestCase {
    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    private func openSamAppearance(_ app: XCUIApplication) {
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "chat"]
        app.launch()
        let title = any(app, "chat-title")
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        title.tap()
        XCTAssertTrue(app.buttons["profile-more"].waitForExistence(timeout: 8))
        app.buttons["profile-more"].tap()
        let entry = app.buttons["profile-chat-appearance"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5), "Chat appearance is in the person's menu")
        entry.tap()
        XCTAssertTrue(app.buttons["chat-use-all"].waitForExistence(timeout: 8) || app.buttons["chat-wallpaper-meadow"].waitForExistence(timeout: 8))
    }

    private func scrollTo(_ element: XCUIElement, _ app: XCUIApplication) {
        for _ in 0..<6 where !element.isHittable { app.swipeUp() }
    }

    func testAWallpaperAndABubbleColourChangeOnlyThatChatAndResetPutsItBack() {
        let app = XCUIApplication()
        openSamAppearance(app)
        let meadow = app.buttons["chat-wallpaper-meadow"]
        scrollTo(meadow, app)
        meadow.tap()
        XCTAssertTrue(meadow.isSelected)
        let pink = app.buttons["chat-bubble-0-deep"]
        scrollTo(pink, app)
        XCTAssertEqual(pink.label, "Pink, deep")
        pink.tap()
        XCTAssertTrue(pink.isSelected)
        app.buttons["chat-look-done"].tap()
        // Back to Sam's chat: it has the look. (The marker is in the chat behind the profile.)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(any(app, "chat-look-meadow-0-deep").waitForExistence(timeout: 8), "this chat has its own look")
        // Reset puts it back.
        any(app, "chat-title").tap()
        app.buttons["profile-more"].tap()
        app.buttons["profile-chat-appearance"].tap()
        let reset = app.buttons["chat-reset"]
        scrollTo(reset, app)
        reset.tap()
        app.buttons["chat-look-done"].tap()
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(any(app, "chat-look-default-follow").waitForExistence(timeout: 8), "reset: the global look again")
    }

    func testTheSetUpOfSamsChatDoesNotReachLeesChatAndUseForAllDoes() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-chatlook", "0", "deep", "meadow", "-lime-demo-screen", "chat"]
        app.launch()
        XCTAssertTrue(any(app, "chat-look-meadow-0-deep").waitForExistence(timeout: 10), "Sam's chat has the look it was given")
        let lee = XCUIApplication()
        lee.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-chatlook", "0", "deep", "meadow", "-lime-demo-screen", "profile-lee"]
        lee.launch()
        XCTAssertTrue(lee.buttons["profile-message"].waitForExistence(timeout: 10))
        lee.buttons["profile-message"].tap()
        XCTAssertTrue(any(lee, "chat-look-default-follow").waitForExistence(timeout: 8), "Lee's chat keeps the global look")
    }
}
