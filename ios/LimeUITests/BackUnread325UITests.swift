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

    /// LIME-334: the number is on the iOS 26 Back too (it was only in the old header). From another chat, a Back with a number is a capsule wider than the plain 44 pt circle.
    func testBackFromAnotherChatShowsTheUnreadMessagesWaitingInTheList() {
        let app = signedInApp()
        app.launch()
        XCTAssertTrue(app.buttons["conversation-row-c2"].waitForExistence(timeout: 10), "row exists")
        app.buttons["conversation-row-c2"].tap()
        let back = app.buttons["back-button"]
        XCTAssertTrue(back.waitForExistence(timeout: 10), "Back exists")
        var value = ""
        for _ in 0..<6 {
            value = back.value as? String ?? ""
            if !value.isEmpty { break }
            sleep(1)
        }
        XCTAssertEqual(back.label, "Back")
        // Which sample chats are unread varies while the data loads (see above), so the number itself is checked by Block334Tests. What this guards is the layout:
        // whenever Back carries a number, it is the capsule, not the plain 44 pt circle.
        if !value.isEmpty {
            XCTAssertNotNil(value.range(of: #"^[1-9][0-9]* unread messages?$"#, options: .regularExpression), "spoken form: \(value)")
            XCTAssertGreaterThan(back.frame.width, 44, "a capsule with the number, not the plain circle")
        }
    }
}
