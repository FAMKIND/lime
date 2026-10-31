import XCTest

/// LIME-281 (demo): a band I only write for shows on my profile but has no Edit, colour or Delete band; my own band still does, and Delete works on it.
@MainActor
final class Band281UITests: LimeUITestCase {
    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    private func profile(_ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "jam-mine-profile"] + extra
        app.launch()
        XCTAssertTrue(app.buttons["profile-tab-Orgs"].waitForExistence(timeout: 10))
        app.buttons["profile-tab-Orgs"].tap()
        return app
    }

    func testABandIWriteForButDoNotOwnHasNoEditColourOrDelete() {
        let app = profile(["-lime-demo-writer-band"])
        let row = any(app, "profile-org-demo-sam-band")
        XCTAssertTrue(row.waitForExistence(timeout: 8), "the band I write for is listed")
        row.tap()
        XCTAssertTrue(app.buttons["profile-tab-Info"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["jam-edit-page"].exists, "no Edit")
        XCTAssertFalse(app.buttons["org-theme"].exists, "no colour")
        app.buttons["profile-org-more"].tap()
        XCTAssertFalse(app.buttons["jam-end"].exists, "no Delete band")
        XCTAssertFalse(app.buttons["jam-subscribers"].exists, "no owner's subscribers list")
    }

    func testMyOwnBandStillHasEditAndDeleteAndDeleteWorks() {
        let app = profile([])
        let row = any(app, "profile-org-demo-band-demo-my-jam")
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        row.tap()
        XCTAssertTrue(app.buttons["jam-edit-page"].waitForExistence(timeout: 8), "Edit on my own band")
        XCTAssertTrue(app.buttons["org-theme"].exists)
    }
}
