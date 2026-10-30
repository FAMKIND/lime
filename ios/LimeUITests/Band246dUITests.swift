import XCTest

/// LIME-246d: a band's QR code opens "Join <band>?" from the scanner; a group inside a band shows the band's picture as a badge in the chat list.
@MainActor
final class Band246dUITests: LimeUITestCase {
    func testScanningABandCodeOpensTheJoinSheet() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "scan-band"]
        app.launch()
        XCTAssertTrue(app.buttons["org-join"].waitForExistence(timeout: 12), "Join <band>?")
    }

    func testAGroupInsideABandShowsTheBandsBadgeAndAnOrdinaryGroupDoesNot() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "band-group-rows"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'band-badge-'")).firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'band-badge-'")).count, 1, "only the band's group")
    }
}
