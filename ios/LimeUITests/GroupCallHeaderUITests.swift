import XCTest

/// The group call's header (LIME-147): the 1:1 call's look, the timer and the four-emoji check, with the explainer sheet.
@MainActor
final class GroupCallHeaderUITests: XCTestCase {
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "group-call-4"]
        app.launch()
        return app
    }

    func testTheHeaderHasThePillTheTimerAndTheEncryptionChipAndTheChipExplainsItself() {
        let app = launch()
        let pill = app.buttons["Grade 4 Team, people in the call"]
        XCTAssertTrue(pill.waitForExistence(timeout: 15), "the group's pill")
        let chip = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Encrypted call. Emoji: '")).firstMatch
        XCTAssertTrue(chip.exists, "the encryption chip after the timer")
        XCTAssertEqual(chip.label.dropFirst("Encrypted call. Emoji: ".count).split(separator: ",").count, 4, "four names for VoiceOver: \(chip.label)")
        XCTAssertGreaterThanOrEqual(chip.frame.height, 44, "a big enough target")
        XCTAssertLessThan(pill.frame.maxY, chip.frame.minY + 1, "the pill is above the timer line")
        chip.tap()
        XCTAssertTrue(app.staticTexts["Compare these 4 with everyone in the call. If you all see the same 4, nobody else can see or hear the call."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["They change when someone joins or leaves, so compare again."].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Verify in person'")).firstMatch.exists, "it says it does not prove who people are")
    }

    func testThePillOpensThePeopleAndMinimiseStaysInTheControls() {
        let app = launch()
        XCTAssertTrue(app.buttons["Grade 4 Team, people in the call"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["Minimise"].exists, "Minimise is in the controls row")
        XCTAssertFalse(app.buttons["Minimise call"].exists, "the header's chevron is gone: the pill takes the corner")
        app.buttons["Grade 4 Team, people in the call"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Shem'")).firstMatch.waitForExistence(timeout: 5), "the people in the call")
    }
}
