import XCTest

/// LIME-284a4: a slow, natural scroll through jam's feed, for `tools/hero-video/` to record
/// (`xcrun simctl io booted recordVideo`). Copy into ios/LimeUITests/ to run; not part of the suite.
@MainActor
final class HeroScrollRecording: XCTestCase {
    func testScroll() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "jam-mine-asjam"]
        app.launch()
        sleep(3)
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.74))
        let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.46))
        for _ in 0..<5 {
            from.press(forDuration: 0.05, thenDragTo: to, withVelocity: 120, thenHoldForDuration: 0.1)
            sleep(2)
        }
        sleep(2)
    }
}
