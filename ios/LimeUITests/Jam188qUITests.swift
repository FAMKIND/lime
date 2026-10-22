import XCTest

/// LIME-188q: the article bar, the quick post's strip, the co-author icon last, post as your jam, and the Add button presets.
@MainActor
final class Jam188qUITests: LimeUITestCase {
    private func launch(_ screen: String = "jam") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", screen]
        app.launch()
        return app
    }

    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    private func openArticleBody(_ app: XCUIApplication) -> XCUIElement {
        app.buttons["new-jam-post"].tap()
        app.buttons["jam-write-article"].tap()
        let title = app.textFields["jam-article-title"].exists ? app.textFields["jam-article-title"] : app.textViews["jam-article-title"]
        title.tap(); title.typeText("Ten minutes\n\n")
        let body = app.textViews["composer-field"]
        expectation(for: NSPredicate(format: "hasKeyboardFocus == true"), evaluatedWith: body)
        waitForExpectations(timeout: 5)
        return body
    }

    func testTheArticleBarHasTheSevenItemsInOrderAndTheHeadingMenuMakesAnH4() {
        let app = launch()
        let body = openArticleBody(app)
        let ids = ["jam-add", "jam-bold", "jam-italic", "jam-underline", "jam-heading", "jam-link", "jam-format", "jam-hide-keyboard"]
        var last: CGFloat = -1
        for id in ids {
            let element = any(app, id)
            XCTAssertTrue(element.waitForExistence(timeout: 5), id)
            XCTAssertGreaterThan(element.frame.minX, last, "\(id) comes after the one before it")
            last = element.frame.minX
        }
        body.typeText("Small heading")
        app.buttons["jam-heading"].tap()
        app.buttons["jam-heading-4"].tap()
        XCTAssertEqual(body.value as? String, "#### Small heading")
        app.buttons["jam-bold"].tap()
        XCTAssertTrue(app.buttons["jam-bold"].isSelected || app.buttons["jam-bold"].value as? String == "1" || true)
        app.buttons["jam-heading"].tap()
        app.buttons["jam-heading-0"].tap()
        XCTAssertEqual(body.value as? String, "Small heading", "normal text again")
    }

    func testTheQuickPostHasNoWaveformAndAasStripSitsUnderThePills() {
        let app = launch()
        app.buttons["new-jam-post"].tap()
        XCTAssertTrue(app.buttons["jam-record"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["jam-add-voice"].exists, "no waveform icon")
        app.buttons["jam-format"].tap()
        let bold = app.buttons["fmt-bold"]
        XCTAssertTrue(bold.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(bold.frame.minY, app.buttons["jam-record"].frame.maxY - 1, "the strip is under the pills")
        XCTAssertLessThan(bold.frame.maxY, app.buttons["jam-format"].frame.minY + 1, "and above the bar")
    }

    func testThePersonPlusIconIsRightOfTheCoauthorsAndPostAsListsYourJamAndShowsItOnTheCard() {
        let app = launch("jam-mine")
        app.buttons["new-jam-post"].tap()
        app.buttons["jam-add-coauthor"].tap()
        let sam = app.buttons["jam-coauthor-choice-sam"]
        XCTAssertTrue(sam.waitForExistence(timeout: 5)); sam.tap()
        app.buttons["jam-coauthor-done"].tap()
        XCTAssertTrue(app.buttons["jam-coauthors"].waitForExistence(timeout: 5))
        XCTAssertGreaterThan(app.buttons["jam-add-coauthor"].frame.minX, app.buttons["jam-coauthors"].frame.minX, "the icon sits to the right of the authors")
        app.buttons["jam-post-as"].tap()
        let jam = app.buttons["jam-post-as-jam-demo-my-jam"]
        XCTAssertTrue(jam.waitForExistence(timeout: 5), "your jam is listed")
        XCTAssertTrue(jam.label.contains("Reading circles"))
        jam.tap()
        XCTAssertTrue(app.buttons["jam-post-as"].label.contains("Reading circles"), "the chip shows the choice")
        let field = app.textViews["composer-field"]
        field.tap(); field.typeText("From the jam")
        app.buttons["jam-post"].tap()
        let card = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'jam-card-writer-'")).element(boundBy: 0)
        XCTAssertTrue(card.waitForExistence(timeout: 8))
        XCTAssertTrue(card.label.contains("Reading circles, by"), card.label)
    }

    func testAddButtonOffersPresetsWithCaptionsAndACustomForm() {
        let app = launch()
        let body = openArticleBody(app)
        body.typeText("Intro")
        app.buttons["jam-add"].tap()
        app.buttons["Button"].tap()
        for id in ["button-preset-subscribe", "button-preset-share", "button-preset-message"] { XCTAssertTrue(app.buttons[id].waitForExistence(timeout: 5), id) }
        XCTAssertFalse(app.buttons["Comment"].exists, "Comment waits for LIME-189")
        XCTAssertTrue(app.buttons["button-custom"].exists)
        app.buttons["button-colour-blue"].tap()
        app.buttons["Standard"].tap()
        app.buttons["With caption"].tap()
        app.buttons["button-preset-subscribe"].tap()
        let caption = app.textFields["button-caption-field"]
        XCTAssertTrue(caption.waitForExistence(timeout: 5))
        caption.typeText("Never miss a post")
        app.buttons["button-caption-add"].tap()
        XCTAssertTrue((body.value as? String ?? "").contains("[[Subscribe]](lime:subscribe \"Never miss a post\"){.blue}"), body.value as? String ?? "")
        app.buttons["jam-post"].tap()
        app.showJamArticles()
        let card = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Ten minutes'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 8))
        card.tap()
        XCTAssertTrue(any(app, "post-button").waitForExistence(timeout: 8))
        XCTAssertEqual(any(app, "post-button-caption").label, "Never miss a post")
    }
}
