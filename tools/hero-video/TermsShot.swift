import XCTest

/// LIME-285: opens the sign-up's terms screen and waits so `xcrun simctl io booted screenshot` can capture it (copy into ios/LimeUITests/ to run; not part of the target).
@MainActor
final class TermsShot: XCTestCase {
    func testTermsScreen() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-fake-auth", "-lime-reset-session", "-lime-reset-store"]
        app.launch()
        app.buttons["welcome-continue"].tap()
        let f = app.textFields["identifier-field"]; XCTAssertTrue(f.waitForExistence(timeout: 10)); f.tap(); f.typeText("new.teacher@example.com")
        app.buttons["next-button"].tap()
        app.buttons["confirm-yes"].tap()
        let c = app.textFields["code-field"]; XCTAssertTrue(c.waitForExistence(timeout: 10)); c.tap(); c.typeText("123456")
        app.buttons["next-button"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "terms-agree").firstMatch.waitForExistence(timeout: 10))
        sleep(25)   // the screenshot is taken in this window
    }
}
