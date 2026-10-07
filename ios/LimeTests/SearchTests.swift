import XCTest
@testable import Lime

@MainActor
final class SearchTests: XCTestCase {
    // MARK: The word matching (also the demo's)

    func testWordsMatchByPrefixIgnoringCaseAndDiacritics() {
        XCTAssertEqual(SearchText.words("  Café, PLANNING!  "), ["cafe", "planning"])
        XCTAssertTrue(SearchText.matches("Café planning for Élodie", query: "cafe"))
        XCTAssertTrue(SearchText.matches("Café planning for Élodie", query: "ÉLO"))
        XCTAssertTrue(SearchText.matches("Café planning for Élodie", query: "plan caf"), "every word, in any order")
        XCTAssertFalse(SearchText.matches("Café planning for Élodie", query: "plan zebra"))
        XCTAssertFalse(SearchText.matches("anything", query: ""))
        XCTAssertFalse(SearchText.matches("anything", query: "!!!"))
        XCTAssertFalse(SearchText.matches("planning", query: "ning"), "a prefix, not a middle")
    }

    func testTheSnippetBoldsTheMatchedWordsAndDropsTheMarks() {
        let marked = "Please bring the \(SearchText.startMark)field\(SearchText.endMark) trip \(SearchText.startMark)forms\(SearchText.endMark)"
        XCTAssertEqual(SearchText.plain(marked), "Please bring the field trip forms")
        let attributed = SearchText.attributed(marked)
        XCTAssertEqual(String(attributed.characters), "Please bring the field trip forms")
        var boldWords: [String] = []
        for run in attributed.runs where run.inlinePresentationIntent == .stronglyEmphasized {
            boldWords.append(String(attributed[run.range].characters))
        }
        XCTAssertEqual(boldWords, ["field", "forms"])
        XCTAssertEqual(SearchText.mark("Lessons and a lesson plan", query: "less"), "\(SearchText.startMark)Lessons\(SearchText.endMark) and a \(SearchText.startMark)lesson\(SearchText.endMark) plan")
        XCTAssertEqual(String(SearchText.attributed("no marks at all").characters), "no marks at all")
    }

    // MARK: The real core through the store

    private func makeStore() throws -> (ConversationStore, LimeStore, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("lime-search-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let core = try LimeStore.open(path: directory.appendingPathComponent("lime.db").path, key: Data(repeating: 3, count: 32))
        return (ConversationStore(store: core), core, directory)
    }

    func testSearchFindsChatsByNameAndMessagesByWordThroughTheRealStore() async throws {
        let (store, core, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let zoe = try core.startDm(userId: "u-zoe", displayName: "Zoë Müller")
        let lee = try core.startDm(userId: "u-lee", displayName: "Lee Wong")
        _ = try core.sendLocalMessage(conversationId: zoe, text: "Can you cover my fractions lesson?")
        _ = try core.sendLocalMessage(conversationId: lee, text: "Fractions worksheet is in the shared folder")
        _ = try core.sendLocalMessage(conversationId: lee, text: "Thanks, see you at lunch")
        await store.reload()

        let byName = await store.search("zoe")
        XCTAssertEqual(byName.chats.map(\.title), ["Zoë Müller"], "diacritics ignored")
        XCTAssertTrue(byName.messages.isEmpty)

        let byWord = await store.search("fraction")
        XCTAssertEqual(Set(byWord.messages.map(\.conversationTitle)), ["Zoë Müller", "Lee Wong"])
        XCTAssertEqual(byWord.messages.count, 2)
        XCTAssertTrue(byWord.messages.allSatisfy { $0.marked.contains(SearchText.startMark) }, "the match is marked")
        XCTAssertTrue(byWord.chats.isEmpty)

        let none = await store.search("zebra")
        XCTAssertTrue(none.isEmpty)
        let blank = await store.search("   ")
        XCTAssertTrue(blank.isEmpty)

        // Inside one chat the matches come oldest first, for stepping.
        _ = try core.sendLocalMessage(conversationId: lee, text: "More fractions on Monday")
        await store.reload()
        let inLee = await store.findInChat("fractions", in: lee)
        XCTAssertEqual(inLee.count, 2)
        XCTAssertTrue(inLee[0].date <= inLee[1].date)
        XCTAssertTrue(inLee.allSatisfy { $0.conversationID == lee })
    }

    func testSearchWorksWithNoBackendAtAll() async throws {
        // A store that was never connected has no link, yet search works: it reads only the phone.
        let (store, core, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        XCTAssertFalse(store.isConnected)
        let chat = try core.startDm(userId: "u-1", displayName: "Sam Park")
        _ = try core.sendLocalMessage(conversationId: chat, text: "offline words")
        await store.reload()
        let found = await store.search("offline")
        XCTAssertEqual(found.messages.count, 1)
    }

    // MARK: The demo, which the UI tests drive

    func testTheDemoSearchesChatsAndMessages() async {
        let store = ConversationStore()
        store.loadDemo()
        let lee = await store.search("lee")
        XCTAssertEqual(lee.chats.map(\.id), ["dm:lee"])
        let lesson = await store.search("lesson")
        XCTAssertEqual(lesson.messages.count, 5)
        XCTAssertEqual(lesson.messages.first?.messageID, "l6", "newest first across chats")
        let inChat = await store.findInChat("lesson", in: "dm:lee")
        XCTAssertEqual(inChat.map(\.messageID), ["l1", "l2", "l3", "l5", "l6"], "oldest first inside a chat")
        let nothing = await store.search("zzz")
        XCTAssertTrue(nothing.isEmpty)
    }
}
