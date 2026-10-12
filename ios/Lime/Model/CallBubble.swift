import Foundation

/// A call as it shows in a chat (LIME-123). The core stores it as a local message with the id `call:<call id>` and a small JSON body.
struct CallBubble: Hashable, Sendable {
    let video: Bool
    let duration: TimeInterval
    let outcome: CallOutcome
    /// I placed the call.
    let mine: Bool

    init(video: Bool, duration: TimeInterval, outcome: CallOutcome, mine: Bool) {
        self.video = video; self.duration = duration; self.outcome = outcome; self.mine = mine
    }

    init?(body: String, mine: Bool) {
        guard let data = body.data(using: .utf8), let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let outcome = (json["outcome"] as? String).flatMap(CallOutcome.init(rawValue:)) else { return nil }
        self.init(video: (json["video"] as? Bool) ?? false, duration: Double((json["duration_ms"] as? Int) ?? 0) / 1000, outcome: outcome, mine: mine)
    }

    /// A missed incoming call (shown in the danger red).
    var isMissedIncoming: Bool { !mine && outcome.isMissed }
    var kind: String { video ? "video" : "voice" }

    /// "Voice call", "Video call", "Missed voice call".
    var title: String { isMissedIncoming ? "Missed \(kind) call" : (video ? "Video call" : "Voice call") }

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
        return "\(title) \u{00B7} \(detail)"
    }

    var symbol: String {
        if isMissedIncoming { return video ? "video.slash" : "phone.arrow.down.left" }
        return video ? "video" : "phone"
    }
}
