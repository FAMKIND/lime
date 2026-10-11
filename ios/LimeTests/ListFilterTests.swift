import XCTest
@testable import Lime

final class ListFilterTests: XCTestCase {
    private func chat(_ id: String, group: Bool = false, pinned: Bool = false, unread: Int = 0, label: String? = nil) -> Conversation {
        var person = Person(id: id, name: id.capitalized, tone: 0)
        person.label = label
        var c = Conversation(id: id, title: id.capitalized, members: group ? [person, Person(id: id + "2", name: "Other", tone: 1)] : [person], messages: [])
        c.isGroupChat = group
        c.isPinned = pinned
        c.unread = unread
        return c
    }

    private var chats: [Conversation] {
        [chat("a", pinned: true, unread: 2, label: "Grade 4"), chat("b", label: "Grade 5"), chat("g1", group: true, pinned: true), chat("g2", group: true, unread: 1), chat("c")]
    }

    func testEachFilterNarrowsTheListAndNoneShowsEverything() {
        let none = { (_: String) in false }
        XCTAssertEqual(ChatFilter().apply(chats, unreadOnly: false, isMuted: none).map(\.id), ["a", "b", "g1", "g2", "c"])
        XCTAssertEqual(ChatFilter(kind: .direct).apply(chats, unreadOnly: false, isMuted: none).map(\.id), ["a", "b", "c"])
        XCTAssertEqual(ChatFilter(kind: .group).apply(chats, unreadOnly: false, isMuted: none).map(\.id), ["g1", "g2"])
        XCTAssertEqual(ChatFilter(pinned: true).apply(chats, unreadOnly: false, isMuted: none).map(\.id), ["a", "g1"])
        XCTAssertEqual(ChatFilter(muted: true).apply(chats, unreadOnly: false, isMuted: { $0 == "b" || $0 == "g2" }).map(\.id), ["b", "g2"])
        XCTAssertEqual(ChatFilter(label: "Grade 5").apply(chats, unreadOnly: false, isMuted: none).map(\.id), ["b"])
        XCTAssertEqual(ChatFilter().apply(chats, unreadOnly: true, isMuted: none).map(\.id), ["a", "g2"], "Unread = chats with something unread")
    }

    func testFiltersCombineWithAndAndTheCountIsHowManyAreOn() {
        let none = { (_: String) in false }
        let both = ChatFilter(kind: .group, pinned: true)
        XCTAssertEqual(both.apply(chats, unreadOnly: false, isMuted: none).map(\.id), ["g1"], "Groups and Pinned: only pinned groups")
        XCTAssertEqual(both.activeCount, 2)
        XCTAssertEqual(ChatFilter(kind: .direct, pinned: true).apply(chats, unreadOnly: true, isMuted: none).map(\.id), ["a"], "with the Unread segment too")
        XCTAssertEqual(ChatFilter(kind: .direct, pinned: true, muted: true, label: "x").activeCount, 4)
        XCTAssertEqual(ChatFilter().activeCount, 0)
        XCTAssertFalse(ChatFilter().isOn)
    }

    func testLabelsInUseAreTheSortedPrivateLabelsOfDirectChats() {
        XCTAssertEqual(ChatFilter.labels(in: chats), ["Grade 4", "Grade 5"])
        XCTAssertEqual(ChatFilter.labels(in: [chat("x")]), [])
    }

    private func call(_ id: String, video: Bool, outgoing: Bool, _ outcome: CallOutcome = .completed) -> CallRecord {
        CallRecord(id: id, peerID: "p", peerName: "P", video: video, outgoing: outgoing, date: Date(), duration: 5, outcome: outcome)
    }

    func testCallFiltersVoiceVideoIncomingOutgoingAndTheMissedSegmentCombine() {
        let calls = [call("1", video: false, outgoing: false, .missed), call("2", video: true, outgoing: false), call("3", video: false, outgoing: true), call("4", video: true, outgoing: true)]
        XCTAssertEqual(CallFilter().apply(calls, missedOnly: false).map(\.id), ["1", "2", "3", "4"])
        XCTAssertEqual(CallFilter(video: true).apply(calls, missedOnly: false).map(\.id), ["2", "4"])
        XCTAssertEqual(CallFilter(video: false).apply(calls, missedOnly: false).map(\.id), ["1", "3"])
        XCTAssertEqual(CallFilter(direction: .incoming).apply(calls, missedOnly: false).map(\.id), ["1", "2"])
        XCTAssertEqual(CallFilter(video: true, direction: .incoming).apply(calls, missedOnly: false).map(\.id), ["2"])
        XCTAssertEqual(CallFilter(direction: .incoming).apply(calls, missedOnly: true).map(\.id), ["1"], "Missed still applies with a filter")
        XCTAssertEqual(CallFilter(video: true, direction: .outgoing).activeCount, 2)
    }
}
