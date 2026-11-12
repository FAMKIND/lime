import XCTest

/// LIME-325: the chat's Back reads "Back" with the number of other unread chats as its value (the Messages tab's count without this chat).
@MainActor
final class BackUnread325UITests: LimeUITestCase {
    func testBackValueIsTheTabCountWithoutThisChat() {
        let app = signedInApp()
        app.launch()
        XCTAssertTrue(app.buttons["conversation-row-c1"].waitForExistence(timeout: 10), "row exists")
        let tab = Int(linkBadge(app)) ?? 0   // the tab bar is hidden inside a chat: read it before
        app.buttons["conversation-row-c1"].tap()
        let back = app.buttons["back-button"]
        XCTAssertTrue(back.waitForExistence(timeout: 10), "Back exists")
        XCTAssertEqual(back.label, "Back")
        let value = back.value as? String ?? ""
        let n = Int(value.prefix { $0.isNumber }) ?? 0
        XCTAssertTrue(n == tab || n == tab - 1, "the value (\(value)) is the tab's \(tab) minus this chat if it was unread")
        XCTAssertTrue(n == 0 ? value.isEmpty : value == (n == 1 ? "1 unread chat" : "\(n) unread chats"), "spoken form: \(value)")
    }
}
