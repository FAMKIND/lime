import XCTest
@testable import Lime

/// LIME-325: the number beside the chat's Back is the Messages tab's count (unread chats) without this chat.
final class BackUnread325Tests: XCTestCase {
    private func chat(_ id: String, unread: Int = 0, marked: Bool = false, request: Bool = false) -> Conversation {
        var c = Conversation(id: id, title: id, members: [Person(id: id, name: id)], messages: [])
        c.unread = unread
        c.markedUnread = marked
        c.isRequest = request
        return c
    }

    func testThisChatIsExcludedAndOthersCount() {
        let all = [chat("a", unread: 2), chat("b", unread: 5), chat("c", marked: true), chat("d")]
        XCTAssertEqual(ConversationStore.otherUnreadChats(in: all, excluding: "a"), 2)
    }

    func testNoneUnreadIsZero() {
        XCTAssertEqual(ConversationStore.otherUnreadChats(in: [chat("a"), chat("b")], excluding: "a"), 0)
    }

    func testRequestsDoNotCountAsTheTabDoesNotCountThem() {
        XCTAssertEqual(ConversationStore.otherUnreadChats(in: [chat("a"), chat("r", unread: 1, request: true)], excluding: "a"), 0)
    }

    func testOver99ReadsNinetyNinePlus() {
        let all = (0..<121).map { chat("c\($0)", unread: 1) }
        XCTAssertEqual(CountBadge.text(ConversationStore.otherUnreadChats(in: all, excluding: "c0")), "99+")
    }
}
