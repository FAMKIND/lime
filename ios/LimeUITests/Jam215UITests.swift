import XCTest

/// LIME-215: profile cards match the feed; taps; the one-line detail; the cover's subtitle (demo).
@MainActor
final class Jam215UITests: LimeUITestCase {
    private func launch(_ screen: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", screen]
        app.launch()
        return app
    }

    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    func testTappingTheDetailLineOpensThePostAndTappingTheNameOpensTheProfile() {
        let app = launch("jam-following")
        let avatar = app.buttons["jam-card-avatar-demo-post-2"]
        XCTAssertTrue(avatar.waitForExistence(timeout: 10))
        // The empty space at the right of the row (not the avatar, not the name, not ⋯) opens the post.
        let window = app.windows.firstMatch
        window.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: window.frame.width * 0.72, dy: avatar.frame.midY)).tap()
        XCTAssertTrue(any(app, "jam-counts-line").waitForExistence(timeout: 8), "the rest of the row opens the post (its page has the counts)")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let name = app.buttons["jam-card-writer-demo-post-2"]
        XCTAssertTrue(name.waitForExistence(timeout: 8))
        // The detail line under the name opens the post too (a tap just below the name).
        window.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: name.frame.minX + 24, dy: name.frame.maxY + 9)).tap()
        XCTAssertTrue(any(app, "jam-counts-line").waitForExistence(timeout: 8), "the detail line opens the post")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(name.waitForExistence(timeout: 8)); name.tap()
        XCTAssertTrue(any(app, "profile-screen").waitForExistence(timeout: 8), "the name opens the profile")
    }

    func testAProfilesCardIsTheFeedsCardWithBothAuthorsAndTheCoverShowsItsSubtitle() {
        let app = launch("jam-following")
        let avatar = app.buttons["jam-card-avatar-demo-post-2"]
        XCTAssertTrue(avatar.waitForExistence(timeout: 10)); avatar.tap()
        XCTAssertTrue(any(app, "profile-screen").waitForExistence(timeout: 8))
        app.buttons["profile-tab-Articles"].tap()
        let byline = any(app, "jam-card-byline-demo-post-1")
        XCTAssertTrue(byline.waitForExistence(timeout: 8), "the writer row is on the profile's card")
        XCTAssertTrue(byline.label.contains("with Lee Wong"), byline.label)
        XCTAssertTrue(app.buttons["jam-card-avatar-demo-post-1"].exists, "the authors' picture")
        XCTAssertTrue(any(app, "jam-article-card-subtitle").exists, "the cover shows the subtitle")
    }

    func testAnOrgPostsNameOpensTheOrgsPage() {
        let app = launch("jam-mine-asjam")
        app.showJamArticles()
        let name = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'jam-card-writer-' AND label BEGINSWITH 'Reading circles, by'")).firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 10)); name.tap()
        XCTAssertTrue(app.staticTexts["profile-jam-row"].waitForExistence(timeout: 8), "the org's page")
    }
}
