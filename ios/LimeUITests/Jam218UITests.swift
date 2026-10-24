import XCTest

/// LIME-218: Delete is last in the card menu; the Options sheet has the post's title in its header and Delete post last.
@MainActor
final class Jam218UITests: LimeUITestCase {
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "jam-mine"]
        app.launch()
        return app
    }

    func testTheCardMenuEndsWithDelete() {
        let app = launch()
        let more = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'card-more-'")).firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 10)); more.tap()
        let delete = app.buttons["Delete"].firstMatch, save = app.buttons["Save"].firstMatch, edit = app.buttons["Edit"].firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(delete.frame.minY, save.frame.minY, "Delete under Save")
        XCTAssertGreaterThan(delete.frame.minY, edit.frame.minY)
        let others = ["Share in lime\u{2026}", "Save", "Edit"].map { app.buttons[$0].firstMatch.frame.minY }
        XCTAssertTrue(others.allSatisfy { $0 < delete.frame.minY }, "last")
    }
}
