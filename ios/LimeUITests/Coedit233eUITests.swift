import XCTest

/// LIME-233e: a co-author does not publish: no Post button, "Shem publishes this article", Ready, and the published banner (demo, simulated writer).
@MainActor
final class Coedit233eUITests: LimeUITestCase {
    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    func testACoAuthorHasNoPublishButtonSaysReadyAndSeesTheWriterPublish() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "jam-mine", "-lime-coedit-sim-coauthor", "-lime-coedit-sim-published"]
        app.launch()
        XCTAssertTrue(app.buttons["new-jam-post"].waitForExistence(timeout: 10))
        app.buttons["new-jam-post"].tap()
        XCTAssertTrue(app.buttons["jam-write-article"].waitForExistence(timeout: 8))
        app.buttons["jam-write-article"].tap()
        let title = app.textFields["jam-article-title"].exists ? app.textFields["jam-article-title"] : app.textViews["jam-article-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 8))
        title.tap(); title.typeText("Fractions plan\n\n")
        let body = app.textViews["composer-field"]
        expectation(for: NSPredicate(format: "hasKeyboardFocus == true"), evaluatedWith: body)
        waitForExpectations(timeout: 5)
        body.typeText("Hello world")
        // The writer is someone else: this author sees who publishes, with a Ready button, and no Post.
        let publishes = any(app, "coedit-publishes")
        XCTAssertTrue(publishes.waitForExistence(timeout: 8), "says who publishes")
        XCTAssertTrue(publishes.label.hasSuffix("publishes this article"), publishes.label)
        XCTAssertFalse(app.buttons["jam-post"].exists, "a co-author has no Post button")
        XCTAssertFalse(app.buttons["jam-update"].exists)
        let ready = app.buttons["coedit-ready"]
        XCTAssertTrue(ready.exists)
        ready.tap()
        XCTAssertTrue(ready.label.hasPrefix("Ready, tell ") && ready.label.hasSuffix(" you are not"), "the button answers at once: \(ready.label)")
        // The writer publishes: the banner says so, and the Ready button goes.
        let published = any(app, "coedit-published")
        XCTAssertTrue(published.waitForExistence(timeout: 20), "the published banner")
        XCTAssertTrue(published.label.hasPrefix("Published by"), published.label)
        XCTAssertFalse(app.buttons["coedit-ready"].exists)
        // Later changes are marked.
        XCTAssertTrue(any(app, "coedit-changes").waitForExistence(timeout: 20))
        XCTAssertEqual(any(app, "coedit-changes").label, "Changes since the last publish")
    }
}
