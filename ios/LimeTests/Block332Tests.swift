import XCTest
@testable import Lime

/// LIME-332: a blocked person's messages and comments do not count: Back's number, a Messages row's number and a jam post's "N comments".
final class Block332Tests: XCTestCase {
    private func message(_ id: String, from sender: String?, at: TimeInterval = 0) -> Message {
        Message(id: id, senderID: sender, text: "hi", date: Date(timeIntervalSince1970: 1_800_000_000 + at), state: sender == nil ? .sent : .received)
    }

    private func group(_ id: String, _ messages: [Message], unread: Int, marked: Bool = false) -> Conversation {
        var c = Conversation(id: id, title: id, members: [Person(id: "lee", name: "Lee"), Person(id: "sam", name: "Sam")], messages: messages)
        c.isGroupChat = true
        c.unread = unread
        c.markedUnread = marked
        return c
    }

    func testBacksNumberSkipsABlockedSendersUnreadMessagesInAnotherChatAndTheyCountAgainAfterUnblock() {
        let here = group("here", [], unread: 0)
        let other = group("other", [message("1", from: "lee"), message("2", from: "lee", at: 1)], unread: 2)
        XCTAssertEqual(ConversationStore.otherUnreadMessages(in: [here, other], excluding: "here", blocked: ["lee"]), 0, "both are Lee's")
        XCTAssertEqual(ConversationStore.otherUnreadMessages(in: [here, other], excluding: "here", blocked: []), 2, "Unblock: they count again")
    }

    func testAMixInOneGroupCountsOnlyTheOthers() {
        let mixed = group("g", [message("1", from: "lee"), message("2", from: "sam", at: 1), message("3", from: "lee", at: 2), message("4", from: "sam", at: 3)], unread: 4)
        XCTAssertEqual(BlockedPeople.unreadMessages(mixed, blocked: ["lee"]), 2, "Sam's two")
        XCTAssertEqual(BlockedPeople.unreadMessages(mixed, blocked: []), 4)
        let older = group("g", [message("0", from: "lee"), message("1", from: "sam", at: 1), message("2", from: "lee", at: 2)], unread: 2)
        XCTAssertEqual(BlockedPeople.unreadMessages(older, blocked: ["lee"]), 1, "only the newest two are unread: Sam's and Lee's; Lee's is skipped")
    }

    func testAChatMarkedUnreadByHandStillAddsOne() {
        let marked = group("g", [message("1", from: "lee")], unread: 0, marked: true)
        XCTAssertEqual(BlockedPeople.unreadMessages(marked, blocked: ["lee"]), 1)
        let markedAndBlocked = group("g", [message("1", from: "lee")], unread: 1, marked: true)
        XCTAssertEqual(BlockedPeople.unreadMessages(markedAndBlocked, blocked: ["lee"]), 1, "Lee's one is skipped, the hand mark still counts 1")
        XCTAssertEqual(ConversationStore.otherUnreadMessages(in: [markedAndBlocked], excluding: "x", blocked: ["lee"]), 1)
    }

    func testRepliesOutsideTheTimelineAreKeptAndAOneToOneChatIsNeverFiltered() {
        let replies = group("g", [message("1", from: "lee")], unread: 3)   // one message in the timeline, two more unread (replies)
        XCTAssertEqual(BlockedPeople.unreadMessages(replies, blocked: ["lee"]), 2, "the two that are not in the timeline cannot be told apart: kept")
        var dm = Conversation(id: "dm:lee", title: "Lee", members: [Person(id: "lee", name: "Lee")], messages: [message("1", from: "lee")])
        dm.unread = 1
        XCTAssertEqual(BlockedPeople.unreadMessages(dm, blocked: ["lee"]), 1, "a blocked one-to-one is hidden by core; nothing to filter here")
    }

    func testACommentCountDropsOnlyTheBlockedCommenter() {
        func comment(_ id: String, _ author: String, state: String = "published") -> JamCommentInfo {
            JamCommentInfo(commentId: id, postId: "p", parentId: nil, author: author, text: "x", created: 1, state: state, mine: false)
        }
        let list = [comment("1", "lee"), comment("2", "sam"), comment("3", "lee"), comment("4", "lee", state: "pending")]
        XCTAssertEqual(BlockedPeople.visibleCommentCount(total: 3, comments: list, blocked: ["lee"]), 1, "Lee's two published comments are not counted; his pending one never was")
        XCTAssertEqual(BlockedPeople.visibleCommentCount(total: 3, comments: list, blocked: []), 3, "Unblock: counted again")
        XCTAssertEqual(BlockedPeople.visibleCommentCount(total: 0, comments: [], blocked: ["lee"]), 0)
    }
}
