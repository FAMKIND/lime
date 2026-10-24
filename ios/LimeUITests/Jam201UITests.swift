import XCTest

/// LIME-201: changing "Post as" in Edit sticks, and the chip starts on the post's current author.
@MainActor
final class Jam201UITests: LimeUITestCase {
    func testEditingTheAuthorToTheJamShowsTheJamOnThePageAndTheChipStartsThere() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "jam-mine"]
        app.launch()
        app.showJamArticles()
        let card = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Our first circle'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10)); card.tap()
        func edit() {
            app.buttons["jam-article-more"].tap()
            XCTAssertTrue(app.buttons["options-edit"].waitForExistence(timeout: 5))
            app.buttons["options-edit"].tap()
        }
        edit()
        let chip = app.buttons["jam-post-as"]
        XCTAssertTrue(chip.waitForExistence(timeout: 8))
        XCTAssertFalse(chip.label.contains("Reading circles"), "starts on you: \(chip.label)")
        chip.tap()
        let jam = app.buttons["jam-post-as-jam-demo-my-jam"]
        XCTAssertTrue(jam.waitForExistence(timeout: 5)); jam.tap()
        app.buttons["jam-update"].tap()
        let byline = app.staticTexts["jam-reader-byline"]
        XCTAssertTrue(byline.waitForExistence(timeout: 8))
        XCTAssertTrue(byline.label.hasPrefix("by "), "the page names the jam first, then \"by <writer>\": \(byline.label)")
        edit()
        XCTAssertTrue(app.buttons["jam-post-as"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["jam-post-as"].label.contains("Reading circles"), "the chip starts on the current author: \(app.buttons["jam-post-as"].label)")
    }
}
