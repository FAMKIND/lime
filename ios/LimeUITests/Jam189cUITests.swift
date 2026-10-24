import XCTest

/// LIME-189c: hearts, comments and the post page (demo).
@MainActor
final class Jam189cUITests: LimeUITestCase {
    private func launch(_ screen: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", screen]
        app.launch()
        return app
    }

    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    func testTheHeartTogglesAndTheCountChanges() {
        let app = launch("jam-following")
        let heart = app.buttons["jam-like-demo-post-2"]
        XCTAssertTrue(heart.waitForExistence(timeout: 10))
        XCTAssertEqual(heart.label, "Like, 2", "two people liked it")
        XCTAssertFalse(heart.isSelected)
        heart.tap()
        XCTAssertEqual(heart.label, "Like, 3")
        XCTAssertTrue(heart.isSelected)
        heart.tap()
        XCTAssertEqual(heart.label, "Like, 2")
    }

    func testThePostPageShowsTheCountsAContactsFaceAndAPendingCommentThenAReplyUnderIt() {
        let app = launch("jam-following")
        let card = app.buttons["jam-post-demo-post-2"]
        XCTAssertTrue(card.waitForExistence(timeout: 10)); card.tap()
        let line = any(app, "jam-counts-line")
        for _ in 0..<4 where !line.exists { app.swipeUp() }
        XCTAssertTrue(line.waitForExistence(timeout: 8))
        XCTAssertEqual(line.label, "2 likes \u{00B7} 1 comment \u{00B7} 0 remixes")
        XCTAssertTrue(any(app, "jam-likers").label.hasPrefix("Liked by "), "a contact's face and name")
        XCTAssertTrue(any(app, "jam-comment-row-demo-comment-1").exists, "Lee's comment")
        // A comment of mine waits for the writer's phone.
        let field = app.textViews["jam-comment-field"].exists ? app.textViews["jam-comment-field"] : app.textFields["jam-comment-field"]
        field.tap(); field.typeText("Thanks for sharing")
        let send = app.buttons["jam-comment-send"]
        XCTAssertTrue(send.waitForExistence(timeout: 5))
        for _ in 0..<3 where !send.isHittable { app.swipeUp() }
        XCTAssertTrue(send.isHittable, "send \(send.frame) keyboard \(app.keyboards.firstMatch.frame) field \(field.frame) \(field.value as? String ?? "")")
        send.tap()
        XCTAssertTrue(any(app, "jam-comment-pending").waitForExistence(timeout: 5), "pending: \"Waiting for … phone\"")
        // A reply goes under its parent.
        app.buttons["jam-reply-demo-comment-1"].tap()
        let field2 = app.textViews["jam-comment-field"].exists ? app.textViews["jam-comment-field"] : app.textFields["jam-comment-field"]
        field2.typeText("Same here")
        app.buttons["jam-comment-send"].tap()
        let rows = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'jam-comment-row-'"))
        expectation(for: NSPredicate(format: "count == 3"), evaluatedWith: rows)
        waitForExpectations(timeout: 5)
        let parent = any(app, "jam-comment-row-demo-comment-1"), reply = rows.element(boundBy: 1)
        XCTAssertGreaterThan(reply.frame.minX, parent.frame.minX + 10, "the reply is indented under its parent")
    }

    func testTheWriterSeesTheDotAndCanRemoveACommentAndActivityHasADot() {
        let app = launch("jam-mine")
        app.showJamArticles()
        let dot = any(app, "jam-unseen-" + (app.buttons.matching(NSPredicate(format: "label CONTAINS 'Our first circle'")).firstMatch.identifier.replacingOccurrences(of: "jam-post-", with: "")))
        XCTAssertTrue(dot.waitForExistence(timeout: 10), "a dot on the post with new comments")
        let card = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Our first circle'")).firstMatch
        card.tap()
        let more = any(app, "jam-comment-more-demo-comment-2")
        for _ in 0..<6 where !more.exists { app.swipeUp() }
        XCTAssertTrue(more.waitForExistence(timeout: 8))
        more.tap()
        XCTAssertTrue(app.buttons["Remove"].waitForExistence(timeout: 5), "the writer removes any comment on their post")
        app.buttons["Remove"].tap()
        XCTAssertTrue(any(app, "jam-comment-row-demo-comment-2").waitForNonExistence(timeout: 5))
    }
}
