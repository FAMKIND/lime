import XCTest
@testable import Lime

/// LIME-104: what a Messages row says (replies, attachments), unread and the demo actions for pin, unread, delete and labels.
@MainActor
final class QARoundTests: XCTestCase {
    private func message(_ id: String, from: String?, _ text: String = "", attachments: [AttachmentItem] = []) -> Message {
        var m = Message(id: id, senderID: from, text: text, date: Date())
        m.attachments = attachments
        return m
    }

    private func chat(group: Bool = false, last: Message, reply: Bool = false) -> Conversation {
        let jean = Person(id: "jean", name: "Jean Park"), lee = Person(id: "lee", name: "Lee Wong")
        return Conversation(id: group ? "grp:1" : "dm:jean", title: group ? "Team" : "Jean Park", members: group ? [jean, lee] : [jean], messages: [last],
                            isGroupChat: group, latest: last, latestIsReply: reply)
    }

    func testAReplyIsShownAsAQuoteOfWhatItAnswersThenTheReplyWithNoArrow() {
        func reply(_ from: String?, _ text: String, root: Message, group: Bool = false) -> ListPreview {
            var last = message("2", from: from, text)
            last.threadRoot = root.id
            let jean = Person(id: "jean", name: "Jean Park"), lee = Person(id: "lee", name: "Lee Wong")
            let c = Conversation(id: group ? "grp:1" : "dm:jean", title: group ? "Team" : "Jean Park", members: group ? [jean, lee] : [jean], messages: [root],
                                 isGroupChat: group, latest: last, latestIsReply: true)
            return ListPreview.make(c)
        }
        let root = message("r", from: "jean", "Who can cover recess duty on Thursday?")
        let one = reply("jean", "sounds good", root: root)
        XCTAssertEqual(one.quote, "Reply to Jean · Who can cover recess duty on Thursday?")
        XCTAssertEqual(one.plain, "Reply to Jean · Who can cover recess duty on Thursday?\nsounds good", "in a chat, just the reply text")
        XCTAssertFalse(one.plain.contains("↩"), "no arrow")
        XCTAssertEqual(reply(nil, "on it", root: root).plain, "Reply to Jean · Who can cover recess duty on Thursday?\nYou: on it")
        XCTAssertEqual(reply("lee", "see you", root: root, group: true).plain, "Reply to Jean · Who can cover recess duty on Thursday?\nLee: see you")
        // A root that is mine, or a picture, reads naturally; one not loaded still says it is a reply.
        XCTAssertEqual(reply("jean", "ok", root: message("m", from: nil, "my plan")).quote, "Reply to You · my plan")
        XCTAssertEqual(reply("jean", "ok", root: message("p", from: "jean", attachments: [AttachmentItem(id: "p", mime: "image/jpeg", name: "p.jpg", size: 1)])).quote, "Reply to Jean · Photo")
        var stray = message("2", from: "jean", "hi"); stray.threadRoot = "missing"
        XCTAssertEqual(ListPreview.make(chat(last: stray, reply: true)).quote, "Reply in a thread")
        // Not a reply: plain in a chat, "Name: " in a group.
        XCTAssertEqual(ListPreview.make(chat(last: message("1", from: "jean", "hello"))).plain, "hello")
        XCTAssertEqual(ListPreview.make(chat(group: true, last: message("1", from: "lee", "hello"))).plain, "Lee: hello")
    }

    func testAttachmentsShowASymbolALabelAndTheCaption() {
        func photo() -> AttachmentItem { AttachmentItem(id: UUID().uuidString, mime: "image/jpeg", name: "p.jpg", size: 1) }
        let one = ListPreview.make(chat(last: message("1", from: "jean", attachments: [photo()])))
        XCTAssertEqual([one.symbol, one.text], ["camera.fill", "Photo"])
        let three = ListPreview.make(chat(last: message("1", from: "jean", "Field trip", attachments: [photo(), photo(), photo()])))
        XCTAssertEqual([three.symbol, three.text], ["camera.fill", "3 Photos · Field trip"], "the caption follows")
        let video = ListPreview.make(chat(last: message("1", from: "jean", attachments: [AttachmentItem(id: "v", mime: "video/mp4", name: "v.mp4", size: 1, durationMs: 31_000)])))
        XCTAssertEqual([video.symbol, video.text], ["video.fill", "Video"])
        let voice = ListPreview.make(chat(last: message("1", from: "jean", attachments: [AttachmentItem(id: "a", mime: "audio/mp4", name: "a.m4a", size: 1, durationMs: 12_000)])))
        XCTAssertEqual([voice.symbol, voice.text], ["mic.fill", "Voice message (0:12)"])
        let file = ListPreview.make(chat(last: message("1", from: "jean", attachments: [AttachmentItem(id: "f", mime: "application/pdf", name: "Report.pdf", size: 1)])))
        XCTAssertEqual([file.symbol, file.text], ["doc.fill", "Report.pdf"])
        let reply = ListPreview.make(chat(last: message("1", from: "jean", attachments: [photo()]), reply: true))
        XCTAssertEqual(reply.text, "Photo")
    }

    func testTheNewestThingIsTheLastMessageAndTheDotShowsForAHandMarkedChat() {
        var c = chat(last: message("old", from: "jean", "old"))
        XCTAssertEqual(c.lastMessage?.id, "old")
        c.latest = message("newer", from: "jean", "reply")
        XCTAssertEqual(c.lastMessage?.id, "newer", "a newer reply is what the row shows")
        XCTAssertFalse(c.isUnread)
        c.markedUnread = true
        XCTAssertTrue(c.isUnread)
        c.markedUnread = false
        c.unread = 2
        XCTAssertTrue(c.isUnread)
    }

    func testPinMarkUnreadDeleteAndLabelInTheDemoStore() async {
        let store = ConversationStore()
        store.loadDemo()
        let ids = store.conversations.map(\.id)
        XCTAssertGreaterThanOrEqual(ids.count, 3)
        let last = ids[ids.count - 1]
        await store.setPinned(last, true)
        XCTAssertEqual(store.conversations.first?.id, last, "pinned goes to the top")
        XCTAssertTrue(store.conversations.first?.isPinned ?? false)
        await store.setPinned(last, false)
        XCTAssertFalse(store.conversation(last)?.isPinned ?? true)

        await store.setMarkedUnread(ids[0], true)
        XCTAssertTrue(store.conversation(ids[0])?.markedUnread ?? false)
        await store.setMarkedUnread(ids[0], false)
        XCTAssertFalse(store.conversation(ids[0])?.isUnread ?? true)

        let person = store.conversations.first(where: { !$0.isGroup && !$0.members.isEmpty })!.members[0]
        await store.setLabel("  Grade 4 · Lincoln ", for: person.id)
        XCTAssertEqual(store.conversations.flatMap(\.members).first { $0.id == person.id }?.label, "Grade 4 · Lincoln".prefix(30).description)
        await store.setLabel("", for: person.id)
        XCTAssertNil(store.conversations.flatMap(\.members).first { $0.id == person.id }?.label)

        await store.deleteChat(ids[1])
        XCTAssertNil(store.conversation(ids[1]))
    }
}
