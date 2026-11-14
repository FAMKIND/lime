import XCTest
@testable import Lime

/// LIME-334: Back's number from the shape of the 13 mini's Messages list: three chats with a green 1 whose newest things are a call, a video call and a rename
/// (system and call rows), and a pinned one-to-one opened from the list. (The number itself was missing from the iOS 26 Back: `BackUnread325UITests` has that.)
final class Block334Tests: XCTestCase {
    private func row(_ id: String, _ text: String, from sender: String?, system: Bool = false, at: TimeInterval = 0) -> Message {
        Message(id: id, senderID: sender, text: text, date: Date(timeIntervalSince1970: 1_800_000_000 + at), state: system ? .system : (sender == nil ? .sent : .received))
    }

    private func group(_ id: String, _ messages: [Message], unread: Int) -> Conversation {
        var c = Conversation(id: id, title: id, members: [Person(id: "a", name: "A"), Person(id: "b", name: "B")], messages: messages)
        c.isGroupChat = true
        c.unread = unread
        return c
    }

    func testThreeUnreadChatsWhoseNewestRowsAreCallsAndARenameAddUpToThreeFromAPinnedOneToOne() {
        let jean = group("shem-fam", [row("1", "Call ended · 0:14", from: "a")], unread: 1)
        let fam = group("fam", [row("2", "Video call · 0:47", from: "b")], unread: 1)
        let org = group("lime-org", [row("3", "You renamed the group", from: nil, system: true)], unread: 1)
        var pinned = Conversation(id: "dm:jean", title: "Jean Chung", members: [Person(id: "jean", name: "Jean Chung")], messages: [row("4", "hello", from: "jean")])
        pinned.isPinned = true
        let all = [pinned, jean, fam, org]
        for blocked in [Set<String>(), ["someone-else"]] {
            XCTAssertEqual(all.dropFirst().map { BlockedPeople.unreadMessages($0, blocked: blocked) }, [1, 1, 1], "each row's green 1")
            XCTAssertEqual(ConversationStore.otherUnreadMessages(in: all, excluding: "dm:jean", blocked: blocked), 3, "Back shows ‹ 3")
        }
    }
}
