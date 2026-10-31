import XCTest

/// LIME-206 (demo): a GIF in a chat shows the GIF mark and is read as "GIF"; with Reduce Motion it waits for a tap on Play.
@MainActor
final class GIF206UITests: LimeUITestCase {
    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    func testAGIFBubbleIsReadAsAGIFAndOpensTheViewer() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "attachments-gif"]
        app.launch()
        let bubble = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'attachment-image-' AND label == 'GIF'")).firstMatch
        XCTAssertTrue(bubble.waitForExistence(timeout: 10), "read as GIF")
        bubble.tap()
        XCTAssertTrue(any(app, "attachment-viewer").waitForExistence(timeout: 8))
        XCTAssertTrue(any(app, "attachment-save").exists, "Save to Photos is there (it keeps the GIF)")
    }
}
