import XCTest

/// All | Unread and All | Missed with a filter menu (LIME-124).
@MainActor
final class FilterRowUITests: XCTestCase {
    private func app(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat"] + extra
        app.launch()
        return app
    }

    private func value(_ button: XCUIElement) -> String { (button.value as? String) ?? "" }

    func testTheLinkFilterRowIsTheFirstRowAndShowsItsMenu() {
        let app = app(["-lime-demo-screen", "groups-rows"])
        let segments = app.segmentedControls.firstMatch
        XCTAssertTrue(segments.waitForExistence(timeout: 10))
        XCTAssertTrue(segments.buttons["All"].exists && segments.buttons["Unread"].exists)
        let first = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'conversation-row-'")).firstMatch
        XCTAssertGreaterThanOrEqual(first.frame.minY, segments.frame.maxY - 4, "the filter row is above the first chat")
        // On iOS 26 the header is the system toolbar: the row sits 8 pt under it.
        let bar = app.navigationBars.firstMatch
        if bar.exists, bar.frame.height > 0 {
            // The row's top is the 40 pt filter button; the (shorter) segmented control is centred in it.
            let gap = app.buttons["chat-filter-button"].frame.minY - bar.frame.maxY
            XCTAssertEqual(gap, 8, accuracy: 4, "the row starts about 8 pt below the header (measured \(gap))")
        }
        let button = app.buttons["chat-filter-button"]
        XCTAssertTrue(button.exists)
        button.tap()
        for item in ["Direct messages", "Groups", "Pinned", "Muted"] {
            XCTAssertTrue(app.buttons[item].waitForExistence(timeout: 5), "menu item \(item)")
        }
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Requests'")).firstMatch.exists, "Requests is in the menu")
        XCTAssertFalse(app.buttons["Clear filters"].exists, "nothing to clear yet")
    }

    func testGroupsFilterShowsOnlyGroupsTheBadgeCountsAndClearFiltersResets() {
        let app = app(["-lime-demo-screen", "groups-rows"])
        let button = app.buttons["chat-filter-button"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        XCTAssertEqual(value(button), "")
        button.tap()
        app.buttons["Groups"].tap()
        XCTAssertTrue(app.buttons["conversation-row-grp:demo1"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["conversation-row-dm:lee"].exists, "only groups")
        XCTAssertEqual(value(button), "1", "the badge counts one filter")
        button.tap()
        app.buttons["Muted"].tap()   // none are muted
        XCTAssertTrue(app.staticTexts["No chats match"].waitForExistence(timeout: 5))
        XCTAssertEqual(value(button), "2")
        app.buttons["filter-clear-empty"].tap()
        XCTAssertTrue(app.buttons["conversation-row-dm:lee"].waitForExistence(timeout: 5), "Clear filters shows everything again")
        XCTAssertEqual(value(button), "", "and removes the badge")
    }

    func testCallsFilterRowAndMenu() {
        let app = app(["-lime-demo-calls"])
        XCTAssertTrue(app.tabBars.buttons["call"].waitForExistence(timeout: 10))
        app.tabBars.buttons["call"].tap()
        let segments = app.segmentedControls.firstMatch
        XCTAssertTrue(segments.waitForExistence(timeout: 5))
        XCTAssertTrue(segments.buttons["All"].exists && segments.buttons["Missed"].exists)
        let button = app.buttons["calls-filter-button"]
        button.tap()
        for item in ["Voice", "Video", "Incoming", "Outgoing"] { XCTAssertTrue(app.buttons[item].waitForExistence(timeout: 5), item) }
        app.buttons["Video"].tap()
        button.tap()
        app.buttons["Incoming"].tap()
        XCTAssertEqual(value(button), "2")
        XCTAssertTrue(app.staticTexts["No calls match"].waitForExistence(timeout: 5), "no incoming video calls in the demo list")
        app.buttons["filter-clear-empty"].tap()
        XCTAssertTrue(app.buttons.matching(identifier: "call-history-row").firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(value(button), "")
        // Voice + Incoming leaves Lee's calls only
        button.tap(); app.buttons["Voice"].tap()
        button.tap(); app.buttons["Incoming"].tap()
        let names = app.staticTexts.matching(identifier: "call-row-name").allElementsBoundByIndex.map(\.label)
        XCTAssertEqual(names, ["Lee Wong (2)", "Lee Wong"])
    }
}
