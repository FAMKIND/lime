import XCTest

/// LIME-188z: reading an article: the dock and the actions hide as you read down and come back as you scroll up.
@MainActor
final class Jam188zUITests: LimeUITestCase {
    func testScrollingDownHidesTheDockAndTheActionsAndScrollingUpBringsThemBack() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "jam-mine-asjam"]
        app.launch()
        app.showJamArticles()
        let card = app.buttons.matching(NSPredicate(format: "label CONTAINS 'How we read together'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10)); card.tap()
        let like = app.buttons["like"]
        XCTAssertTrue(like.waitForExistence(timeout: 8))
        XCTAssertTrue(like.isHittable, "shown at the top: pill \(like.frame), dock \(app.tabBars.firstMatch.frame), window \(app.windows.firstMatch.frame)")
        for _ in 0..<2 { app.swipeUp(velocity: .slow) }
        expectation(for: NSPredicate(format: "hittable == false"), evaluatedWith: like)
        waitForExpectations(timeout: 5)
        XCTAssertFalse(app.tabBars.buttons["jam"].isHittable, "the dock is away")
        app.swipeDown(velocity: .slow)
        expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: like)
        waitForExpectations(timeout: 5)
    }
}
