import XCTest

/// LIME-277e (demo): a contact's profile colour reaches this phone and colours their profile's default top.
@MainActor
final class Tone277eUITests: LimeUITestCase {
    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    func testAContactsProfileColourColoursTheirProfileWhenTheyHaveNoCover() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-lee-tone", "-lime-demo-screen", "profile-lee"]
        app.launch()
        XCTAssertTrue(any(app, "profile-hero-tone-4").waitForExistence(timeout: 10), "Lee chose Blue: his profile's top uses it")
    }

    func testWithoutAColourTheProfileKeepsItsAutomaticOne() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "profile-lee"]
        app.launch()
        XCTAssertTrue(app.buttons["profile-message"].waitForExistence(timeout: 10))
        XCTAssertFalse(any(app, "profile-hero-tone-4").exists)
    }
}
