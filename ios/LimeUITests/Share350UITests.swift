import XCTest

/// LIME-350: every jam card's row reads ♥ · 💬 · Share; Share sends the post into a chat; a members-only post has no Share (its words must never reach a chat
/// that may include non-members). Uses the website's debug demo (`site-jam`): a free quick post and a members-only post.
@MainActor
final class Share350UITests: LimeUITestCase {
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "site-jam"]
        app.launch()
        return app
    }

    private func scrollTo(_ app: XCUIApplication, _ element: XCUIElement) {
        for _ in 0..<10 { if element.exists && element.isHittable { return }; app.swipeUp(); sleep(1) }
    }

    func testAFreePostHasThreeActionsAndShareOpensTheChatPicker() {
        let app = launch()
        let share = app.buttons["jam-card-share-site-lindgren-1"]
        scrollTo(app, share)
        XCTAssertTrue(share.waitForExistence(timeout: 10), "Share is the third action of a free post")
        XCTAssertEqual(share.label, "Share", "VoiceOver says Share")
        XCTAssertGreaterThanOrEqual(share.frame.height, 44, "a 44 pt target")
        XCTAssertTrue(app.buttons["jam-like-site-lindgren-1"].exists && app.buttons["jam-comment-site-lindgren-1"].exists, "♥ and 💬 are still there")
        // Three equal columns: the three buttons are about the same width.
        let widths = ["jam-like-site-lindgren-1", "jam-comment-site-lindgren-1", "jam-card-share-site-lindgren-1"].map { app.buttons[$0].frame.width }
        XCTAssertLessThan((widths.max() ?? 0) - (widths.min() ?? 0), 2, "equal columns: \(widths)")
        share.tap()
        XCTAssertTrue(app.navigationBars["Share in lime"].waitForExistence(timeout: 6), "the post goes to a chat of lime's own: there is no link to a post")
        XCTAssertFalse(app.staticTexts["jam-share-members-only"].exists)
        app.buttons["Cancel"].tap()
    }

    func testAMembersOnlyPostHasNoShare() {
        let app = launch()
        let post = app.descendants(matching: .any).matching(identifier: "jam-post-site-sci-2").firstMatch
        scrollTo(app, post)
        XCTAssertTrue(post.waitForExistence(timeout: 10), "the members-only post is in the feed")
        XCTAssertTrue(app.buttons["jam-like-site-sci-2"].exists, "its heart is there")
        XCTAssertFalse(app.buttons["jam-card-share-site-sci-2"].exists, "no Share on a members-only post")
    }
}
