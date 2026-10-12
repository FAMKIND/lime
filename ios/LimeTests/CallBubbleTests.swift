import XCTest
@testable import Lime

final class CallBubbleTests: XCTestCase {
    func testTitlesDetailsAndTheOneLineSummaryForEveryOutcome() {
        let done = CallBubble(video: true, duration: 23, outcome: .completed, mine: true)
        XCTAssertEqual(done.title, "Video call")
        XCTAssertEqual(done.detail, "0:23")
        XCTAssertEqual(done.summary, "Video call · 0:23")
        XCTAssertEqual(done.symbol, "video")

        let missed = CallBubble(video: false, duration: 0, outcome: .missed, mine: false)
        XCTAssertTrue(missed.isMissedIncoming)
        XCTAssertEqual(missed.title, "Missed voice call")
        XCTAssertEqual(missed.summary, "Missed voice call")
        XCTAssertEqual(missed.symbol, "phone.arrow.down.left")
        XCTAssertEqual(CallBubble(video: true, duration: 0, outcome: .missed, mine: false).symbol, "video.slash")

        // an outgoing call I ended before an answer is "Cancelled"; nobody picking up is "No answer"
        XCTAssertEqual(CallBubble(video: false, duration: 0, outcome: .missed, mine: true).detail, "Cancelled")
        XCTAssertFalse(CallBubble(video: false, duration: 0, outcome: .missed, mine: true).isMissedIncoming)
        XCTAssertEqual(CallBubble(video: false, duration: 0, outcome: .noAnswer, mine: true).summary, "Voice call · No answer")
        XCTAssertEqual(CallBubble(video: false, duration: 0, outcome: .declined, mine: true).detail, "Declined")
        XCTAssertEqual(CallBubble(video: false, duration: 0, outcome: .busy, mine: true).detail, "Busy")
        XCTAssertEqual(CallBubble(video: false, duration: 252, outcome: .completed, mine: false).summary, "Voice call · 4:12")
    }

    func testTheCoresBodyBecomesTheBubbleAndAMessageWithACallIdCarriesItsWordsAsItsText() {
        let body = #"{"video":true,"duration_ms":23000,"outcome":"completed","outgoing":true}"#
        let bubble = CallBubble(body: body, mine: true)
        XCTAssertEqual(bubble?.summary, "Video call · 0:23")
        XCTAssertNil(CallBubble(body: "not json", mine: true))
        XCTAssertNil(CallBubble(body: #"{"video":true}"#, mine: true), "an unknown outcome is not a call")
    }

    func testACallMessageCannotBeEditedOrDeletedForEveryone() {
        var message = Message(id: "call:x", senderID: nil, text: "Voice call · 0:09", date: Date(), state: .sent)
        XCTAssertTrue(message.canDeleteForEveryone(), "an ordinary message of mine can")
        message.call = CallBubble(video: false, duration: 9, outcome: .completed, mine: true)
        XCTAssertFalse(message.canDeleteForEveryone(), "a call is never sent, so it can only be deleted for me")
        XCTAssertFalse(message.canEdit())
    }

    func testSilencedAndUnavailableCallsSayWhy() {
        let dnd = CallBubble(video: false, duration: 0, outcome: .missedDnd, mine: false)
        XCTAssertEqual(dnd.title, "Missed voice call")
        XCTAssertEqual(dnd.detail, "Silenced \u{00B7} Do Not Disturb")
        XCTAssertTrue(dnd.isMissedIncoming)
        let hours = CallBubble(video: true, duration: 0, outcome: .missedHours, mine: false)
        XCTAssertEqual(hours.detail, "Silenced \u{00B7} Work hours")
        let mineUnavailable = CallBubble(video: false, duration: 0, outcome: .unavailable, mine: true)
        XCTAssertEqual(mineUnavailable.detail, "Unavailable")
        XCTAssertFalse(mineUnavailable.isMissedIncoming)
        XCTAssertEqual(mineUnavailable.summary, "Voice call \u{00B7} Unavailable")
    }
}
