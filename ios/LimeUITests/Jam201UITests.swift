import XCTest

/// LIME-201: the chip starts on the post's current author; editing a post offers only the jam it is in (LIME-259).
@MainActor
final class Jam201UITests: LimeUITestCase {
    func testEditingAPostInMyOwnSpaceOffersOnlyMeAndTheChipStartsOnMe() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "jam-mine"]
        app.launch()
        app.showJamArticles()
        let card = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Our first circle'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10)); card.tap()
        func edit() {
            app.buttons["jam-article-more"].tap()
            XCTAssertTrue(app.buttons["options-edit"].waitForExistence(timeout: 5))
            app.buttons["options-edit"].tap()
        }
        edit()
        let chip = app.buttons["jam-post-as"]
        XCTAssertTrue(chip.waitForExistence(timeout: 8))
        XCTAssertFalse(chip.label.contains("Reading circles"), "starts on you: \(chip.label)")
        chip.tap()
        // A post stays in the jam it was made in (LIME-259): a post in my own space can only be mine, so no band is offered.
        XCTAssertTrue(app.buttons["jam-post-as-me"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["jam-post-as-jam-demo-band-demo-my-jam"].exists, "no band to move it to")
    }
}
