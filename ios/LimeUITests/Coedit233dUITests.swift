import XCTest

/// LIME-233d: writing together (demo): a second author's face, cursor and words, while this author's caret stays.
@MainActor
final class Coedit233dUITests: LimeUITestCase {
    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    func testAnotherAuthorShowsAsAFaceACursorAndTypedWordsWhileMyCaretStays() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "jam-mine", "-lime-coedit-sim-remote", "-lime-coedit-sim-peer"]
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
        // The top bar has the authors' avatars (me and Jean) before Post, and no "Article" title.
        let authors = any(app, "coedit-authors")
        XCTAssertTrue(authors.waitForExistence(timeout: 10), "the authors are in the top bar")
        XCTAssertTrue(authors.label.contains("Jean Park"), authors.label)
        XCTAssertTrue(app.buttons["jam-post"].exists)
        XCTAssertFalse(app.staticTexts["Article"].exists, "no nav title")
        XCTAssertFalse(any(app, "coedit-editing").exists, "no \"is editing\" line: the cursor says it")
        XCTAssertLessThan(authors.frame.minX, app.buttons["jam-post"].frame.minX, "the avatars sit left of Post")
        // Her cursor is in the page, with her name.
        XCTAssertTrue(any(app, "coedit-cursor-sim-jean").waitForExistence(timeout: 6), "her cursor shows")
        XCTAssertEqual(any(app, "coedit-cursor-sim-jean").label, "Jean\u{2019}s cursor")
        // Her words arrive; this author's caret does not jump.
        let probe = any(app, "coedit-probe")
        expectation(for: NSPredicate(format: "label == 'REMOTE Hello world'"), evaluatedWith: probe)
        waitForExpectations(timeout: 15)
        body.typeText("!")
        sleep(2)
        XCTAssertEqual((body.value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), "REMOTE Hello world!", "my typing landed at my caret")
    }
}
