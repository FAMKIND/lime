import XCTest

/// LIME-188d: a calmer profile: a header as before, then one row of sections, each showing one thing; Info first.
@MainActor
final class Jam188dUITests: LimeUITestCase {
    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    private func openSamsProfile(_ app: XCUIApplication) {
        app.buttons["conversation-row-dm:sam"].tap()
        any(app, "chat-title").tap()
        XCTAssertTrue(any(app, "profile-screen").waitForExistence(timeout: 10))
    }

    func testTheSectionsRowHasTheTabsInOrderInfoFirstAndOneSectionAtATime() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat"]
        app.launch()
        openSamsProfile(app)
        let order = ["Info", "Activity", "Posts", "Comments", "Replies"]
        var last: CGFloat = -1
        for name in order {
            let tab = app.buttons["profile-tab-\(name)"]
            XCTAssertTrue(tab.waitForExistence(timeout: 8), name)
            XCTAssertGreaterThan(tab.frame.minX, last, "\(name) comes after the one before it")
            last = tab.frame.minX
        }
        XCTAssertTrue(app.buttons["profile-tab-Info"].isSelected, "Info is the default")
        XCTAssertTrue(any(app, "profile-about").exists || any(app, "profile-handle").exists || any(app, "profile-name").exists)
        XCTAssertFalse(app.staticTexts["profile-jam-row"].exists, "no jam parts in the header or Info")
        app.buttons["profile-tab-Activity"].tap()
        XCTAssertTrue(any(app, "profile-empty-activity").waitForExistence(timeout: 5), "calm and empty until 189")
        app.buttons["profile-tab-Comments"].tap()
        XCTAssertTrue(any(app, "profile-empty-comments").waitForExistence(timeout: 5))
        XCTAssertFalse(any(app, "profile-empty-activity").exists, "one section at a time")
        app.buttons["profile-tab-Replies"].tap()
        XCTAssertTrue(any(app, "profile-empty-replies").waitForExistence(timeout: 5))
        app.buttons["profile-tab-Posts"].tap()
        XCTAssertTrue(app.staticTexts["profile-jam-row"].waitForExistence(timeout: 5), "the jam's title, subscribers and posts live in Posts")
    }

    func testPostsCanBeNarrowedByKind() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "jam-mine-profile"]
        app.launch()
        XCTAssertTrue(app.buttons["profile-tab-Posts"].waitForExistence(timeout: 10))
        app.buttons["profile-tab-Posts"].tap()
        XCTAssertTrue(app.buttons["profile-posts-kind-All"].waitForExistence(timeout: 5))
        for name in ["Articles", "Audio", "Video", "Quick"] { XCTAssertTrue(app.buttons["profile-posts-kind-\(name)"].exists, name) }
        app.buttons["profile-posts-kind-Video"].tap()
        XCTAssertTrue(app.buttons["profile-posts-kind-Video"].isSelected)
        XCTAssertTrue(app.staticTexts["Your posts show here."].waitForExistence(timeout: 5), "nothing of that kind")
        app.buttons["profile-posts-kind-All"].tap()
        XCTAssertFalse(app.staticTexts["Your posts show here."].exists)
    }
}
