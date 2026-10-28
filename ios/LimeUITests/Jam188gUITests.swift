import XCTest

/// LIME-188g: Record is a podcast: the dark recorder (audio by default, a camera toggle), co-hosts, and a player with a waveform to scrub.
@MainActor
final class Jam188gUITests: LimeUITestCase {
    private func launch(_ screen: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat"] + (screen.map { ["-lime-demo-screen", $0] } ?? [])
        app.launch()
        return app
    }

    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    private func field(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.textFields[id].exists ? app.textFields[id] : app.textViews[id]
    }

    func testARecordingGetsATitleAndCoHostsThenPostsAsAPodcast() {
        let app = launch("jam")
        app.buttons["new-jam-post"].tap()
        app.buttons["jam-record"].tap()
        XCTAssertTrue(any(app, "podcast-recorder").waitForExistence(timeout: 8), "the recorder (LIME-239a)")
        app.buttons["podcast-record"].tap()
        XCTAssertTrue(app.buttons["podcast-stop"].waitForExistence(timeout: 5))
        sleep(2)
        XCTAssertNotEqual(any(app, "podcast-timer").label, "", "the timer runs")
        app.buttons["podcast-stop"].tap()
        XCTAssertTrue(app.buttons["podcast-next"].waitForExistence(timeout: 8), "the details page (LIME-239b)")
        XCTAssertFalse(app.buttons["podcast-next"].isEnabled, "a take but no title yet")
        let title = field(app, "podcast-title")
        title.tap(); title.typeText("Sunday planning")
        XCTAssertTrue(app.buttons["podcast-next"].isEnabled, "a take and a title: Next")
        app.buttons["podcast-hosts"].tap()
        let sam = app.buttons["jam-coauthor-choice-sam"]
        XCTAssertTrue(sam.waitForExistence(timeout: 5), "co-hosts come from your contacts")
        sam.tap()
        app.buttons["jam-coauthor-done"].tap()
        publishPodcast(app)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Sunday planning'")).firstMatch.waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'jam-audio-card-' OR identifier == 'jam-video'")).firstMatch.waitForExistence(timeout: 5), "the recording is a card")
    }
}
