import Foundation

/// What VoiceOver says when the roll-up changes under the person (LIME-130-5b): "<Name> needs help", "<Name> is safe", and when several change
/// together or close together, "3 people updated". Announcements only: no new surface (Emergency stays in Settings and the long-press).
enum EmergencyAnnouncements {
    /// The words for each person whose status changed between two roll-ups. You (no id) are skipped (you know), as is "no response yet".
    static func changes(old: [RollupEntry], new: [RollupEntry], name: (RollupEntry) -> String) -> [String] {
        var before: [String: String] = [:]
        for entry in old { if let id = entry.userId { before[id] = entry.status } }
        return new.compactMap { entry in
            guard let id = entry.userId, before[id] != entry.status else { return nil }
            switch entry.status {
            case "need_help": return "\(name(entry)) needs help"
            case "safe": return "\(name(entry)) is safe"
            default: return nil
            }
        }
    }

    /// One change is said as it is; several become a count.
    static func summary(_ changes: [String]) -> String {
        changes.count == 1 ? changes[0] : "\(changes.count) people updated"
    }
}

/// Says the changes, at most once every `gap` seconds: anything that arrives sooner waits and is said together, as a count.
@MainActor
final class EmergencyAnnouncer {
    static let gap: TimeInterval = 2
    private var last: Date?
    private var pending: [String] = []
    private var flush: Task<Void, Never>?
    private let say: (String) -> Void
    private let now: () -> Date

    init(say: @escaping (String) -> Void = { Announce.say($0) }, now: @escaping () -> Date = { Date() }) {
        self.say = say
        self.now = now
    }

    func note(_ changes: [String]) {
        guard !changes.isEmpty else { return }
        let time = now()
        if pending.isEmpty, last == nil || time.timeIntervalSince(last!) >= Self.gap {
            last = time
            say(EmergencyAnnouncements.summary(changes))
            return
        }
        pending += changes
        guard flush == nil else { return }
        let wait = max(0, Self.gap - time.timeIntervalSince(last ?? .distantPast))
        flush = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled, let self else { return }
            self.flushNow()
        }
    }

    func flushNow() {
        flush?.cancel(); flush = nil
        guard !pending.isEmpty else { return }
        let words = EmergencyAnnouncements.summary(pending)
        pending = []
        last = now()
        say(words)
    }
}
