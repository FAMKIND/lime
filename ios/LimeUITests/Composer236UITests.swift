import XCTest

/// LIME-236: the New post composer as the mockup (demo): two glass pills above the keyboard bar, the bar in order.
@MainActor
final class Composer236UITests: LimeUITestCase {
    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    func testThePillsSitAboveTheBarAndTheBarIsInOrderAndThePillsOpenTheArticleAndTheStudio() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "jam-mine"]
        app.launch()
        XCTAssertTrue(app.buttons["new-jam-post"].waitForExistence(timeout: 10))
        app.buttons["new-jam-post"].tap()
        let article = app.buttons["jam-write-article"], record = app.buttons["jam-record"]
        XCTAssertTrue(article.waitForExistence(timeout: 8) && record.exists)
        XCTAssertEqual(article.label, "Write an article"); XCTAssertEqual(record.label, "Record a podcast")
        // Both pills are above the keyboard bar.
        let photo = app.buttons["jam-add-photo"]
        XCTAssertLessThan(article.frame.maxY, photo.frame.minY + 2, "the pills sit above the bar")
        XCTAssertLessThan(record.frame.maxY, photo.frame.minY + 2)
        XCTAssertLessThan(article.frame.minX, record.frame.minX)
        // The bar: photo library · camera · Aa ⌄ · H ⌄ · undo · redo … hide keyboard.
        let ids = ["jam-add-photo", "jam-add-camera", "jam-format", "jam-heading", "jam-undo", "jam-redo", "jam-hide-keyboard"]
        let xs = ids.map { app.buttons[$0].frame.minX }
        XCTAssertEqual(xs, xs.sorted(), "in order: \(xs)")
        XCTAssertTrue(app.buttons["jam-hide-keyboard"].frame.minX > app.buttons["jam-redo"].frame.maxX, "hide keyboard is at the right end")
        // Post is disabled until there is something to post.
        XCTAssertFalse(app.buttons["jam-post"].isEnabled)
        // The pills open the studio and the article editor.
        record.tap()
        XCTAssertTrue(any(app, "podcast-record").waitForExistence(timeout: 8), "Record a podcast opens the studio")
    }

    func testWriteAnArticleOpensTheArticleEditor() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "jam-mine"]
        app.launch()
        app.buttons["new-jam-post"].tap()
        XCTAssertTrue(app.buttons["jam-write-article"].waitForExistence(timeout: 8))
        app.buttons["jam-write-article"].tap()
        XCTAssertTrue(app.textFields["jam-article-title"].waitForExistence(timeout: 8) || app.textViews["jam-article-title"].waitForExistence(timeout: 2))
    }
}
