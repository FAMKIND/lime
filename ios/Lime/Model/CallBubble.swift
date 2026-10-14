import Foundation

/// A call as it shows in a chat (LIME-123). The core stores it as a local message with the id `call:<call id>` and a small JSON body.
struct CallBubble: Hashable, Sendable {
    let video: Bool
    let duration: TimeInterval
    let outcome: CallOutcome
    /// I placed the call.
    let mine: Bool
    /// A group call (LIME-112b): "<Name> started a call · Join" while it is on, then "Call ended · 23:10". `startedBy` is the starter's user id.
    let isGroup: Bool
    let live: Bool
    let startedBy: String?

    init(video: Bool, duration: TimeInterval, outcome: CallOutcome, mine: Bool, isGroup: Bool = false, live: Bool = false, startedBy: String? = nil) {
        self.video = video; self.duration = duration; self.outcome = outcome; self.mine = mine
        self.isGroup = isGroup; self.live = live; self.startedBy = startedBy
    }

    init?(body: String, mine: Bool) {
        guard let data = body.data(using: .utf8), let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = json["outcome"] as? String else { return nil }
        let isGroup = (json["group"] as? Bool) ?? false
        let live = isGroup && raw == "live"
        guard let outcome = CallOutcome(rawValue: live ? CallOutcome.completed.rawValue : raw) else { return nil }
        self.init(video: (json["video"] as? Bool) ?? false, duration: Double((json["duration_ms"] as? Int) ?? 0) / 1000, outcome: outcome, mine: mine,
                  isGroup: isGroup, live: live, startedBy: json["started_by"] as? String)
    }

    /// The title in a chat, given the name of whoever started a group call.
    func title(startedBy name: String?) -> String {
        guard isGroup else { return title }
        // Never "You": my own card reads "Call started", someone else's "<Name> started a call".
        if live { return mine ? "Call started" : "\(name ?? "Someone") started a call" }
        return "Call ended"
    }

    /// The second line in a chat: "Join" while a group call is on.
    var chatDetail: String { isGroup && live ? "Join" : detail }

    /// A missed incoming call (shown in the danger red).
    var isMissedIncoming: Bool { !isGroup && !mine && outcome.isMissed }
    var kind: String { video ? "video" : "voice" }

    /// "Voice call", "Video call", "Missed voice call".
    var title: String { isGroup ? (live ? "Group call" : "Call ended") : (isMissedIncoming ? "Missed \(kind) call" : (video ? "Video call" : "Voice call")) }

    /// The second line: the length, or what became of it.
    var detail: String {
        switch outcome {
        case .completed: CallRecord.clock(duration)
        case .missed: mine ? "Cancelled" : "Missed"
        case .missedDnd, .missedHours: mine ? "Cancelled" : (outcome.silencedNote ?? "Missed")
        case .unavailable: "Unavailable"
        case .noAnswer: "No answer"
        case .declined: "Declined"
        case .busy: "Busy"
        case .failed: "Failed"
        }
    }

    /// One line for the Messages row and a reply's quote: "Video call · 0:23", "Missed voice call", "Voice call · No answer".
    var summary: String {
        if isMissedIncoming { return title }
        if isGroup && live { return "Group call \u{00B7} Join" }
        return "\(title) \u{00B7} \(detail)"
    }

    var symbol: String {
        if isMissedIncoming { return video ? "video.slash" : "phone.arrow.down.left" }
        return video ? "video" : "phone"
    }
}
