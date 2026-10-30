import XCTest

/// LIME-259: one kind of band. An old-style band (the profile space renamed) becomes a real band on its own; the space is never a band; Delete band asks.
@MainActor
final class Band259UITests: LimeUITestCase {
    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    func testAnOldStyleBandBecomesARealOneWithANoteAndPostAsOffersItAndTheSpaceIsNeverABand() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "jam-mine-profile", "-lime-demo-old-band", "-lime-demo-jam-picture"]
        app.launch()
        XCTAssertTrue(app.buttons["profile-tab-Orgs"].waitForExistence(timeout: 10))
        app.buttons["profile-tab-Orgs"].tap()
        let row = any(app, "profile-org-demo-band-demo-my-jam")
        XCTAssertTrue(row.waitForExistence(timeout: 8), "the old-style band is a real band now")
        XCTAssertTrue(row.label.contains("Reading circles"), row.label)
        XCTAssertFalse(any(app, "profile-org-demo-my-jam").exists, "the profile space is never a band")
        row.tap()
        XCTAssertTrue(app.staticTexts["org-cleanup-note"].waitForExistence(timeout: 5), "once: what happened")
        XCTAssertTrue(app.staticTexts["org-cleanup-note"].label.contains("Earlier posts stay with your profile"))
    }

    func testDeleteBandAsksWithTheNewWordsAndTheBandIsGoneFromBandsAndPostAs() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "jam-mine-profile"]
        app.launch()
        XCTAssertTrue(app.buttons["profile-tab-Orgs"].waitForExistence(timeout: 10))
        app.buttons["profile-tab-Orgs"].tap()
        let row = any(app, "profile-org-demo-band-demo-my-jam")
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        row.swipeLeft()
        app.buttons["org-swipe-end-demo-band-demo-my-jam"].tap()
        XCTAssertTrue(app.staticTexts["Delete Reading circles?"].waitForExistence(timeout: 5) || app.buttons["jam-end-confirm"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["jam-end-confirm"].firstMatch.label, "Delete")
        XCTAssertTrue(app.staticTexts["Its page and picture are removed. Subscribers keep posts they already have."].exists)
        app.buttons["jam-end-confirm"].firstMatch.tap()
        XCTAssertTrue(app.buttons["profile-tab-Orgs"].waitForNonExistence(timeout: 5) || !any(app, "profile-org-demo-band-demo-my-jam").exists, "gone from Bands")
    }
}
