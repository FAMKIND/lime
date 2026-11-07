import XCTest

/// LIME-284e15: opens the report sheet in the demo chat so `xcrun simctl io booted screenshot` can capture it (copy into ios/LimeUITests/ to run; not part of the suite).
@MainActor
final class SafetyShot: XCTestCase {
    func testReportSheet() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "chat"]
        app.launch()
        sleep(4)
        let msg = app.staticTexts["Are you coming to the staff meeting?"]
        XCTAssertTrue(msg.waitForExistence(timeout: 10))
        msg.press(forDuration: 0.9)
        sleep(2)
        let report = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Report'")).firstMatch
        XCTAssertTrue(report.waitForExistence(timeout: 5))
        report.tap()
        sleep(30)   // the screenshot is taken in this window
    }
}
