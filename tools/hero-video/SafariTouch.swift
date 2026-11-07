import XCTest

/// LIME-284c3f: drives the website's hero in the iOS simulator's Safari with real touches (a tap on each half, a touch-and-hold with a drag, a vertical swipe, a horizontal swipe).
/// Load the page first (`xcrun simctl openurl <device> http://localhost:8099/`) and record the screen with `xcrun simctl io <device> recordVideo`; see tools/hero-video/safari-touch.sh.
/// Copy into ios/LimeUITests/ to run; not part of the suite.
@MainActor
final class SafariTouch: XCTestCase {
    private func at(_ app: XCUIApplication, _ x: Double, _ y: Double) -> XCUICoordinate { app.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y)) }
    private func snap(_ name: String) { try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/284c3f/\(name).png")) }

    func testTouch() {
        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        safari.activate(); sleep(3); snap("0-idle")
        at(safari, 0.78, 0.22).tap(); usleep(180_000); snap("1-tap-right-portal"); sleep(3); snap("1b-after-bloom")
        at(safari, 0.2, 0.22).tap(); usleep(180_000); snap("2-tap-left-portal"); sleep(3); snap("2b-after-bloom")
        // touch and hold on the right half for 0.7 s, then drag to the left half and lift: the portal is above the finger and follows it; lifting blooms to the previous slide
        at(safari, 0.6, 0.30).press(forDuration: 0.7, thenDragTo: at(safari, 0.25, 0.26)); sleep(3); snap("3-after-hold-drag")
        // a normal vertical swipe scrolls the page
        at(safari, 0.5, 0.45).press(forDuration: 0.05, thenDragTo: at(safari, 0.5, 0.15)); sleep(1); snap("4-after-vertical-swipe")
        safari.swipeDown(); sleep(1)
        // a quick horizontal swipe changes the slide with no portal
        at(safari, 0.85, 0.25).press(forDuration: 0.05, thenDragTo: at(safari, 0.15, 0.27)); usleep(300_000); snap("5-swipe-no-portal"); sleep(3)
    }
}
