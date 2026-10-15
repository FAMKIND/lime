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
    /// Weaker than this (dBm) is not worth connecting to; 127 is the system's "unknown".
    static let weakestRSSI = -92

    static func rssiAllowsConnecting(_ rssi: Int) -> Bool { rssi != 127 && rssi >= weakestRSSI }

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

    mutating func release(remote: UInt64) { live.remove(remote) }
}
