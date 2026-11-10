import XCTest

/// LIME-280 (demo, no media): the video call's Effects button opens a menu of reactions and Video effects; without a camera that can, there is no button.
@MainActor
final class Effects280UITests: XCTestCase {
    private func call(_ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-call", "video"] + extra
        app.launch()
        return app
    }

    func testTheEffectsButtonOpensTheReactionsAndVideoEffects() {
        let app = call(["-lime-demo-effects"])
        let button = app.descendants(matching: .any).matching(identifier: "call-effects").firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 10), "Effects is in the video call's controls")
        XCTAssertEqual(button.label, "Effects")
        button.tap()
        for name in ["Hearts", "Thumbs up", "Confetti", "Rain", "Video effects\u{2026}"] {
            XCTAssertTrue(app.buttons[name].waitForExistence(timeout: 5), name)
        }
        XCTAssertFalse(app.buttons["Fireworks"].exists || app.buttons["Lasers"].exists, "the two that flash are not offered (LIME-130-4c)")
    }

    func testNoButtonWhereTheCameraCannotDoEffects() {
        let app = call([])
        XCTAssertTrue(app.buttons["call-end"].waitForExistence(timeout: 10))
        sleep(2)
        XCTAssertFalse(app.buttons["call-effects"].exists)
    }
}
