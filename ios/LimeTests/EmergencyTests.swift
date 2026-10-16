import XCTest
@testable import Lime

/// LIME-143: emergency mode on the phone: how an arriving card is announced (LimeCore's rule), the words, the card, and that it is never forwarded.
final class EmergencyTests: XCTestCase {
    private func card(status: String = "safe", kind: String = "status") -> EmergencyCard {
        EmergencyCard(sessionID: "s", kind: kind, status: status, situation: "lockdown", students: 24, place: "Room 204", note: "")
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

    func testTheNotificationSaysTheLabelWordAndTheStatus() {
        let real = NotificationPolicy.content(for: incoming(card()), preview: .hidden, sound: false)
        XCTAssertTrue(real.title.hasPrefix("EMERGENCY"), real.title)
        XCTAssertTrue(real.body.contains("Safe") && real.body.contains("24 students") && real.body.contains("Room 204"), real.body)
        XCTAssertTrue(real.breaksThroughQuiet)
        XCTAssertTrue(NotificationPolicy.content(for: incoming(card(kind: "end")), preview: .hidden, sound: false).body.hasPrefix("Emergency ended by Ms. Lee"))
    }

    func testTheCardInfoComesFromTheCoreMessage() {
        let item = MessageItem(id: "m", conversationId: "grp:g", senderId: "u", text: "Emergency: Safe", sentAt: 0, localState: "sent", attachments: [], edited: false,
                               deleted: false, reactions: [], forwarded: false, linkPreview: nil, threadRoot: nil,
                               emergency: EmergencyInfo(sessionId: "s", kind: "status", status: "need_help", situation: "", students: 3, place: "Gym", note: ""))
        let message = Message(item)
        XCTAssertEqual(message.emergency?.status, "need_help")
        XCTAssertEqual(message.emergency.map(EmergencyCopy.summary), "Need help \u{00B7} 3 students \u{00B7} Gym")
    }

    func testTheWords() {
        XCTAssertEqual(EmergencyCopy.callFirst(number: "911"), "Call 911 first if you can")
        XCTAssertEqual(EmergencyCopy.summary(card()), "Safe \u{00B7} Lockdown \u{00B7} 24 students \u{00B7} Room 204")
        XCTAssertEqual(EmergencyCopy.studentsWords(1), "1 student")
        XCTAssertEqual(EmergencyCopy.label, "EMERGENCY")
        XCTAssertEqual(EmergencyCopy.safewordsTitle, "Safewords")
        XCTAssertEqual(EmergencyCopy.number(region: "US"), "911")
        XCTAssertEqual(EmergencyCopy.number(region: "GB"), "999")
        XCTAssertEqual(EmergencyCopy.number(region: nil), "911")
        XCTAssertTrue(EmergencyCopy.soundWhy.contains("a sound can reveal where people hide"))
        XCTAssertTrue(EmergencyCopy.pushNote.contains("Not guaranteed"), "honest about background delivery")
    }
}
