import XCTest

/// LIME-188s: Note to Self makes link cards too.
@MainActor
final class Jam188sUITests: LimeUITestCase {
    func testALinkInNoteToSelfShowsACardBeforeSendingAndInTheBubble() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "note-to-self"]
        app.launch()
        let field = app.textViews["composer-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("https://example.com")
        XCTAssertTrue(app.descendants(matching: .any)["preview-draft"].waitForExistence(timeout: 8), "the card shows above the field")
        app.buttons["send-button"].tap()
        let card = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'link-card-' AND identifier != 'link-card-title' AND identifier != 'link-card-site'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 8), "the bubble keeps the card")
    }
}
