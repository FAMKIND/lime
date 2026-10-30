import XCTest

/// LIME-256: Report group from the group's ⋯: recent messages (each can be left out), the name and photo, who's in it (off), leave afterwards (demo).
@MainActor
final class ReportGroup256UITests: LimeUITestCase {
    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    private func openReport() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "group-details"]
        app.launch()
        XCTAssertTrue(app.buttons["group-more"].waitForExistence(timeout: 8))
        app.buttons["group-more"].tap()
        XCTAssertTrue(app.buttons["group-more-report"].waitForExistence(timeout: 5), "Report group is in ⋯")
        app.buttons["group-more-report"].tap()
        XCTAssertTrue(app.buttons["report-reason-harassment"].waitForExistence(timeout: 5))
        return app
    }

    func testTheSheetListsRecentMessagesTickedMembersOffAndSendCarriesOnlyTheTickedOnes() {
        let app = openReport()
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'report-message-'"))
        XCTAssertEqual(rows.count, 3, "the recent messages")
        XCTAssertTrue(rows.element(boundBy: 0).label.hasSuffix("on"), "ticked: \(rows.element(boundBy: 0).label)")
        XCTAssertEqual(any(app, "report-group-name").value as? String, "1", "the name and photo are on")
        XCTAssertEqual(any(app, "report-group-members").value as? String, "0", "who's in the group is off")
        XCTAssertEqual(any(app, "report-group-leave").value as? String, "0")
        // Leave one out.
        rows.element(boundBy: 1).tap()
        XCTAssertTrue(rows.element(boundBy: 1).label.hasSuffix("off"))
        app.buttons["report-reason-harassment"].tap()
        app.buttons["report-send"].tap()
        XCTAssertTrue(app.staticTexts["report-thanks"].waitForExistence(timeout: 8))
        let probe = any(app, "report-probe").label
        XCTAssertTrue(probe.hasPrefix("group grp:"), probe)
        XCTAssertTrue(probe.contains("lee") && probe.contains("priya.nair") && !probe.contains("sam"), "only the ticked messages' senders: \(probe)")
        let included = any(app, "report-included-probe").label
        XCTAssertTrue(included.contains("Can we plan the field trip") && included.contains("Friday works") && !included.contains("permission forms"), included)
        XCTAssertTrue(included.contains("\"name\":\"Grade 4 Team\""))
        XCTAssertFalse(included.contains("\"members\""), "no member list unless asked")
    }

    func testWithMembersAndLeaveTheReportCarriesThePeopleAndYouLeave() {
        let app = openReport()
        any(app, "report-group-members").tap()
        any(app, "report-group-leave").tap()
        app.buttons["report-reason-spam"].tap()
        app.buttons["report-send"].tap()
        XCTAssertTrue(app.staticTexts["report-thanks"].waitForExistence(timeout: 8))
        XCTAssertTrue(any(app, "report-included-probe").label.contains("\"members\""), "the list was asked for")
        app.buttons["report-done"].tap()
        XCTAssertTrue(app.buttons["group-more"].waitForNonExistence(timeout: 8), "you left the group")
    }
}
