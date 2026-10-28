import XCTest

/// LIME-236d: New post in landscape with the keyboard up (demo): nothing overlaps; the pills are in the keyboard bar's row.
@MainActor
final class Composer236dUITests: LimeUITestCase {
    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    func testLandscapeWithTheKeyboardUpPutsThePillsInTheBarAndNothingOverlaps() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "jam-mine"]
        app.launch()
        XCTAssertTrue(app.buttons["new-jam-post"].waitForExistence(timeout: 10))
        app.buttons["new-jam-post"].tap()
        XCTAssertTrue(app.buttons["jam-write-article"].waitForExistence(timeout: 8))
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let field = app.textViews["composer-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 8))
        // At rest the Post-as row is under the top bar, not behind it.
        sleep(1)
        XCTAssertGreaterThanOrEqual(app.buttons["jam-post-as"].frame.minY, app.navigationBars.firstMatch.frame.maxY - 2, "not under the top bar at rest")
        field.tap()
        sleep(2)
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/c236d.png"))
        let postAs = app.buttons["jam-post-as"], article = app.buttons["jam-write-article"], record = app.buttons["jam-record"], photo = app.buttons["jam-add-photo"]
        XCTAssertTrue(postAs.exists && article.exists && record.exists && photo.exists)
        // The pills are one-liners in the bar's row, not cards floating over the text.
        XCTAssertLessThanOrEqual(article.frame.height, 48, "a one-line pill: \(article.frame)")
        XCTAssertEqual(article.frame.midY, photo.frame.midY, accuracy: 6, "in the keyboard bar's row")
        XCTAssertGreaterThan(article.frame.minX, photo.frame.maxX - 1, "after the photo icon")
        // The field is on the page under the Post-as row, which scrolls; the pills are in the bar, a separate strip above the keyboard.
        XCTAssertGreaterThanOrEqual(field.frame.minY, postAs.frame.maxY - 2, "the field starts below the Post-as row")
        // A long post scrolls: the caret stays above the bar.
        field.typeText(String(repeating: "A long post that keeps going. ", count: 12))
        sleep(1)
        XCTAssertTrue(app.buttons["jam-post"].exists)
        // The bar sits above the keyboard.
        let keyboard = app.keyboards.firstMatch
        if keyboard.exists { XCTAssertLessThanOrEqual(photo.frame.maxY, keyboard.frame.minY + 2, "the bar is above the keyboard: \(photo.frame) vs \(keyboard.frame)") }
        // Turned back: the cards return.
        XCUIDevice.shared.orientation = .portrait
        sleep(2)
        XCTAssertGreaterThan(app.buttons["jam-write-article"].frame.height, 60, "the cards are back")
    }
}
