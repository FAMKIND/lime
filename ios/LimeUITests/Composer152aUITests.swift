import XCTest

/// LIME-152a: the composer's tool row is never under the keyboard, and Note to Self's header opens your own profile.
@MainActor
final class Composer152aUITests: LimeUITestCase {
    private func assertToolRowAboveKeyboard(_ app: XCUIApplication, _ message: String) {
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5), "the keyboard is up")
        for id in ["composer-plus", "composer-emoji", "composer-aa"] {
            let button = app.buttons[id]
            XCTAssertTrue(button.waitForExistence(timeout: 5), "\(id) exists: \(message)")
            XCTAssertTrue(button.isHittable, "\(id) is hittable: \(message)")
            XCTAssertLessThanOrEqual(button.frame.maxY, keyboard.frame.minY + 1, "\(id) is above the keyboard: \(message)")
        }
    }

    func testTheComposerStaysAboveTheKeyboardAfterDeletingASelectionInALongDraft() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat"]
        app.launch()
        let field = openComposer(app)
        field.typeText("one\ntwo\nthree\nfour\nfive\nsix")
        assertToolRowAboveKeyboard(app, "a six line draft")
        selectAll(field, in: app)
        field.typeText(XCUIKeyboardKey.delete.rawValue)
        XCTAssertEqual(field.value as? String ?? "", "")
        sleep(1)
        assertToolRowAboveKeyboard(app, "after select all and delete")
        // A partial selection, deleted, in a long draft.
        field.typeText("alpha\nbeta\ngamma\ndelta\nepsilon")
        field.typeText(XCUIKeyboardKey.delete.rawValue)
        field.typeText(XCUIKeyboardKey.delete.rawValue)
        sleep(1)
        assertToolRowAboveKeyboard(app, "after deleting a few characters")
    }

    func testTheComposerStaysAboveTheKeyboardWithTheFormattingRowOpenAfterADelete() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat"]
        app.launch()
        let field = openComposer(app)
        field.typeText("one\ntwo\nthree\nfour")
        selectAll(field, in: app)
        XCTAssertTrue(app.buttons["fmt-bold"].waitForExistence(timeout: 5), "the formatting row is open")
        field.typeText(XCUIKeyboardKey.delete.rawValue)
        sleep(1)
        let keyboard = app.keyboards.firstMatch
        for id in ["composer-plus", "composer-emoji", "composer-aa"] {
            XCTAssertLessThanOrEqual(app.buttons[id].frame.maxY, keyboard.frame.minY + 1, "\(id) is above the keyboard")
        }
    }

    func testNoteToSelfsHeaderOpensYourOwnProfile() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "note-to-self"]
        app.launch()
        let title = app.descendants(matching: .any).matching(identifier: "chat-title").firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        title.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "profile-screen").firstMatch.waitForExistence(timeout: 5), "your profile opens")
        XCTAssertTrue(app.buttons["profile-sign-out"].waitForExistence(timeout: 5) || app.staticTexts["Shem Rajoon"].exists, "and it is yours")
    }
}
