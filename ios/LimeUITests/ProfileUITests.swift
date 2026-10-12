import XCTest

/// The contact profile (LIME-122a), in the made-up chat with Sam.
@MainActor
final class ProfileUITests: XCTestCase {
    private func app(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat"] + extra
        app.launch()
        return app
    }

    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any)[id] }

    func testTappingTheTitleOfADirectChatOpensTheProfileWithHandleSchoolAboutAndStatus() {
        let app = app()
        app.buttons["conversation-row-dm:sam"].tap()
        XCTAssertTrue(any(app, "chat-title").waitForExistence(timeout: 8))
        any(app, "chat-title").tap()
        XCTAssertTrue(any(app, "profile-screen").waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["profile-name"].label, "Sam Park")
        XCTAssertEqual(app.staticTexts["profile-handle"].label, "@sam.park · Lincoln Elementary")
        XCTAssertTrue(app.staticTexts["profile-status"].exists, "the status they shared")
        XCTAssertTrue(app.buttons["profile-message"].exists && app.buttons["profile-voice"].exists && app.buttons["profile-video"].exists)
        XCTAssertTrue(app.staticTexts["profile-about"].label.contains("fractions"), "About")
        XCTAssertTrue(app.buttons["profile-username"].exists && app.buttons["profile-label"].exists, "the details card")
    }

    func testTheMoreMenusProfileItemOpensIt() {
        let app = app()
        app.buttons["conversation-row-dm:sam"].tap()
        XCTAssertTrue(app.buttons["chat-more"].waitForExistence(timeout: 8))
        app.buttons["chat-more"].tap()
        XCTAssertTrue(app.buttons["chat-profile"].waitForExistence(timeout: 5))
        app.buttons["chat-profile"].tap()
        XCTAssertTrue(any(app, "profile-screen").waitForExistence(timeout: 8))
    }

    func testTheSharedSectionListsWhatSamSharedAndCopyingTheUsernameToasts() {
        let app = app()
        app.buttons["conversation-row-dm:sam"].tap()
        any(app, "chat-title").tap()
        XCTAssertTrue(any(app, "profile-screen").waitForExistence(timeout: 8))
        app.segmentedControls.firstMatch.buttons["Shared"].tap()
        XCTAssertTrue(any(app, "profile-links").waitForExistence(timeout: 5), "the link Sam sent")
        XCTAssertTrue(any(app, "profile-files").exists, "and the file")
        app.segmentedControls.firstMatch.buttons["Info"].tap()
        app.buttons["profile-username"].tap()
        XCTAssertTrue(any(app, "profile-copied").waitForExistence(timeout: 3), "Copied")
    }

    func testCallDatesOnTheProfileAreOneLineEach() {
        let app = app(["-lime-demo-calls"])
        app.tabBars.buttons["call"].tap()
        app.buttons.matching(identifier: "call-history-row").element(boundBy: 1).tap()   // Sam
        XCTAssertTrue(any(app, "profile-screen").waitForExistence(timeout: 8))
        let lines = app.descendants(matching: .any).matching(identifier: "profile-call-line")
        XCTAssertTrue(lines.firstMatch.waitForExistence(timeout: 5))
        for line in lines.allElementsBoundByIndex { XCTAssertLessThan(line.frame.height, 60, "a call is one line: \(line.label)") }
    }
}
