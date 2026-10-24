import XCTest

/// LIME-220: the podcast edit page looks like the article editor: small cover (tap for full size), big title, subtitle, "Description…", no raw markup.
@MainActor
final class Jam220UITests: LimeUITestCase {
    func testThePodcastPageLooksLikeTheArticleEditor() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "jam-mine-podcast"]
        app.launch()
        app.descendants(matching: .any).matching(identifier: "jam-filter-segments").firstMatch.buttons["Podcasts"].tap()
        let more = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'card-more-'")).firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 10)); more.tap()
        app.buttons["Edit"].tap()
        let any = { (id: String) in app.descendants(matching: .any).matching(identifier: id).firstMatch }
        XCTAssertTrue(any("podcast-edit-title").waitForExistence(timeout: 8))
        let cover = app.buttons["podcast-edit-cover"]
        XCTAssertEqual(cover.frame.height, 107, accuracy: 3, "the cover is two thirds of 160")
        XCTAssertLessThan(cover.frame.maxY, any("podcast-edit-title").frame.minY, "cover above the title")
        XCTAssertLessThan(any("podcast-edit-title").frame.minY, any("podcast-edit-subtitle").frame.minY)
        XCTAssertTrue(app.staticTexts["Description\u{2026}"].exists || any("podcast-edit-description").exists, "the description field")
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'attachment:'")).firstMatch.exists, "no raw markup")
        XCTAssertFalse(app.textViews.matching(NSPredicate(format: "value CONTAINS 'attachment:'")).firstMatch.exists, "no raw markup in the field")
        cover.tap()
        XCTAssertTrue(any("podcast-edit-cover-viewer").waitForExistence(timeout: 5), "the cover opens large")
    }
}
