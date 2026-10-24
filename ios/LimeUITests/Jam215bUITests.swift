import XCTest

/// LIME-215b: taller article cards; the org's writers on the Post as sheet and chip.
@MainActor
final class Jam215bUITests: LimeUITestCase {
    private func launch(_ screen: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", screen]
        app.launch()
        return app
    }

    func testAnArticleCardIsTwoThirdsOfAPortraitPhotoTall() {
        let app = launch("jam-following")
        let card = app.buttons["jam-post-demo-post-1"]
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        XCTAssertEqual(card.frame.height / card.frame.width, 0.83, accuracy: 0.08, "cover only is 0.83 x width; the card adds its text, so only check it is not 16:9")
        XCTAssertGreaterThan(card.frame.height, card.frame.width * 0.83 - 4)
    }

    func testPostAsShowsYouInTheOrgsAuthorsAndTheChipCarriesTheTile() {
        let app = launch("jam-mine")
        app.buttons["new-jam-post"].tap()
        app.buttons["jam-post-as"].tap()
        let jam = app.buttons["jam-post-as-jam-demo-my-jam"]
        XCTAssertTrue(jam.waitForExistence(timeout: 5))
        XCTAssertTrue(jam.label.contains("with you"), jam.label)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'You'")).firstMatch.exists, "You · … under the name")
        jam.tap()
        XCTAssertTrue(app.buttons["jam-post-as"].label.contains("Reading circles"))
    }
}
