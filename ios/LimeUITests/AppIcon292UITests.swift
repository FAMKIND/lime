import XCTest

/// LIME-292b: Settings → Customize → App icon shows eight icons, lime's own selected. (Picking one opens the system's alert, which the simulator
/// cannot drive reliably, so choosing is checked on the phones.)
final class AppIcon292UITests: LimeUITestCase {
    func testTheAppIconScreenShowsEightIconsWithLimeSelected() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "settings/app-icon"]
        app.launch()
        for name in ["lime", "dark", "minimal", "pixel", "rainbow", "notebook", "chalkboard", "apple"] {
            XCTAssertTrue(app.buttons["app-icon-\(name)"].waitForExistence(timeout: 8), name)
        }
        XCTAssertEqual(app.buttons["app-icon-lime"].label, "lime app icon")
        XCTAssertTrue(app.buttons["app-icon-lime"].isSelected, "the icon in use is selected")
        XCTAssertFalse(app.buttons["app-icon-pixel"].isSelected)
        XCTAssertGreaterThanOrEqual(app.buttons["app-icon-pixel"].frame.height, 44)
    }
}
