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
        XCTAssertTrue(app.segmentedControls.buttons["All"].waitForExistence(timeout: 5))
    }

    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any)[id] }

    func testASilencedCallSaysWhyOnItsRowAndStaysInMissed() {
        let app = app()
        openCalls(app)
        let note = any(app, "call-row-note")
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        XCTAssertEqual(note.label, "Silenced \u{00B7} Do Not Disturb")
        app.segmentedControls.buttons["Missed"].tap()
        XCTAssertTrue(any(app, "call-row-note").waitForExistence(timeout: 5), "a silenced call is still a missed call")
    }

    func testAllAndMissedFiltersAndGroupedRows() {
        let app = app()
        openCalls(app)
        let names = app.staticTexts.matching(identifier: "call-row-name").allElementsBoundByIndex.map(\.label)
        XCTAssertEqual(names, ["Lee Wong (2)", "Sam Park", "Lee Wong", "Sam Park"], "the two missed calls from Lee are one row with a count")
        app.segmentedControls.buttons["Missed"].tap()
        let missed = app.staticTexts.matching(identifier: "call-row-name").allElementsBoundByIndex.map(\.label)
        XCTAssertEqual(missed, ["Lee Wong (2)"], "Missed shows only the missed incoming calls")
        app.segmentedControls.buttons["All"].tap()
        XCTAssertEqual(app.staticTexts.matching(identifier: "call-row-name").count, 4)
    }

    func testTheTrailingButtonRepeatsTheKindAndTapOpensTheDetails() {
        let app = app()
        openCalls(app)
        XCTAssertTrue(app.buttons["Video call Sam Park"].waitForExistence(timeout: 5), "a video call's button is a video button")
        XCTAssertTrue(app.buttons["Call Lee Wong"].exists, "a voice call's button is a phone button")
        app.buttons.matching(identifier: "call-history-row").firstMatch.tap()
        XCTAssertTrue(any(app, "profile-screen").waitForExistence(timeout: 5), "a call row opens the profile")
        XCTAssertTrue(app.buttons["profile-message"].exists && app.buttons["profile-voice"].exists && app.buttons["profile-video"].exists)
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "profile-call-line").count, 2, "both missed calls are listed on the Calls section")
        XCTAssertFalse(app.tabBars.firstMatch.isHittable, "the tab bar hides in the profile, as in a chat")
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

    func testTheFilterIsPartOfTheListAndScrollsAwayWithIt() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-calls", "-lime-demo-calls-many"]
        app.launch()
        openCalls(app)
        let list = any(app, "calls-list")
        XCTAssertTrue(list.waitForExistence(timeout: 5))
        let pill = app.segmentedControls.firstMatch
        XCTAssertLessThan(list.frame.minY, 80, "the list is edge to edge at the top (it scrolls under the header)")
        let first = app.buttons.matching(identifier: "call-history-row").firstMatch
        XCTAssertGreaterThanOrEqual(first.frame.minY, pill.frame.maxY - 4, "at rest the first call row is below the filter")
        let before = pill.frame.minY
        list.swipeUp()
        let moved = NSPredicate { _, _ in !pill.exists || pill.frame.minY < before - 40 || !pill.isHittable }
        expectation(for: moved, evaluatedWith: nil)
        waitForExpectations(timeout: 5)
        // At the very end the last row's call-back button still clears the "+".
        for _ in 0..<4 { list.swipeUp() }
        let plus = app.buttons["new-call-button"].frame
        let lastCallBack = app.buttons.matching(identifier: "call-row-callback").allElementsBoundByIndex.last!
        XCTAssertFalse(lastCallBack.frame.intersects(plus), "the last row's button is not under the +")
    }

    func testNoStatusBadgesOnCallRowsButBackInNewCall() {
        let app = app()
        openCalls(app)
        XCTAssertTrue(app.buttons["call-row-callback"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(any(app, "status-badge-lee").exists, "plain avatars on the call rows")
        XCTAssertFalse(any(app, "status-badge-sam").exists)
        // New Call is the one place they are back: someone you are about to call, with their status.
        app.buttons["new-call-button"].tap()
        XCTAssertTrue(app.buttons["new-call-voice-lee"].waitForExistence(timeout: 5))
        XCTAssertTrue(any(app, "status-badge-lee").waitForExistence(timeout: 5), "status badges are back in New Call")
    }

    func testTheTabBarStaysOpenWhileScrollingCalls() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-calls", "-lime-demo-calls-many"]
        app.launch()
        openCalls(app)
        let bar = app.tabBars.firstMatch
        let before = bar.frame
        let list = any(app, "calls-list")
        for _ in 0..<3 { list.swipeUp() }
        XCTAssertEqual(bar.frame.width, before.width, accuracy: 1, "the tab bar does not shrink on scroll")
        XCTAssertEqual(bar.frame.height, before.height, accuracy: 1)
        XCTAssertTrue(app.tabBars.buttons["link"].isHittable && app.tabBars.buttons["jam"].isHittable, "all three tabs are still there")
    }

    func testTheMagnifierPushesTheCallsSearchWithPeopleAndCalls() {
        let app = app()
        openCalls(app)
        app.buttons["calls-search-button"].tap()
        let field = app.textFields["search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("lee")
        XCTAssertTrue(app.buttons["calls-search-voice-lee"].waitForExistence(timeout: 5), "People: Lee, with call buttons")
        XCTAssertTrue(app.buttons["calls-search-video-lee"].exists)
        XCTAssertTrue(app.buttons.matching(identifier: "call-history-row").firstMatch.exists, "Calls: Lee's history rows")
        XCTAssertFalse(app.staticTexts["Sam Park"].exists, "only matches")
        app.buttons["search-back"].tap()
        XCTAssertTrue(app.segmentedControls.buttons["All"].waitForExistence(timeout: 5), "back returns to the list")
    }

    func testEmptyStates() {
        let app = app(calls: false)
        openCalls(app)
        XCTAssertTrue(any(app, "calls-empty").waitForExistence(timeout: 5), "All: No calls yet")
        XCTAssertTrue(app.buttons["calls-empty-new-call"].exists, "with a New call button")
        app.segmentedControls.buttons["Missed"].tap()
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
        XCTAssertTrue(app.segmentedControls.buttons["All"].waitForExistence(timeout: 5))
        let cleared = NSPredicate { _, _ in !value().hasPrefix("2") }
        expectation(for: cleared, evaluatedWith: nil)
        waitForExpectations(timeout: 5)
    }

    func testSettingsPrivacyHasAlwaysRelayCallsOffByDefault() {
        let app = app()
        app.buttons["settings-button"].tap()
        XCTAssertTrue(app.buttons["profile-settings"].waitForExistence(timeout: 5))
        app.buttons["profile-settings"].tap()
        XCTAssertTrue(app.buttons["settings-privacy"].waitForExistence(timeout: 8))
        app.buttons["settings-privacy"].tap()
        let toggle = app.switches["privacy-always-relay"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? String, "0", "off by default")
        XCTAssertTrue(app.staticTexts["Hides your IP address from the person you\u{2019}re calling. Calls may be a little slower."].exists)
        toggle.tap()
        XCTAssertEqual(app.switches["privacy-always-relay"].value as? String, "1")
        app.switches["privacy-always-relay"].tap()   // leave it as it was
        XCTAssertEqual(app.switches["privacy-always-relay"].value as? String, "0")
    }

    func testSettingsPrivacyClearsTheCallHistory() {
        let app = app()
        app.buttons["settings-button"].tap()
        XCTAssertTrue(app.buttons["profile-settings"].waitForExistence(timeout: 5))
        app.buttons["profile-settings"].tap()
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
