import XCTest
@testable import Lime

/// LIME-331 (was 325): the number beside the chat's Back is the unread messages in the other accepted chats, as the Messages list's numbers add up.
final class BackUnread325Tests: XCTestCase {
    private func chat(_ id: String, unread: Int = 0, marked: Bool = false, request: Bool = false) -> Conversation {
        var c = Conversation(id: id, title: id, members: [Person(id: id, name: id)], messages: [])
        c.unread = unread
        c.markedUnread = marked
        c.isRequest = request
        return c
    }

    func testThisChatIsExcludedAndTheOthersMessagesAreAdded() {
        let all = [chat("a", unread: 2), chat("b", unread: 5), chat("c", unread: 3), chat("d")]
        XCTAssertEqual(ConversationStore.otherUnreadMessages(in: all, excluding: "a"), 8)
    }

    func testAChatMarkedUnreadCountsOne() {
        let all = [chat("a"), chat("m", marked: true), chat("n", unread: 4, marked: true)]
        XCTAssertEqual(ConversationStore.otherUnreadMessages(in: all, excluding: "a"), 5)
    }

    func testNoneUnreadIsZero() {
        XCTAssertEqual(ConversationStore.otherUnreadMessages(in: [chat("a"), chat("b")], excluding: "a"), 0)
    }

    func testRequestsAreNotCounted() {
        XCTAssertEqual(ConversationStore.otherUnreadMessages(in: [chat("a"), chat("r", unread: 3, request: true)], excluding: "a"), 0)
    }

    func testOver99ReadsNinetyNinePlus() {
        let all = [chat("a"), chat("big", unread: 120)]
        XCTAssertEqual(CountBadge.text(ConversationStore.otherUnreadMessages(in: all, excluding: "a")), "99+")
    }
}
