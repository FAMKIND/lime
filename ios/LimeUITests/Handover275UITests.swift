import XCTest

/// LIME-275c (demo): hand over a band's publishing: offer, pending, cancel; and an offer made to me, accepted or declined.
@MainActor
final class Handover275UITests: LimeUITestCase {
    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    func testOfferingABandShowsPendingAndCancelTakesItBack() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "jam-mine-profile", "-lime-demo-band-people", "-lime-demo-band-owner"]
        app.launch()
        XCTAssertTrue(app.buttons["profile-tab-Orgs"].waitForExistence(timeout: 10))
        app.buttons["profile-tab-Orgs"].tap()
        let row = any(app, "profile-org-demo-band-demo-my-jam")
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        row.tap()
        XCTAssertTrue(app.buttons["profile-org-more"].waitForExistence(timeout: 8))
        app.buttons["profile-org-more"].tap()
        XCTAssertTrue(app.buttons["handover-start"].waitForExistence(timeout: 5), "an owner of a real band can hand over publishing")
        app.buttons["handover-start"].tap()
        let sam = app.buttons["handover-owner-sam"]
        XCTAssertTrue(sam.waitForExistence(timeout: 5), "only the other owners are listed")
        XCTAssertFalse(app.buttons["handover-owner-lee"].exists, "a member is not offered")
        sam.tap()
        XCTAssertTrue(app.staticTexts["handover-confirm-text"].waitForExistence(timeout: 5))
        app.buttons["handover-confirm"].tap()
        app.buttons["profile-org-more"].tap()
        XCTAssertTrue(any(app, "handover-pending").waitForExistence(timeout: 5), "waiting for Sam")
        app.buttons["handover-cancel"].tap()
        app.buttons["profile-org-more"].tap()
        XCTAssertTrue(app.buttons["handover-start"].waitForExistence(timeout: 5), "taken back")
    }

    func testAnOfferMadeToMeIsAcceptedOrDeclinedFromTheCard() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "jam", "-lime-demo-handover-offer"]
        app.launch()
        let accept = app.buttons["handover-accept-demo-sam-band"]
        XCTAssertTrue(accept.waitForExistence(timeout: 10), "the offer shows with both answers")
        XCTAssertTrue(app.buttons["handover-decline-demo-sam-band"].exists)
        accept.tap()
        XCTAssertTrue(waitUntilGone(accept), "answered")
    }

    func testDecliningAnOfferRemovesIt() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "jam", "-lime-demo-handover-offer"]
        app.launch()
        let decline = app.buttons["handover-decline-demo-sam-band"]
        XCTAssertTrue(decline.waitForExistence(timeout: 10))
        decline.tap()
        XCTAssertTrue(waitUntilGone(decline))
    }

    private func waitUntilGone(_ element: XCUIElement) -> Bool {
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: element)
        return XCTWaiter().wait(for: [gone], timeout: 6) == .completed
    }
}
