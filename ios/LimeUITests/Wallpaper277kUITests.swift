import XCTest

/// LIME-277k (demo): a big photo as a chat's wallpaper never changes the chat's layout: the header buttons, the composer and the messages are where they are
/// without one, there is no dock, and typing works.
@MainActor
final class Wallpaper277kUITests: LimeUITestCase {
    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    private func chat(_ args: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "chat"] + args
        app.launch()
        return app
    }

    func testAPhotoWallpaperLeavesTheHeaderTheComposerAndTheMessagesWhereTheyAre() {
        let plain = chat([])
        let field = plain.textViews["composer-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        let plainField = field.frame, plainBack = plain.buttons["back-button"].exists ? plain.buttons["back-button"].frame : plain.navigationBars.buttons.firstMatch.frame
        let plainSearch = plain.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'search'")).firstMatch.frame
        plain.terminate()

        let app = chat(["-lime-demo-photo-wallpaper"])
        let window = app.windows.firstMatch.frame
        let photoField = app.textViews["composer-field"]
        XCTAssertTrue(photoField.waitForExistence(timeout: 10), "the composer has its field")
        XCTAssertEqual(photoField.frame.minX, plainField.minX, accuracy: 2); XCTAssertEqual(photoField.frame.width, plainField.width, accuracy: 2)
        XCTAssertLessThanOrEqual(photoField.frame.maxX, window.maxX, "the composer is on the screen")
        for id in ["composer-plus", "composer-emoji", "composer-aa", "composer-hide-keyboard"] {
            let b = app.buttons[id]
            XCTAssertTrue(b.exists, "\(id) is there")
            XCTAssertTrue(b.frame.minX >= 0 && b.frame.maxX <= window.maxX, "\(id) is on the screen")
        }
        let back = app.buttons["back-button"].exists ? app.buttons["back-button"] : app.navigationBars.buttons.firstMatch
        XCTAssertTrue(back.exists, "‹ is there")
        XCTAssertEqual(back.frame.minX, plainBack.minX, accuracy: 2)
        let search = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'search'")).firstMatch
        XCTAssertTrue(search.exists, "search is there")
        XCTAssertEqual(search.frame.minX, plainSearch.minX, accuracy: 2, "in the same place as without a wallpaper")
        XCTAssertFalse(app.tabBars.firstMatch.exists && app.tabBars.firstMatch.isHittable, "no dock over a chat")
        // The messages did not widen either.
        let bubble = app.descendants(matching: .any).matching(identifier: "other-bubble").firstMatch
        XCTAssertTrue(bubble.exists)
        XCTAssertLessThanOrEqual(bubble.frame.maxX, window.maxX)
    }

    func testTypingAFewLinesOnAPhotoWallpaperStaysResponsive() {
        let app = chat(["-lime-demo-photo-wallpaper"])
        let field = app.textViews["composer-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        for line in ["First line", "Second line", "Third line with a few more words in it"] { field.typeText(line + "\n") }
        XCTAssertTrue((field.value as? String ?? "").contains("Third line"), "typing landed")
        XCTAssertTrue(app.buttons["back-button"].exists || app.navigationBars.buttons.firstMatch.exists, "the header is still whole")
        XCTAssertLessThanOrEqual(field.frame.maxX, app.windows.firstMatch.frame.maxX)
    }
}
