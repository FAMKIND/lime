import Foundation

/// Who connects to whom, and which links to keep (LIME-141). Pure logic.
///
/// Every phone is a central and a peripheral at once, so two phones that find each other both connect: two links. The rule that makes it one:
/// each phone has a **random link id** (new every launch and every ~15 minutes: it identifies nothing and is not in the advertisement, only in
/// the hello read after connecting), and **the lower id initiates**. A link is kept when the lower id is the central on it.
struct MeshLinkIdentity {
    private(set) var id: UInt64
    private(set) var since: Date
    static let rotationInterval: TimeInterval = 15 * 60

    init(now: Date = Date(), random: () -> UInt64 = { UInt64.random(in: 1...UInt64.max) }) {
        id = random()
        since = now
    }

    /// Makes a new id when the old one has been used for 15 minutes. Links already open keep the ids they were made with.
    @discardableResult
    mutating func rotateIfDue(now: Date, random: () -> UInt64 = { UInt64.random(in: 1...UInt64.max) }) -> Bool {
        guard now.timeIntervalSince(since) >= Self.rotationInterval else { return false }
        id = random()
        since = now
        return true
    }
}

enum MeshLinkPolicy {
    /// Weaker than this (dBm) is not worth connecting to. 127 is CoreBluetooth's "RSSI unavailable": unknown, not weak, so it is allowed.
    static let weakestRSSI = -96

    static func rssiAllowsConnecting(_ rssi: Int) -> Bool { rssi == 127 || rssi >= weakestRSSI }

    /// The lower id initiates.
    static func iShouldInitiate(local: UInt64, remote: UInt64) -> Bool { local < remote }

    /// Keep the link I have with `remote`? Only when the lower id is the central on it.
    static func keep(local: UInt64, remote: UInt64, iAmCentral: Bool) -> Bool {
        iShouldInitiate(local: local, remote: remote) == iAmCentral
    }
}

/// The live links by the remote phone's link id: one per pair. A second link to the same phone (the same id) is a duplicate and is refused.
struct MeshLinkRegistry {
    enum Verdict: Equatable {
        case keep
        /// The policy says the other phone should be the one to connect: close this one.
        case wrongDirection
        /// There is already a live link to that phone.
        case duplicate
        /// A phone with this very id: talking to myself.
        case myself
    }

    private(set) var live: Set<UInt64> = []

    mutating func claim(remote: UInt64, local: UInt64, iAmCentral: Bool) -> Verdict {
        guard remote != local else { return .myself }
        guard MeshLinkPolicy.keep(local: local, remote: remote, iAmCentral: iAmCentral) else { return .wrongDirection }
        guard !live.contains(remote) else { return .duplicate }
        live.insert(remote)
        return .keep
    }

    /// The grace-period fallback (LIME-141-fix): the other phone has the lower id and should have connected to me, but has not (it may be locked,
    /// and a locked phone does not scan or connect). After a short wait a link in the "wrong" direction is better than none: kept if there is
    /// still no link to that phone. If the lower phone then connects after all, its link finds this one live and is refused as a duplicate.
    mutating func claimFallback(remote: UInt64, local: UInt64) -> Bool {
        guard remote != local, !live.contains(remote) else { return false }
        live.insert(remote)
        return true
    }

    mutating func release(remote: UInt64) { live.remove(remote) }
}

/// Whether the peripheral side takes a link the policy calls "wrong direction" (LIME-141-fix4). The phone with the higher id waits a grace period
/// for the lower one to connect and then connects itself (the fallback); the lower phone used to refuse it by the same strict rule, so when the
/// lower phone's own outbound never completed, no link ever formed. A "wrong direction" inbound can only be that fallback (the higher phone only
/// writes its hello once the grace is over), so it is accepted unless the lower phone has a live link already or an outbound that is still
/// fresh (it started under 4 s ago and may be about to finish).
enum MeshInboundFallback {
    /// An outbound handshake younger than this may still finish: the fallback is refused rather than made a duplicate.
    static let freshSeconds: TimeInterval = 4

    static func shouldAccept(hasLiveLink: Bool, freshOutboundHandshake: Bool) -> Bool { !hasLiveLink && !freshOutboundHandshake }
}

/// The outbound handshake's own clock (LIME-141-fix4): connect, discover the service, read the hello. It used to wait for ever (the iPad's logs
/// show 19 connects and no hello, each ending 1–2 minutes later when the other side hung up).
enum MeshHandshakeWatchdog {
    static let timeout: TimeInterval = 10
    /// After this many handshakes in a row that never finished, stop dialling that phone for a while and wait for its fallback instead.
    static let failuresBeforePause = 2
    static let pauseSeconds: TimeInterval = 60

    static func pause(afterFailures failures: Int) -> TimeInterval { failures >= failuresBeforePause ? pauseSeconds : 0 }
}
