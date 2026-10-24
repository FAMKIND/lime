import XCTest

/// LIME-189d: likes and comments, polished (demo).
@MainActor
final class Jam189dUITests: LimeUITestCase {
    private func launch(_ screen: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", screen]
        app.launch()
        return app
    }

    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    func testTheCommentIconOnACardOpensThePostAtItsCommentsWithTheKeyboardDown() {
        let app = launch("jam-following")
        let icon = app.buttons["jam-comment-demo-post-2"]
        XCTAssertTrue(icon.waitForExistence(timeout: 10)); icon.tap()
        let line = any(app, "jam-counts-line")
        XCTAssertTrue(line.waitForExistence(timeout: 8))
        XCTAssertTrue(line.isHittable, "the comments are on screen")
        XCTAssertFalse(app.keyboards.firstMatch.exists, "nothing is in focus")
    }

    func testTheCommentFieldIsNotUnderTheActionPillAtTheEndOfAnArticle() {
        let app = launch("jam-mine-asjam")
        app.showJamArticles()
        let card = app.buttons.matching(NSPredicate(format: "label CONTAINS 'How we read together'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10)); card.tap()
        let field = app.textViews["jam-comment-field"].exists ? app.textViews["jam-comment-field"] : app.textFields["jam-comment-field"]
        for _ in 0..<12 where !field.exists || !field.isHittable { app.swipeUp() }
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertTrue(field.isHittable)
        let pill = app.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] 'like'")).firstMatch
        if pill.exists { XCTAssertGreaterThan(field.frame.maxY, 0); XCTAssertFalse(field.frame.intersects(pill.frame) && pill.isHittable, "the pill is not over the field") }
        field.tap()
        XCTAssertFalse(pill.isHittable, "the pill steps aside while typing")
    }

    func testActivityOnMyProfileListsMyOwnLikeAndOnSomeoneElsesOnlyWhatIcanSee() {
        let app = launch("jam-following")
        let heart = app.buttons["jam-like-demo-post-2"]
        XCTAssertTrue(heart.waitForExistence(timeout: 10)); heart.tap()
        app.buttons["settings-button"].tap()
        XCTAssertTrue(app.buttons["profile-tab-Activity"].waitForExistence(timeout: 10))
        app.buttons["profile-tab-Activity"].tap()
        XCTAssertTrue(any(app, "jam-activity-l-demo-post-2").waitForExistence(timeout: 5), "my own like is listed")
        // Lee's profile: his comment on a post I can read.
        app.terminate(); 
        let app2 = launch("jam-following")
        app2.buttons["link"].tap()
        app2.buttons["conversation-row-dm:lee"].tap()
        any(app2, "chat-title").tap()
        XCTAssertTrue(app2.buttons["profile-tab-Activity"].waitForExistence(timeout: 10))
        app2.buttons["profile-tab-Activity"].tap()
        XCTAssertTrue(any(app2, "jam-activity-c-demo-comment-1").waitForExistence(timeout: 5), "Lee's comment on a post I can read")
    }
}
