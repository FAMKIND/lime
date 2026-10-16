import Foundation

/// An emergency status or its end, as a message shows it (LIME-143). The rules (what counts, the roll-up, silent alerts) are in LimeCore.
struct EmergencyCard: Hashable, Sendable {
    let sessionID: String
    /// `status` or `end`.
    let kind: String
    /// `safe` or `need_help`.
    let status: String
    let situation: String
    let students: Int
    let place: String
    let note: String
    let drill: Bool

    var isEnd: Bool { kind == "end" }
    var needsHelp: Bool { status == "need_help" }
}

extension EmergencyCard {
    init(_ info: EmergencyInfo) {
        self.init(sessionID: info.sessionId, kind: info.kind, status: info.status, situation: info.situation, students: Int(info.students),
                  place: info.place, note: info.note, drill: info.drill)
    }
}

/// The words of emergency mode, in one place (for the card, the sheet, notifications, VoiceOver and the Android copy in `docs/screens/emergency.md`).
enum EmergencyCopy {
    static let label = "EMERGENCY"
    static let drillLabel = "DRILL"

    static func label(drill: Bool) -> String { drill ? drillLabel : label }

    static func callFirst(number: String) -> String { "Call \(number) first if you can" }
    static let neverAlerts = "lime does not alert the police. Call first."

    static func statusWords(_ status: String) -> String { status == "need_help" ? "Need help" : (status == "no_response" ? "No response yet" : "Safe") }

    static func situationWords(_ situation: String) -> String {
        switch situation {
        case "hold": "Hold"
        case "secure": "Secure"
        case "lockdown": "Lockdown"
        case "evacuate": "Evacuate"
        case "shelter": "Shelter"
        default: ""
        }
    }

    static func studentsWords(_ count: Int) -> String { "\(count) student\(count == 1 ? "" : "s")" }

    /// "Safe · Lockdown · 24 students · Room 204".
    static func summary(_ card: EmergencyCard) -> String {
        var parts = [statusWords(card.status)]
        let situation = situationWords(card.situation)
        if !situation.isEmpty { parts.append(situation) }
        parts.append(studentsWords(card.students))
        if !card.place.isEmpty { parts.append(card.place) }
        return parts.joined(separator: " \u{00B7} ")
    }

    static func endedWords(by name: String, drill: Bool) -> String { drill ? "Drill ended by \(name)" : "Emergency ended by \(name)" }

    static let soundTitle = "Emergency alerts make a sound"
    static let soundWhy = "In a lockdown, a sound can reveal where people are hiding. Turn this on where loud is safer, for example natural disasters."
    static let schoolActionsTitle = "Use school safety actions"
    static let schoolActionsWhy = "Hold, Secure, Lockdown, Evacuate and Shelter, as in the Standard Response Protocol. Turn off if your school doesn\u{2019}t use them."
    static let pushNote = "Until lime can send push notifications, an alert reaches a phone when lime is open or when nearby phones wake it. Keep lime open and your phone awake and plugged in if you can. This is not a promise of delivery."
    static let keepAwake = "Keep your phone awake and plugged in if you can."
    static let noGroup = "Choose your emergency group in Settings \u{2192} Emergency."

    /// The region's number to call first (LimeCore's table).
    static func number(region: String? = Locale.current.region?.identifier) -> String { emergencyNumber(region: region ?? "US") }

    /// The words of the notification for an arriving card: the label word first (never colour alone).
    static func notification(card: EmergencyCard, senderName: String) -> (title: String, body: String) {
        if card.isEnd { return ("\(label(drill: card.drill)) \u{00B7} \(senderName)", endedWords(by: senderName, drill: card.drill)) }
        return ("\(label(drill: card.drill)) \u{00B7} \(senderName)", summary(card))
    }
}
