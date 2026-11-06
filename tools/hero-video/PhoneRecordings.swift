import XCTest

/// LIME-284e2: the two phone recordings for limemessenger.com (`tools/hero-video/record-phones.sh` runs these while
/// `xcrun simctl io booted recordVideo` records). Copy into ios/LimeUITests/ to run; not part of the suite.
@MainActor
final class PhoneRecordings: XCTestCase {
    func testJam() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "jam-marketing"]
        app.launch()
        sleep(4)
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.74))
        let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.40))
        for _ in 0..<5 {
            from.press(forDuration: 0.05, thenDragTo: to, withVelocity: 110, thenHoldForDuration: 0.1)
            sleep(2)
        }
        sleep(2)
    }

    func testChat() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "chat"]
        app.launch()
        sleep(4)
        let field = app.textViews["composer-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        sleep(1)
        field.typeText("Friday works for me. See you there!")
        sleep(1)
        app.buttons["send-button"].tap()
        sleep(4)
    }
}
