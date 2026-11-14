import XCTest

/// LIME-603: the Mac window, against staging, as Ada Mac. Needs the partner running as Ben (`partner --as b echo`) and the app already signed in
/// (`mac/test.sh` does the hand-over and starts the partner). Not part of any unattended run: it talks to the real staging server.
final class MacWindowTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testListBesideChatSendAndEcho() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-use-test-account"]
        app.launch()

        // The list shows "Ben Mac", read as one stop: name, last message, time (the row is one button).
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Ben Mac,'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 30), "no Ben Mac row")
        XCTAssertTrue(row.label.hasPrefix("Ben Mac, "), "the row's VoiceOver label is name, then the last message: \(row.label)")

        // Selecting it shows the chat beside the list: the list is still there, and the composer appears.
        row.tap()
        let composer = app.textViews.firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 15), "no composer")
        XCTAssertTrue(row.exists, "the list is still visible beside the chat")
        XCTAssertLessThan(row.frame.maxX, composer.frame.minX, "the list is left of the chat")

        // Send. (Return inserts a new line in the shared composer; the send button sends.)
        let words = "hello from the Mac \(Int(Date().timeIntervalSince1970) % 100000)"
        composer.tap()
        composer.typeText(words)
        let send = app.buttons["send-button"]
        XCTAssertTrue(send.waitForExistence(timeout: 5))
        send.tap()

        // The message is one VoiceOver stop with its words, and Ben's echo comes back within 60 s.
        XCTAssertTrue(app.staticTexts[words.prefix(1).uppercased() + words.dropFirst()].waitForExistence(timeout: 15) || app.staticTexts[words].waitForExistence(timeout: 1), "the sent message is not in the chat")
        let echo = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Ben here: got")).matching(NSPredicate(format: "label CONTAINS[c] %@", String(words.prefix(20)))).firstMatch
        XCTAssertTrue(echo.waitForExistence(timeout: 60), "no echo from Ben within 60 s (is `partner --as b echo` running?)")
    }
}
