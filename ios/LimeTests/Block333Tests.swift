import XCTest
@testable import Lime

/// LIME-333: a blocked person's last traces: unread replies, a thread's reply text, a post's hearts and faces, the "New comments" dot and the Activity list.
final class Block333Tests: XCTestCase {
    private func message(_ id: String, from sender: String?, at: TimeInterval = 0) -> Message {
        Message(id: id, senderID: sender, text: "hi", date: Date(timeIntervalSince1970: 1_800_000_000 + at), state: sender == nil ? .sent : .received)
    }

    private func groupWithUnreadReplies(timeline: [Message], unread: Int, thread: ThreadInfo) -> Conversation {
        var root = message("root", from: "sam", at: -10)
        root.thread = thread
        var c = Conversation(id: "g", title: "g", members: [Person(id: "lee", name: "Lee"), Person(id: "sam", name: "Sam")], messages: [root] + timeline)
        c.isGroupChat = true
        c.unread = unread
        return c
    }

    private func thread(unread: Int, senders: [String]) -> ThreadInfo {
        ThreadInfo(replyCount: 3, lastReplyAt: Date(), repliers: [], unread: unread, unreadSenders: senders)
    }

    func testUnreadRepliesFromABlockedPersonDoNotCountAndComeBackAfterUnblock() {
        // Sam's message in the timeline plus three unread replies in a thread: two from Lee, one from Sam.
        let c = groupWithUnreadReplies(timeline: [message("1", from: "sam", at: 1)], unread: 4, thread: thread(unread: 3, senders: ["lee", "sam", "lee"]))
        XCTAssertEqual(BlockedPeople.unreadMessages(c, blocked: ["lee"]), 2, "Sam's message and Sam's reply")
        XCTAssertEqual(BlockedPeople.unreadMessages(c, blocked: []), 4, "Unblock: all four")
        XCTAssertTrue(BlockedPeople.countsAsUnread(c, blocked: ["lee"]))
    }

    func testAChatWhoseOnlyUnreadThingsAreABlockedPersonsRepliesIsNotUnread() {
        let c = groupWithUnreadReplies(timeline: [], unread: 2, thread: thread(unread: 2, senders: ["lee", "lee"]))
        XCTAssertEqual(BlockedPeople.unreadMessages(c, blocked: ["lee"]), 0)
        XCTAssertFalse(BlockedPeople.countsAsUnread(c, blocked: ["lee"]), "no badge for it")
        XCTAssertTrue(BlockedPeople.countsAsUnread(c, blocked: []))
    }

    func testAThreadsVisibleUnreadSkipsTheBlockedRepliers() {
        let t = thread(unread: 3, senders: ["lee", "sam", "lee"])
        XCTAssertEqual(t.visibleUnread(blocked: ["lee"]), 1)
        XCTAssertEqual(t.visibleUnread(blocked: []), 3)
        XCTAssertEqual(t.unread, 3, "core's number stays: reading the thread takes all of it off the chat's number")
    }

    func testAPostsHeartsFacesCommentsAndDotSkipTheBlockedAndComeBack() {
        func comment(_ id: String, _ author: String) -> JamCommentInfo {
            JamCommentInfo(commentId: id, postId: "p", parentId: nil, author: author, text: "x", created: 1, state: "published", mine: false)
        }
        let counts = JamCountsInfo(postId: "p", likes: 3, comments: 2, remixes: 0, likers: ["lee", "sam", "kim"], likedByMe: false, unseen: true)
        let onlyLee = BlockedPeople.visibleCounts(counts, comments: [comment("1", "lee"), comment("2", "lee")], blocked: ["lee"], me: "me")
        XCTAssertEqual(onlyLee.likes, 2)
        XCTAssertEqual(onlyLee.likers, ["sam", "kim"], "Lee's face is gone")
        XCTAssertEqual(onlyLee.comments, 0)
        XCTAssertFalse(onlyLee.unseen, "the only new comments are Lee's: no dot")
        let mixed = BlockedPeople.visibleCounts(counts, comments: [comment("1", "lee"), comment("2", "sam")], blocked: ["lee"], me: "me")
        XCTAssertTrue(mixed.unseen, "Sam's comment keeps the dot")
        XCTAssertEqual(mixed.comments, 1)
        let back = BlockedPeople.visibleCounts(counts, comments: [comment("1", "lee"), comment("2", "lee")], blocked: [], me: "me")
        XCTAssertEqual(back, counts, "Unblock: all of it shows")
    }

    @MainActor
    func testActivityLeavesOutABlockedPersonsWordsAndHeartsAndTheyReturnOnUnblock() async {
        let store = ConversationStore()
        store.loadDemo(screen: "jam-mine")
        guard let post = store.jamPosts["demo-my-jam"]?.last else { return XCTFail("the demo has a post of mine") }
        store.demoEngagement.comments[post.postId] = [JamCommentInfo(commentId: "c1", postId: post.postId, parentId: nil, author: "sam", text: "Great circle", created: 5, state: "published", mine: false)]
        store.demoEngagement.likers[post.postId] = ["sam"]
        store.demoEngagement.unseen.insert(post.postId)
        XCTAssertTrue(store.jamActivity().contains { $0.who == "sam" && $0.kind == .commentedOnMine }, "before: Sam's comment is in my Activity")
        XCTAssertEqual(store.jamCounts(post.postId).likes, 1)
        XCTAssertTrue(store.jamHasUnseen())
        await store.blockPerson("sam", name: "Sam")
        XCTAssertFalse(store.jamActivity().contains { $0.who == "sam" }, "blocked: no line from Sam, not even collapsed")
        XCTAssertFalse(store.jamActivity(of: "sam").contains { $0.who == "sam" }, "nor on Sam's own profile")
        XCTAssertEqual(store.jamCounts(post.postId).likes, 0)
        XCTAssertEqual(store.jamCounts(post.postId).comments, 0)
        XCTAssertFalse(store.jamHasUnseen(), "no dot")
        await store.unblock("dm:sam")
        XCTAssertTrue(store.jamActivity().contains { $0.who == "sam" && $0.kind == .commentedOnMine }, "Unblock: back")
        XCTAssertTrue(store.jamHasUnseen())
    }
}
