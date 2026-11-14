import XCTest
@testable import Lime

/// LIME-330: what a blocked person looks like (collapsed rows, reactions, the menu, the badge), by core's rules.
final class Block330Tests: XCTestCase {
    private func message(_ id: String, from sender: String?, at: TimeInterval = 0, _ text: String = "hi") -> Message {
        Message(id: id, senderID: sender, text: text, date: Date(timeIntervalSince1970: 1_800_000_000 + at), state: sender == nil ? .sent : .received)
    }

    private func group(_ messages: [Message], unread: Int = 0, marked: Bool = false) -> Conversation {
        var c = Conversation(id: "grp:x", title: "Team", members: [Person(id: "lee", name: "Lee"), Person(id: "sam", name: "Sam")], messages: messages)
        c.isGroupChat = true
        c.unread = unread
        c.markedUnread = marked
        return c
    }

    private func shape(_ rows: [ChatRow]) -> [String] {
        rows.map { row in
            switch row.kind {
            case .day: "day"
            case .message(let m, _): m.id
            case .system: "system"
            case .deletedRun(let n): "deleted\(n)"
            case .blockedRun(let ms): "blocked\(ms.count)"
            }
        }
    }

    func testBlockedMessagesFoldIntoOneRowPerRunInAGroupAndShowOpensThem() {
        let c = group([message("1", from: "lee"), message("2", from: "lee", at: 10), message("3", from: "sam", at: 20), message("4", from: "lee", at: 30), message("5", from: nil, at: 40)])
        XCTAssertEqual(shape(ChatRow.rows(for: c, blocked: ["lee"])), ["day", "blocked2", "3", "blocked1", "5"])
        XCTAssertEqual(shape(ChatRow.rows(for: c, blocked: ["lee"], revealed: ["1", "2"])), ["day", "1", "2", "3", "blocked1", "5"], "Show opens the ones it was given")
        XCTAssertEqual(shape(ChatRow.rows(for: c, blocked: [])), ["day", "1", "2", "3", "4", "5"], "nobody blocked: nothing folds")
    }

    func testAOneToOneChatNeverFoldsAndMyOwnMessagesNeverDo() {
        var dm = Conversation(id: "dm:lee", title: "Lee", members: [Person(id: "lee", name: "Lee")], messages: [message("1", from: "lee")])
        dm.isGroupChat = false
        XCTAssertEqual(shape(ChatRow.rows(for: dm, blocked: ["lee"])), ["day", "1"])
        XCTAssertEqual(shape(ChatRow.rows(for: group([message("1", from: nil)]), blocked: ["lee"])), ["day", "1"])
    }

    func testTheWordsOfACollapsedRow() {
        XCTAssertEqual(BlockedPeople.collapsedWords(count: 1), "Message from someone you blocked")
        XCTAssertEqual(BlockedPeople.collapsedWords(count: 3), "3 messages from someone you blocked")
        XCTAssertEqual(BlockedPeople.quoteWords, "a blocked person\u{2019}s message")
    }

    func testBlockedReactorsLeaveTheChipsAndTheCount() {
        let chips = [ReactionChip(emoji: "👍", count: 3, mine: true, people: ["You", "Lee", "Sam"], personIDs: ["me", "lee", "sam"]),
                     ReactionChip(emoji: "🎉", count: 1, mine: false, people: ["Lee"], personIDs: ["lee"]),
                     ReactionChip(emoji: "❤️", count: 1, mine: false, people: ["Pat"], personIDs: [])]
        let shown = BlockedPeople.visible(chips, blocked: ["lee"])
        XCTAssertEqual(shown.map(\.emoji), ["👍", "❤️"], "the emoji only Lee used is gone")
        XCTAssertEqual(shown[0].count, 2)
        XCTAssertEqual(shown[0].people, ["You", "Sam"])
        XCTAssertEqual(shown[1].count, 1, "a chip with no ids is kept as it is")
        XCTAssertEqual(BlockedPeople.visible(chips, blocked: []).count, 3)
    }

    func testTheMenuOffersBlockOnlyForAGroupMessageFromSomeoneElse() {
        let theirs = message("1", from: "lee")
        XCTAssertFalse(MessageActionPlan.actions(for: theirs, inThread: false).contains(.block), "not unless the caller says it can")
        XCTAssertTrue(MessageActionPlan.actions(for: theirs, inThread: false, canBlock: true).contains(.block))
        let list = MessageActionPlan.actions(for: theirs, inThread: false, canBlock: true)
        XCTAssertEqual(list.firstIndex(of: .block), list.firstIndex(of: .report).map { $0 + 1 }, "right after Report")
        XCTAssertFalse(MessageActionPlan.actions(for: message("2", from: nil), inThread: false, canBlock: true).contains(.block), "never on my own message")
        XCTAssertEqual(AppMessageAction.block.title(blockName: "Lee Wong"), "Block Lee Wong")
        XCTAssertEqual(AppMessageAction.report.title(blockName: "Lee Wong"), "Report")
    }

    func testAGroupWhoseUnreadMessagesAreAllFromBlockedPeopleDoesNotCountForTheBadge() {
        let all = group([message("1", from: "sam"), message("2", from: "lee", at: 1), message("3", from: "lee", at: 2)], unread: 2)
        XCTAssertFalse(BlockedPeople.countsAsUnread(all, blocked: ["lee"]), "the two unread are Lee's")
        XCTAssertTrue(BlockedPeople.countsAsUnread(all, blocked: []))
        let mixed = group([message("1", from: "lee"), message("2", from: "sam", at: 1), message("3", from: "lee", at: 2)], unread: 2)
        XCTAssertTrue(BlockedPeople.countsAsUnread(mixed, blocked: ["lee"]), "Sam's message is among the unread")
        let marked = group([message("1", from: "lee")], unread: 1, marked: true)
        XCTAssertTrue(BlockedPeople.countsAsUnread(marked, blocked: ["lee"]), "marked unread by hand still counts")
        XCTAssertFalse(BlockedPeople.countsAsUnread(group([message("1", from: "lee")], unread: 0), blocked: ["lee"]), "read stays read")
    }

    func testAGroupRowsPreviewDoesNotNameOrQuoteABlockedPerson() {
        let c = group([message("1", from: "sam"), message("2", from: "lee", at: 1, "secret words")])
        XCTAssertEqual(ListPreview.make(c, blocked: ["lee"]).plain, "Message from someone you blocked")
        XCTAssertEqual(ListPreview.make(c, blocked: []).plain, "Lee: secret words")
    }
}
