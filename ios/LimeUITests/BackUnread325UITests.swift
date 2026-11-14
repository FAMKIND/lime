import XCTest

/// LIME-325: the chat's Back reads "Back" with the number of other unread chats as its value (the Messages tab's count without this chat).
@MainActor
final class BackUnread325UITests: LimeUITestCase {
    func testBackValueIsTheTabCountWithoutThisChat() {
        let app = signedInApp()
        app.launch()
        XCTAssertTrue(app.buttons["conversation-row-c1"].waitForExistence(timeout: 10), "row exists")
        // The tab bar is hidden inside a chat, so read the count before; wait until it has settled (the sample chats finish loading a moment after the list shows).
        var tab = Int(linkBadge(app)) ?? 0
        for _ in 0..<5 { sleep(1); let again = Int(linkBadge(app)) ?? 0; if again == tab { break }; tab = again }
        app.buttons["conversation-row-c1"].tap()
        let back = app.buttons["back-button"]
        XCTAssertTrue(back.waitForExistence(timeout: 10), "Back exists")
        XCTAssertEqual(back.label, "Back")
        // The value follows the unread chats live: allow it a moment to settle on the tab's count, less this chat if it was unread.
        var value = "", n = 0
        for _ in 0..<6 {
            value = back.value as? String ?? ""
            n = Int(value.prefix { $0.isNumber }) ?? 0
            if n == tab || n == tab - 1 { break }
            sleep(1)
        }
        XCTAssertTrue(n == tab || n == tab - 1, "the value (\(value)) is the tab's \(tab) minus this chat if it was unread")
        XCTAssertTrue(n == 0 ? value.isEmpty : value == (n == 1 ? "1 unread chat" : "\(n) unread chats"), "spoken form: \(value)")
    }
}
