import XCTest
@testable import Lime

final class ThreadTests: XCTestCase {
    private func summary(count: UInt32, repliers: [MemberInfo], unread: UInt32 = 0, at: Date = Date()) -> ThreadSummary {
        ThreadSummary(rootId: "root", replyCount: count, lastReplyAt: Int64(at.timeIntervalSince1970 * 1000), repliers: repliers, unread: unread)
    }

    func testTheSummaryIsOneReplyOrNReplies() {
        let me = Person(id: "u-me", name: "Me Teacher")
        let info = ThreadInfo(summary(count: 1, repliers: []), me: me)
        XCTAssertTrue(info.summaryText.hasPrefix("1 reply · "))
        XCTAssertFalse(info.summaryText.contains("Last reply"), "no \"Last reply\"")
        // Not today: the date instead of the time.
        let later = Calendar.current.date(byAdding: .day, value: 3, to: info.lastReplyAt)!
        XCTAssertEqual(info.summary(now: later), "1 reply · \(info.lastReplyAt.formatted(.dateTime.month(.abbreviated).day()))")
        XCTAssertTrue(ThreadInfo(summary(count: 3, repliers: []), me: me).summaryText.hasPrefix("3 replies · "))
        XCTAssertTrue(ThreadInfo(summary(count: 12, repliers: []), me: me).summaryText.hasPrefix("12 replies"))
    }

    func testTheCoresMeBecomesTheSignedInPersonAndOthersKeepTheirColour() {
        let me = Person(id: "my-user-id", name: "Shem Rajoon")
        let others = [
            MemberInfo(id: "me", name: "Me", initials: "M", tone: 4, label: nil),
            MemberInfo(id: "u-lee", name: "Lee Wong", initials: "LW", tone: 2, label: nil),
        ]
        let info = ThreadInfo(summary(count: 2, repliers: others, unread: 1), me: me)
        XCTAssertEqual(info.repliers.map(\.id), ["my-user-id", "u-lee"], "'me' is shown as the signed-in person")
        XCTAssertEqual(info.repliers.map(\.name), ["Shem Rajoon", "Lee Wong"])
        XCTAssertEqual(info.repliers[1].tone, 2)
        XCTAssertEqual(info.unread, 1)
        XCTAssertEqual(info.replyCount, 2)
    }

    func testTheLastReplyTimeIsTheCoresTime() {
        let when = Date(timeIntervalSince1970: 1_800_000_000)
        let info = ThreadInfo(summary(count: 1, repliers: [], at: when), me: Person(id: "m", name: "M"))
        XCTAssertEqual(info.lastReplyAt, when)
    }

    @MainActor
    func testTheDemoThreadOpensSendsAReplyAndCountsIt() async {
        let store = ConversationStore()
        store.loadDemo(screen: "thread")
        XCTAssertEqual(store.conversation("dm:rae")?.messages.first?.thread?.replyCount, 3)
        await store.openThread("t1")
        XCTAssertEqual(store.threads["t1"]?.map(\.id), ["t1", "t1a", "t1b", "t1c"], "the root, then the replies in order")
        await store.sendReply("one more", root: "t1", in: "dm:rae")
        XCTAssertEqual(store.threads["t1"]?.last?.text, "one more")
        XCTAssertEqual(store.conversation("dm:rae")?.messages.first?.thread?.replyCount, 4)
        XCTAssertEqual(store.conversation("dm:rae")?.messages.count, 2, "the reply is not in the timeline")
        await store.markThreadRead("t1", in: "dm:rae")
        XCTAssertEqual(store.conversation("dm:rae")?.messages.first?.thread?.unread, 0)
        let found = await store.search("second half")
        XCTAssertEqual(found.messages.first?.threadRoot, "t1", "a hit inside a thread names it")
        store.closeThread("t1")
        XCTAssertNil(store.threads["t1"])
    }
}
