import XCTest

/// LIME-233g: smoother co-editing (demo): a remote insertion in the middle of a word lands in place and the caret stays; a remote caret shows in the title;
/// Drafts lists a shared draft; the invitation banner opens it.
@MainActor
final class Coedit233gUITests: LimeUITestCase {
    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    private func openArticle(_ app: XCUIApplication) -> XCUIElement {
        XCTAssertTrue(app.buttons["new-jam-post"].waitForExistence(timeout: 10))
        app.buttons["new-jam-post"].tap()
        XCTAssertTrue(app.buttons["jam-write-article"].waitForExistence(timeout: 8))
        app.buttons["jam-write-article"].tap()
        let title = app.textFields["jam-article-title"].exists ? app.textFields["jam-article-title"] : app.textViews["jam-article-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 8))
        return title
    }

    func testARemoteInsertionInTheMiddleOfAWordLandsInPlaceAndMyCaretStaysAndHerCaretShowsInTheTitle() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "jam-mine", "-lime-coedit-sim-remote", "-lime-coedit-sim-remote-mid", "-lime-coedit-sim-peer", "-lime-coedit-sim-peer-title"]
        app.launch()
        let title = openArticle(app)
        title.tap(); title.typeText("Fractions plan\n\n")
        let body = app.textViews["composer-field"]
        expectation(for: NSPredicate(format: "hasKeyboardFocus == true"), evaluatedWith: body)
        waitForExpectations(timeout: 5)
        body.typeText("Hello world")
        // Her caret is in the title, with her tag.
        let cursor = any(app, "coedit-cursor-sim-jean")
        if !cursor.waitForExistence(timeout: 10) {
            let dump = app.debugDescription.split(separator: "\n").filter { $0.contains("cursor") || $0.contains("jam-article-title") || $0.contains("coedit") }.joined(separator: "\n")
            XCTFail("her caret shows in the title; found: \(dump)")
        }
        // Her letters arrive inside "Hello": "Hel-X-lo world". My caret stays at the end of my text.
        let probe = any(app, "coedit-probe")
        expectation(for: NSPredicate(format: "label == 'Hel-X-lo world'"), evaluatedWith: probe)
        waitForExpectations(timeout: 15)
        body.typeText("!")
        sleep(1)
        XCTAssertEqual((body.value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), "Hel-X-lo world!", "my letter went after the same character as before")
        XCTAssertEqual(body.value(forKey: "hasKeyboardFocus") as? Bool, true)
    }

    func testTheInvitationBannerOpensTheDraftAndDraftsListsIt() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "jam-mine", "-lime-coedit-sim-invite"]
        app.launch()
        let banner = app.buttons["draft-invite-banner"]
        XCTAssertTrue(banner.waitForExistence(timeout: 10), "the glass banner")
        XCTAssertTrue(banner.label.contains("invited you to write"), banner.label)
        // A tap on the banner opens the editor on the draft.
        banner.tap()
        let body = app.textViews["composer-field"]
        XCTAssertTrue(body.waitForExistence(timeout: 10), "the editor opened")
        expectation(for: NSPredicate(format: "value CONTAINS 'Hello from Jean.'"), evaluatedWith: body)
        waitForExpectations(timeout: 8)
        app.buttons["jam-compose-cancel"].tap()
        // Drafts is in jam's toggle after Podcasts and lists the draft; a tap on it opens the editor too.
        let drafts = app.buttons["jam-segment-Drafts"]
        XCTAssertTrue(drafts.waitForExistence(timeout: 8))
        drafts.tap()
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'jam-draft-'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "Drafts lists the shared draft")
        row.tap()
        XCTAssertTrue(app.textViews["composer-field"].waitForExistence(timeout: 10), "a row opens the draft")
    }
}
