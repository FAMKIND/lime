import XCTest
@testable import Lime

/// LIME-278: which message ends a run (where its time shows).
final class ChatRuns278Tests: XCTestCase {
    private func conversation(_ messages: [Message]) -> Conversation {
        Conversation(id: "dm:sam", title: "Sam", members: [Person(id: "sam", name: "Sam Park")], messages: messages)
    }

    private func ends(_ messages: [Message]) -> [String: Bool] {
        var out: [String: Bool] = [:]
        for row in ChatRow.rows(for: conversation(messages)) { if case .message(let m, _) = row.kind { out[m.id] = row.endsRun } }
        return out
    }

    func testOnlyTheLastOfAnUnbrokenRunFromOnePersonEndsIt() {
        let t = Date(timeIntervalSince1970: 1_800_000_000)
        let result = ends([
            Message(id: "a", senderID: "sam", text: "hi", date: t),
            Message(id: "b", senderID: "sam", text: "Hi", date: t.addingTimeInterval(30)),
            Message(id: "c", senderID: "sam", text: "yo", date: t.addingTimeInterval(90)),
            Message(id: "d", senderID: nil, text: "hey", date: t.addingTimeInterval(120), state: .sent),
            Message(id: "e", senderID: nil, text: "ok", date: t.addingTimeInterval(130), state: .sent),
        ])
        XCTAssertEqual(result, ["a": false, "b": false, "c": true, "d": false, "e": true])
    }

    func testAGapOfFiveMinutesAnotherSenderOrANewDayStartsANewRun() {
        let t = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000)).addingTimeInterval(10 * 3600)
        let result = ends([
            Message(id: "a", senderID: "sam", text: "one", date: t),
            Message(id: "b", senderID: "sam", text: "two", date: t.addingTimeInterval(ChatRow.runGap + 1)),
            Message(id: "c", senderID: "sam", text: "three", date: t.addingTimeInterval(ChatRow.runGap + 60)),
            Message(id: "d", senderID: "sam", text: "next day", date: t.addingTimeInterval(86_400)),
        ])
        XCTAssertEqual(result, ["a": true, "b": false, "c": true, "d": true])
    }
}
