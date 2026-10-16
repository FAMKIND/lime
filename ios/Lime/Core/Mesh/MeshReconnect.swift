import Foundation

/// How long to wait before connecting again to a phone whose link ended (LIME-141-fix2). Two phones that cannot agree on a link used to
/// reconnect every 0.35 s for half an hour; now each failure doubles the wait (0.5 s, 1, 2, 4 … 60 s, with jitter) and only a link that stayed
/// up for 30 s starts over. A link that ended within 2 s of opening counts as a failure.
struct ReconnectBackoff: Equatable {
    static let base: TimeInterval = 0.5
    static let cap: TimeInterval = 60
    /// A link this old when it ended was a good one.
    static let stable: TimeInterval = 30
    /// A link that ended this soon after opening was no link.
    static let quick: TimeInterval = 2

    private(set) var failures = 0

    /// A link ended. `livedFor` is how long it was up (nil: it never came up).
    mutating func linkEnded(livedFor: TimeInterval?) {
        guard let livedFor else { failures += 1; return }
        if livedFor >= Self.stable { failures = 0 } else if livedFor < Self.quick { failures += 1 }
        // Between 2 and 30 seconds: neither a failure nor a recovery.
    }

    /// The wait before the next connection attempt: `base × 2^failures`, at most `cap`, spread by `jitter` (0.8…1.2).
    func delay(jitter: Double = Double.random(in: 0.8...1.2)) -> TimeInterval {
        min(Self.cap, Self.base * pow(2, Double(min(failures, 10)))) * jitter
    }
}

/// Counts connection attempts over a minute and says when to warn: more than 10 in a minute, and at most one warning a minute.
struct ReconnectStormGuard {
    static let limit = 10
    private var attempts: [Date] = []
    private var lastWarning: Date?

    /// Records an attempt; true when this one should log `WARNING reconnect storm`.
    mutating func record(at now: Date) -> Bool {
        attempts.append(now)
        attempts.removeAll { now.timeIntervalSince($0) > 60 }
        guard attempts.count > Self.limit else { return false }
        if let lastWarning, now.timeIntervalSince(lastWarning) < 60 { return false }
        lastWarning = now
        return true
    }

    var perMinute: Int { attempts.count }
}

/// L2CAP channels that arrived before the hello that names their phone was handled (a race the logs showed 4,500 times): kept for a short
/// grace and bound when the peer appears, instead of being closed at once (which made the other phone drop the link and reconnect).
struct PendingChannels<Channel> {
    static var grace: TimeInterval { 2 }
    private var held: [UUID: (channel: Channel, since: Date)] = [:]

    mutating func hold(_ channel: Channel, from phone: UUID, at now: Date) { held[phone] = (channel, now) }

    /// The channel waiting for this phone, if it is still within the grace.
    mutating func take(for phone: UUID, at now: Date) -> Channel? {
        guard let entry = held.removeValue(forKey: phone) else { return nil }
        return now.timeIntervalSince(entry.since) <= Self.grace ? entry.channel : nil
    }

    /// The channels whose grace has run out (to be closed).
    mutating func expire(at now: Date) -> [Channel] {
        let old = held.filter { now.timeIntervalSince($0.value.since) > Self.grace }
        for key in old.keys { held[key] = nil }
        return old.values.map(\.channel)
    }

    var count: Int { held.count }
}

/// When the launch key check may run (LIME-144, 141-fix2): once per launch, when a session and the internet both exist, retried when either
/// appears later; every skipped try says why (so a silent log can never mean "it did not run").
enum MeshKeyCheckGate {
    enum Decision: Equatable { case run, skip(why: String) }

    static func decide(alreadyChecked: Bool, engineReady: Bool, online: Bool, hasSession: Bool) -> Decision {
        if alreadyChecked { return .skip(why: "done") }
        if !engineReady { return .skip(why: "no-engine") }
        if !online { return .skip(why: "offline") }
        if !hasSession { return .skip(why: "no-session") }
        return .run
    }

    /// The line the check always leaves.
    static func line(matches: Bool?, pinned: String, server: String, why: String) -> (kind: String, detail: [String: String]) {
        switch matches {
        case true?: return ("mesh_key_check", ["result": "ok", "key": pinned])
        case false?: return ("mesh_key_check", ["result": "mismatch", "pinned": pinned, "server": server])
        case nil: return ("mesh_key_check", ["result": "unavailable", "why": why])
        }
    }
}
