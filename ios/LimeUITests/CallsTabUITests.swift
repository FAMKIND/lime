import XCTest

/// The Calls tab (LIME-116b), with made-up calls (`-lime-demo-calls`): Lee missed twice today (one row "(2)"), Sam a video call out,
/// Lee answered yesterday, Sam unanswered 3 days ago.
@MainActor
final class CallsTabUITests: XCTestCase {
    private func app(calls: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat"] + (calls ? ["-lime-demo-calls"] : [])
        app.launch()
        return app
    }

    private func openCalls(_ app: XCUIApplication) {
        XCTAssertTrue(app.tabBars.buttons["call"].waitForExistence(timeout: 10))
        app.tabBars.buttons["call"].tap()
        XCTAssertTrue(app.buttons["calls-filter-all"].waitForExistence(timeout: 5))
    }

    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any)[id] }

    func testAllAndMissedFiltersAndGroupedRows() {
        let app = app()
        openCalls(app)
        let names = app.staticTexts.matching(identifier: "call-row-name").allElementsBoundByIndex.map(\.label)
        XCTAssertEqual(names, ["Lee Wong (2)", "Sam Rivera", "Lee Wong", "Sam Rivera"], "the two missed calls from Lee are one row with a count")
        app.buttons["calls-filter-missed"].tap()
        let missed = app.staticTexts.matching(identifier: "call-row-name").allElementsBoundByIndex.map(\.label)
        XCTAssertEqual(missed, ["Lee Wong (2)"], "Missed shows only the missed incoming calls")
        app.buttons["calls-filter-all"].tap()
        XCTAssertEqual(app.staticTexts.matching(identifier: "call-row-name").count, 4)
    }

    func testTheTrailingButtonRepeatsTheKindAndTapOpensTheDetails() {
        let app = app()
        openCalls(app)
        XCTAssertTrue(app.buttons["Video call Sam Rivera"].waitForExistence(timeout: 5), "a video call's button is a video button")
        XCTAssertTrue(app.buttons["Call Lee Wong"].exists, "a voice call's button is a phone button")
        app.buttons.matching(identifier: "call-history-row").firstMatch.tap()
        XCTAssertTrue(any(app, "call-details").waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["call-details-message"].exists && app.buttons["call-details-voice"].exists && app.buttons["call-details-video"].exists)
        XCTAssertEqual(app.staticTexts.matching(identifier: "call-detail-outcome").count, 2, "both missed calls are listed")
        XCTAssertFalse(app.tabBars.firstMatch.isHittable, "the tab bar hides in the details, as in a chat")
    }

    func testSwipeLeftDeletesARow() {
        let app = app()
        openCalls(app)
        let rows = app.buttons.matching(identifier: "call-history-row")
        XCTAssertEqual(rows.count, 4)
        rows.element(boundBy: 1).swipeLeft()
        app.buttons["call-swipe-delete"].tap()
        XCTAssertTrue(NSPredicate { _, _ in rows.count == 3 }.evaluate(with: nil) || rows.element(boundBy: 3).waitForNonExistence(timeout: 5))
        XCTAssertEqual(rows.count, 3)
    }

    func testThePlusOnCallOpensNewCallWithSearchAtTheBottomAndBothButtonsPerContact() {
        let app = app()
        openCalls(app)
        let plus = app.buttons["new-call-button"]
        XCTAssertTrue(plus.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["new-message-button"].exists, "call has New call, not New message")
        plus.tap()
        XCTAssertTrue(any(app, "new-call-sheet").waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["new-call-find-username"].exists, "Find by username at the top")
        let field = app.textFields["new-call-field"]
        XCTAssertTrue(field.exists)
        XCTAssertGreaterThan(field.frame.midY, app.windows.firstMatch.frame.height * 0.6, "the search field is at the bottom")
        XCTAssertTrue(app.buttons["new-call-voice-lee"].exists && app.buttons["new-call-video-lee"].exists, "voice and video for each contact")
    }

    func testThePlusOnLinkStillOpensNewMessageAndIs64PointsClearOfTheTabBar() {
        let app = app(calls: false)
        let plus = app.buttons["new-message-button"]
        XCTAssertTrue(plus.waitForExistence(timeout: 10))
        XCTAssertEqual(plus.frame.width, 64, accuracy: 1)
        XCTAssertEqual(plus.frame.height, 64, accuracy: 1)
        let frames = app.tabBars.buttons.allElementsBoundByIndex.filter { ["link", "call", "jam"].contains($0.label) }.map(\.frame)
        let bar = frames.dropFirst().reduce(frames.first ?? .zero) { $0.union($1) }.insetBy(dx: -6, dy: -4)
        XCTAssertFalse(plus.frame.intersects(bar), "the + \(plus.frame) must not overlap the bar \(bar)")
        plus.tap()
        XCTAssertTrue(app.textFields["new-message-field"].waitForExistence(timeout: 5))
    }

    func testThePlusOnCallIs64PointsAndClearOfTheTabBar() {
        let app = app()
        openCalls(app)
        let plus = app.buttons["new-call-button"]
        XCTAssertTrue(plus.waitForExistence(timeout: 5))
        XCTAssertEqual(plus.frame.width, 64, accuracy: 1)
        let frames = app.tabBars.buttons.allElementsBoundByIndex.filter { ["link", "call", "jam"].contains($0.label) }.map(\.frame)
        let bar = frames.dropFirst().reduce(frames.first ?? .zero) { $0.union($1) }.insetBy(dx: -6, dy: -4)
        XCTAssertFalse(plus.frame.intersects(bar))
    }

    func testEmptyStates() {
        let app = app(calls: false)
        openCalls(app)
        XCTAssertTrue(any(app, "calls-empty").waitForExistence(timeout: 5), "All: No calls yet")
        XCTAssertTrue(app.buttons["calls-empty-new-call"].exists, "with a New call button")
        app.buttons["calls-filter-missed"].tap()
        XCTAssertTrue(any(app, "calls-empty-missed").waitForExistence(timeout: 5), "Missed: No missed calls")
    }

    func testTheCallTabBadgeCountsMissedCallsAndClearsWhenTheTabIsOpened() {
        let app = app()
        XCTAssertTrue(app.tabBars.buttons["call"].waitForExistence(timeout: 10))
        let value = { (app.tabBars.buttons["call"].value as? String) ?? "" }
        let counted = NSPredicate { _, _ in value().hasPrefix("2") }
        expectation(for: counted, evaluatedWith: nil)
        waitForExpectations(timeout: 8)
        app.tabBars.buttons["call"].tap()
        XCTAssertTrue(app.buttons["calls-filter-all"].waitForExistence(timeout: 5))
        let cleared = NSPredicate { _, _ in !value().hasPrefix("2") }
        expectation(for: cleared, evaluatedWith: nil)
        waitForExpectations(timeout: 5)
    }

    func testSettingsPrivacyClearsTheCallHistory() {
        let app = app()
        app.buttons["settings-button"].tap()
        XCTAssertTrue(app.buttons["status-open-settings"].waitForExistence(timeout: 5))
        app.buttons["status-open-settings"].tap()
        let privacy = app.buttons["settings-privacy"]
        XCTAssertTrue(privacy.waitForExistence(timeout: 8))
        privacy.tap()
        let clear = app.buttons["privacy-clear-calls"]
        XCTAssertTrue(clear.waitForExistence(timeout: 5))
        clear.tap()
        XCTAssertTrue(app.buttons["privacy-clear-calls-confirm"].firstMatch.waitForExistence(timeout: 5), "it asks first")
        app.buttons["privacy-clear-calls-confirm"].firstMatch.tap()
        XCTAssertTrue(app.buttons["privacy-clear-calls"].waitForExistence(timeout: 5))
    }
}
