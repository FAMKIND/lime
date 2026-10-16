import XCTest
@testable import Lime

/// LIME-143: emergency mode on the phone: how an arriving card is announced (LimeCore's rule), the words, the card, and that it is never forwarded.
final class EmergencyTests: XCTestCase {
    private func card(drill: Bool = false, status: String = "safe", kind: String = "status") -> EmergencyCard {
        EmergencyCard(sessionID: "s", kind: kind, status: status, situation: "lockdown", students: 24, place: "Room 204", note: "", drill: drill)
    }

    private func incoming(_ card: EmergencyCard) -> IncomingMessage {
        IncomingMessage(id: "m", conversationID: "grp:g", conversationTitle: "Staff", senderID: "u", senderName: "Ms. Lee", text: "x", threadRoot: nil, isGroup: true,
                        isRequest: false, date: Date(), emergency: card)
    }

    private func how(_ card: EmergencyCard, sound: Bool = false, quiet: Bool = true, muted: Bool = true, active: Bool = false) -> Presentation {
        NotificationPolicy.presentation(for: incoming(card), enabled: true, muted: muted, sound: .limeChime, appActive: active, viewing: nil, quiet: quiet, emergencySound: sound)
    }

    func testARealEmergencyShowsEvenWhenQuietAndMutedAndIsSilentByDefault() {
        XCTAssertEqual(how(card()), .local(sound: false), "silent: no sound (and so no vibration), even in quiet hours and a muted chat")
        XCTAssertEqual(how(card(), active: true), .banner(sound: false))
    }

    func testTheSoundSettingMakesARealEmergencyLoud() {
        XCTAssertEqual(how(card(), sound: true), .local(sound: true))
        XCTAssertEqual(how(card(), sound: true, active: true), .banner(sound: true))
    }

    func testADrillNeverBreaksThroughQuietOrMutedAndIsNeverLoud() {
        XCTAssertEqual(how(card(drill: true), sound: true), .none, "muted")
        XCTAssertEqual(how(card(drill: true), sound: true, muted: false), .held, "quiet")
        XCTAssertEqual(how(card(drill: true), sound: true, quiet: false, muted: false), .local(sound: false), "silent even with the sound setting on")
    }

    func testTheNotificationSaysTheLabelWordAndTheStatus() {
        let real = NotificationPolicy.content(for: incoming(card()), preview: .hidden, sound: false)
        XCTAssertTrue(real.title.hasPrefix("EMERGENCY"), real.title)
        XCTAssertTrue(real.body.contains("Safe") && real.body.contains("24 students") && real.body.contains("Room 204"), real.body)
        XCTAssertTrue(real.breaksThroughQuiet)
        let drill = NotificationPolicy.content(for: incoming(card(drill: true)), preview: .hidden, sound: false)
        XCTAssertTrue(drill.title.hasPrefix("DRILL"), drill.title)
        XCTAssertFalse(drill.breaksThroughQuiet, "a drill never breaks through Do Not Disturb")
        XCTAssertTrue(NotificationPolicy.content(for: incoming(card(kind: "end")), preview: .hidden, sound: false).body.hasPrefix("Emergency ended by Ms. Lee"))
    }

    func testTheCardInfoComesFromTheCoreMessage() {
        let item = MessageItem(id: "m", conversationId: "grp:g", senderId: "u", text: "Emergency: Safe", sentAt: 0, localState: "sent", attachments: [], edited: false,
                               deleted: false, reactions: [], forwarded: false, linkPreview: nil, threadRoot: nil,
                               emergency: EmergencyInfo(sessionId: "s", kind: "status", status: "need_help", situation: "", students: 3, place: "Gym", note: "", drill: false))
        let message = Message(item)
        XCTAssertEqual(message.emergency?.status, "need_help")
        XCTAssertEqual(message.emergency.map(EmergencyCopy.summary), "Need help \u{00B7} 3 students \u{00B7} Gym")
    }

    func testTheWords() {
        XCTAssertEqual(EmergencyCopy.callFirst(number: "911"), "Call 911 first if you can")
        XCTAssertEqual(EmergencyCopy.summary(card()), "Safe \u{00B7} Lockdown \u{00B7} 24 students \u{00B7} Room 204")
        XCTAssertEqual(EmergencyCopy.studentsWords(1), "1 student")
        XCTAssertEqual(EmergencyCopy.label(drill: true), "DRILL")
        XCTAssertEqual(EmergencyCopy.number(region: "US"), "911")
        XCTAssertEqual(EmergencyCopy.number(region: "GB"), "999")
        XCTAssertEqual(EmergencyCopy.number(region: nil), "911")
        XCTAssertTrue(EmergencyCopy.soundWhy.contains("reveal where people are hiding"))
        XCTAssertTrue(EmergencyCopy.pushNote.contains("not a promise"), "honest about background delivery")
    }
}
