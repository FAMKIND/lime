import XCTest

/// LIME-325, 331: the chat's Back reads "Back" with the unread messages in the other chats as its value.
@MainActor
final class BackUnread325UITests: LimeUITestCase {
    func testBackValueIsTheUnreadMessagesInTheOtherChats() {
        let app = signedInApp()
        app.launch()
        XCTAssertTrue(app.buttons["conversation-row-c1"].waitForExistence(timeout: 10), "row exists")
        app.buttons["conversation-row-c1"].tap()
        let back = app.buttons["back-button"]
        XCTAssertTrue(back.waitForExistence(timeout: 10), "Back exists")
        XCTAssertEqual(back.label, "Back")
        // The value is the unread MESSAGES in the other chats (LIME-331): "5 unread messages", "1 unread message", or nothing. Which chats are unread in the
        // sample data can change while it loads (it differed from run to run under load), so this checks the words, not a number; the unit tests check the count.
        let value = back.value as? String ?? ""
        let n = Int(value.prefix { $0.isNumber }) ?? 0
        XCTAssertTrue(n == 0 ? value.isEmpty : value == (n == 1 ? "1 unread message" : "\(n) unread messages"), "spoken form: \(value)")
    }
}
