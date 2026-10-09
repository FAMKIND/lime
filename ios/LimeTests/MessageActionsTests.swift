import XCTest
@testable import Lime

/// LIME-105: who may edit and delete for everyone, what the demo does, the list preview of a deleted message and the copy.
@MainActor
final class MessageActionsTests: XCTestCase {
    private func message(_ id: String = "m", own: Bool, age: TimeInterval, state: DeliveryState = .sent, deleted: Bool = false) -> Message {
        var m = Message(id: id, senderID: own ? nil : "x", text: "hello **there**", date: Date().addingTimeInterval(-age), state: own ? state : .received)
        m.deleted = deleted
        return m
    }

    func testEditAndDeleteForEveryoneAreOnlyForMyOwnMessagesForADay() {
        XCTAssertTrue(message(own: true, age: 60).canEdit())
        XCTAssertTrue(message(own: true, age: 23.9 * 3600).canEdit())
        XCTAssertFalse(message(own: true, age: 24.1 * 3600).canEdit(), "after 24 hours")
        XCTAssertFalse(message(own: false, age: 60).canEdit(), "someone else's")
        XCTAssertFalse(message(own: true, age: 60, deleted: true).canEdit(), "already deleted")
        XCTAssertTrue(message(own: true, age: 60).canDeleteForEveryone())
        XCTAssertFalse(message(own: true, age: 25 * 3600).canDeleteForEveryone())
        XCTAssertFalse(message(own: false, age: 60).canDeleteForEveryone())
    }

    func testADeletedMessageSaysSoInTheMessagesList() {
        let jean = Person(id: "jean", name: "Jean Park")
        let gone = message(own: false, age: 10, deleted: true)
        let chat = Conversation(id: "dm:jean", title: "Jean Park", members: [jean], messages: [gone], latest: gone)
        XCTAssertEqual(ListPreview.make(chat).plain, "This message was deleted")
    }

    func testTheDemoStoreReactsEditsAndDeletes() async throws {
        let store = ConversationStore()
        store.loadDemo()
        let chat = try XCTUnwrap(store.conversations.first { $0.id == "dm:sam" })
        let theirs = chat.messages[0], mine = chat.messages[1]
        await store.toggleReaction("👍", on: theirs, in: chat.id)
        XCTAssertEqual(store.conversation(chat.id)?.messages[0].reactions.map(\.emoji), ["👍"])
        XCTAssertEqual(store.conversation(chat.id)?.messages[0].reactions.first?.mine, true)
        await store.toggleReaction("👍", on: store.conversation(chat.id)!.messages[0], in: chat.id)
        XCTAssertTrue(store.conversation(chat.id)!.messages[0].reactions.isEmpty, "tapping my own emoji again removes it")

        let edited = await store.editMessage(mine, to: "  changed  ", in: chat.id)
        XCTAssertTrue(edited)
        let after = store.conversation(chat.id)!.messages[1]
        XCTAssertEqual([after.text, String(after.edited)], ["changed", "true"])

        await store.deleteMessages([mine.id], for: true, in: chat.id)
        let tombstone = store.conversation(chat.id)!.messages[1]
        XCTAssertTrue(tombstone.deleted)
        XCTAssertEqual(tombstone.text, "")
        await store.deleteMessages([theirs.id], for: false, in: chat.id)
        XCTAssertNil(store.conversation(chat.id)!.messages.first { $0.id == theirs.id }, "deleted for me: gone from the list")
    }

    func testCopyPutsThePlainWordsAndRichTextOnThePasteboard() {
        let store = ConversationStore()
        store.copyToPasteboard(message(own: true, age: 1))
        XCTAssertEqual(UIPasteboard.general.string, "hello there")
        XCTAssertTrue(UIPasteboard.general.contains(pasteboardTypes: ["public.rtf"]), "formatting travels as rich text")
    }
}
