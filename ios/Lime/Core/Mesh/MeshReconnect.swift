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

    /// A link ended. `livedFor` is how long it was up (nil: it never came up); `carriedFrame` whether a frame came over it.
    /// **A link is a failure unless it bound and carried a frame, or stayed up 30 s: never by time alone** (a link that lived 2.1 s because a
    /// grace period ran out used to count as fine, so the wait never grew). One that carried a frame but was short is neither.
    mutating func linkEnded(livedFor: TimeInterval?, carriedFrame: Bool = false) {
        guard let livedFor else { failures += 1; return }
        if livedFor >= Self.stable { failures = 0 } else if !carriedFrame { failures += 1 }
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

/// One link per pair, decided the same way on both phones (LIME-141-fix3): when each is connecting to the other, the phone with the **lower**
/// link id keeps its own (outbound) connection as the central; the other drops its outbound and accepts the inbound.
enum MeshTieBreak {
    static func keepsOutbound(local: UInt64, remote: UInt64) -> Bool { local < remote }
}

/// When the mesh engine may be attached (LIME-141-fix3, item 4): as soon as the account's store exists, whenever that is. A phone relaunched by
/// iOS for Bluetooth while locked has no store at first; the engine used to give up after 60 s and never attach for the life of that process.
enum MeshAttachGate {
    static func shouldAttach(attached: Bool, helpEnabled: Bool, explained: Bool, coreReady: Bool) -> Bool {
        !attached && helpEnabled && explained && coreReady
    }
}

/// Whether a phone whose registration with the server failed at launch still gets a (pending) link (LIME-141-fix4, fix5). Without one every send
/// became a local-only message that said "Sent" and went nowhere. **Whatever the failure looked like** (offline, a refresh that failed, a server
/// error) a signed-in phone gets the link; only an ended session (signed out elsewhere) does not. fix4 also asked "has this phone registered
/// before?" through a flag that phones signed in earlier never had, so it never took effect on the 13 mini.
enum OfflineLinkRule {
    static func shouldConnect(_ problem: ConnectionProblem) -> Bool { problem != .sessionEnded }
}

/// When an offline phone asks a neighbour to fetch its mail, and who it asks (LIME-155). The engine allows one request in flight and gives up on it
/// after 20 s; these rules decide when to start one and which neighbour is next.
enum MeshFetchRules {
    /// While offline, one request a minute.
    static let interval: TimeInterval = 60

    enum Trigger: Equatable {
        /// A neighbour that can fetch for me has just appeared (or said so).
        case neighbour
        /// The periodic tick while offline.
        case tick
    }

    /// Ask only when this phone is offline, signed in (it has an account to fetch for) and a linked neighbour says it can fetch; a new neighbour is
    /// asked at once, otherwise once a minute.
    static func shouldRequest(offline: Bool, signedIn: Bool, hasOnlineNeighbour: Bool, secondsSinceLast: TimeInterval?, trigger: Trigger) -> Bool {
        guard offline, signedIn, hasOnlineNeighbour else { return false }
        switch trigger {
        case .neighbour: return true
        case .tick: return secondsSinceLast.map { $0 >= interval } ?? true
        }
    }

    /// Why an offline phone did not ask (nil: it asks, or it is online and never would). Logged once per reason per minute as `fetch_skip`.
    static func skipReason(offline: Bool, signedIn: Bool, neighbours: [UInt64], lastAsked: [UInt64: Date], secondsSinceLast: TimeInterval?, trigger: Trigger) -> String? {
        guard offline else { return nil }
        if !signedIn { return "not_signed_in" }
        if neighbours.isEmpty { return "no_online_neighbour" }
        if !shouldRequest(offline: offline, signedIn: signedIn, hasOnlineNeighbour: true, secondsSinceLast: secondsSinceLast, trigger: trigger) { return "asked_within_minute" }
        if trigger == .neighbour, neighbours.allSatisfy({ lastAsked[$0] != nil }) { return "already_asked" }
        return nil
    }

    /// The neighbour asked least recently (one that was never asked first), so a request that timed out goes to the next one.
    static func nextNeighbour(candidates: [UInt64], lastAsked: [UInt64: Date]) -> UInt64? {
        candidates.min { (lastAsked[$0] ?? .distantPast) < (lastAsked[$1] ?? .distantPast) }
    }

    /// A phone tells its neighbours it can fetch for them when it is online and signed in.
    static func relayOnline(online: Bool, signedIn: Bool) -> Bool { online && signedIn }
}
