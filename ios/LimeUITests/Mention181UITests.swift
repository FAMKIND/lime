import XCTest

/// LIME-181: @mentions: pick from the chat's people, highlighted in the bubble, tap for the profile.
@MainActor
final class Mention181UITests: LimeUITestCase {
    private func open(_ row: String, screen: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat"] + (screen.map { ["-lime-demo-screen", $0] } ?? [])
        app.launch()
        if screen == "group" { return app }   // opens the group itself
        app.buttons[row].tap()
        return app
    }

    private func field(_ app: XCUIApplication) -> XCUIElement {
        let field = app.textViews["composer-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        return field
    }

    private func suggestion(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.buttons["mention-suggestion-\(id)"] }

    func testInAOneToOneChatAtOffersJustTheOtherPerson() {
        let app = open("conversation-row-dm:sam")
        field(app).typeText("@")
        XCTAssertTrue(suggestion(app, "sam").waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'mention-suggestion-'")).count, 1)
        XCTAssertFalse(suggestion(app, "everyone").exists, "never in a one-to-one chat")
    }

    func testPickingAPersonPutsTheirNameInTheFieldAndTheBubbleHasATappableMention() {
        let app = open("", screen: "group")
        let field = field(app)
        field.typeText("hi @le")
        XCTAssertTrue(suggestion(app, "lee").waitForExistence(timeout: 5))
        XCTAssertFalse(suggestion(app, "sam").exists, "narrowed by what was typed")
        suggestion(app, "lee").tap()
        XCTAssertFalse(suggestion(app, "lee").exists, "the list closes")
        XCTAssertEqual(field.value as? String, "hi [@Lee Wong](mention:lee) ", "the field holds the mention (its value is the message as it will be sent)")
        field.typeText("look")
        app.buttons["send-button"].tap()
        let mention = app.links["@Lee Wong"]
        XCTAssertTrue(mention.waitForExistence(timeout: 8), "the bubble has a mention element")
        mention.tap()
        XCTAssertTrue(app.descendants(matching: .any)["profile-screen"].waitForExistence(timeout: 8), "tapping it opens their profile")
    }

    func testBackspaceRemovesAWholeMention() {
        let app = open("", screen: "group")
        let field = field(app)
        field.typeText("@sa")
        suggestion(app, "sam").tap()
        field.typeText(XCUIKeyboardKey.delete.rawValue)   // the space
        XCTAssertEqual((field.value as? String)?.hasPrefix("[@Sam"), true, "the space went, the mention stays")
        field.typeText(XCUIKeyboardKey.delete.rawValue)   // the mention, all of it
        XCTAssertEqual(field.value as? String, "", "no half a name is left")
    }

    func testOnlyAnAdminIsOfferedEveryone() {
        let owner = open("", screen: "group")
        field(owner).typeText("@")
        XCTAssertTrue(suggestion(owner, "everyone").waitForExistence(timeout: 5), "I own this group")
        owner.terminate()

        let member = open("conversation-row-grp:demo2", screen: "groups-rows")
        field(member).typeText("@")
        XCTAssertTrue(suggestion(member, "lee").waitForExistence(timeout: 5))
        XCTAssertFalse(suggestion(member, "everyone").exists, "a plain member does not get it")
    }
}
