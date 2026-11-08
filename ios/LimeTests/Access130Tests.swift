import XCTest
@testable import Lime

/// LIME-130-1: the message actions VoiceOver gets are the long-press menu's list, and the call controls stay while VoiceOver or Switch Control runs.
final class Access130Tests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func message(own: Bool = true, text: String = "Hello", state: DeliveryState = .sent, age: TimeInterval = 60, attachments: [AttachmentItem] = [],
                         deleted: Bool = false, call: CallBubble? = nil) -> Message {
        var m = Message(id: "m1", senderID: own ? nil : "ana", text: text, date: now.addingTimeInterval(-age), state: state)
        m.attachments = attachments
        m.deleted = deleted
        m.call = call
        return m
    }

    private func plan(_ m: Message, inThread: Bool = false) -> [String] {
        MessageActionPlan.actions(for: m, inThread: inThread, now: now).map(\.title)
    }

    func testMyOwnSentTextHasEveryAction() {
        XCTAssertEqual(plan(message()), ["React", "Reply", "Forward", "Edit", "Copy", "Select", "Delete"])
    }

    func testAnotherPersonsTextHasReportAndNoEdit() {
        XCTAssertEqual(plan(message(own: false)), ["React", "Reply", "Forward", "Copy", "Select", "Report", "Delete"])
    }

    func testEditStopsAfterADay() {
        XCTAssertTrue(plan(message(age: Message.editWindow - 10)).contains("Edit"))
        XCTAssertFalse(plan(message(age: Message.editWindow + 10)).contains("Edit"))
    }

    func testInAThreadThereIsNoReply() {
        XCTAssertFalse(plan(message(), inThread: true).contains("Reply"))
        XCTAssertTrue(plan(message(), inThread: false).contains("Reply"))
    }

    func testAMessageStillGoingOrFailedHasNoReactOrReply() {
        for state in [DeliveryState.sending, .failed, .waiting, .offline] {
            let list = plan(message(state: state))
            XCTAssertFalse(list.contains("React"), "\(state)")
            XCTAssertFalse(list.contains("Reply"), "\(state)")
        }
        XCTAssertEqual(plan(message(state: .failed)), ["Forward", "Edit", "Copy", "Select", "Delete"])
    }

    func testADeletedMessageOnlyCanBeSelectedOrDeleted() {
        XCTAssertEqual(plan(message(deleted: true)), ["Select", "Delete"])
        XCTAssertEqual(plan(message(own: false, deleted: true)), ["Select", "Delete"])
    }

    func testAPhotoWithoutWordsCopiesThePictureButCannotBeEdited() {
        let photo = AttachmentItem(id: "p", mime: "image/jpeg", name: "Photo.jpg", size: 10)
        let list = plan(message(text: "", attachments: [photo]))
        XCTAssertEqual(list, ["React", "Reply", "Forward", "Copy", "Select", "Delete"])
        XCTAssertEqual(plan(message(text: "Look", attachments: [photo])), ["React", "Reply", "Forward", "Edit", "Copy", "Select", "Delete"])
    }

    func testAVoiceMessageHasNoCopyAndAGIFCanBeSaved() {
        let voice = AttachmentItem(id: "v", mime: "audio/mp4", name: "Voice message.m4a", size: 10, durationMs: 5000)
        XCTAssertFalse(plan(message(text: "", attachments: [voice])).contains("Copy"))
        let gif = AttachmentItem(id: "g", mime: "image/gif", name: "a.gif", size: 10)
        XCTAssertEqual(plan(message(own: false, text: "", attachments: [gif])), ["React", "Reply", "Forward", "Copy", "Save to my GIFs", "Select", "Report", "Delete"])
        var gone = gif
        gone.removed = true
        XCTAssertFalse(plan(message(text: "", attachments: [gone])).contains("Save to my GIFs"))
    }

    func testACallCardCanBeReactedToRepliedToAndDeletedOnly() {
        let call = CallBubble(video: true, duration: 23, outcome: .completed, mine: true)
        XCTAssertEqual(plan(message(text: "", call: call)), ["React", "Reply", "Delete"])
    }

    func testTheMenuOrderIsTheDocumentedOne() {
        let all = MessageAction.allCases.map(\.title)
        XCTAssertEqual(all, ["React", "Reply", "Forward", "Edit", "Copy", "Save to my GIFs", "Select", "Report", "Delete"])
        let gif = AttachmentItem(id: "g", mime: "image/gif", name: "a.gif", size: 10)
        let list = plan(message(own: false, text: "Fun", attachments: [gif]))
        XCTAssertEqual(list, all.filter { $0 != "Edit" })
    }

    func testCallControlsNeverHideWhileVoiceOverOrSwitchControlRuns() {
        XCTAssertTrue(CallControlsPolicy.mayAutoHide(voiceOver: false, switchControl: false))
        XCTAssertFalse(CallControlsPolicy.mayAutoHide(voiceOver: true, switchControl: false))
        XCTAssertFalse(CallControlsPolicy.mayAutoHide(voiceOver: false, switchControl: true))
        XCTAssertFalse(CallControlsPolicy.mayAutoHide(voiceOver: true, switchControl: true))
    }

    func testTheControlsAreHiddenOnlyOnAVideoCallForTouchUsersAfterTheDelay() {
        XCTAssertTrue(CallControlsPolicy.hidden(video: true, visible: false, voiceOver: false, switchControl: false))
        XCTAssertFalse(CallControlsPolicy.hidden(video: true, visible: true, voiceOver: false, switchControl: false))
        XCTAssertFalse(CallControlsPolicy.hidden(video: false, visible: false, voiceOver: false, switchControl: false))
        XCTAssertFalse(CallControlsPolicy.hidden(video: true, visible: false, voiceOver: true, switchControl: false))
        XCTAssertFalse(CallControlsPolicy.hidden(video: true, visible: false, voiceOver: false, switchControl: true))
    }

    func testTheSpokenRecordingTime() {
        XCTAssertEqual(VoiceFormat.spoken(0), "0 seconds")
        XCTAssertEqual(VoiceFormat.spoken(1), "1 second")
        XCTAssertEqual(VoiceFormat.spoken(7), "7 seconds")
        XCTAssertEqual(VoiceFormat.spoken(60), "1 minute")
        XCTAssertEqual(VoiceFormat.spoken(83), "1 minute 23 seconds")
        XCTAssertEqual(VoiceFormat.spoken(3723), "1 hour 2 minutes 3 seconds")
    }
}
