import Foundation

/// How a call ended, for the chat's call line and the Calls list.
enum CallOutcome: String, Codable, Sendable {
    case completed, missed, declined, noAnswer, busy, failed
}

/// One call, kept on this phone (Calls tab and the chat's timeline).
struct CallRecord: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let peerID: String
    var peerName: String
    let video: Bool
    let outgoing: Bool
    let date: Date
    var duration: TimeInterval
    var outcome: CallOutcome

    /// "Voice call · 4:12", "Missed call", "Video call · 0:31", "Declined call", "No answer".
    var line: String {
        let kind = video ? "Video call" : "Voice call"
        switch outcome {
        case .completed: return "\(kind) · \(Self.clock(duration))"
        case .missed: return outgoing ? "No answer" : "Missed \(video ? "video " : "")call"
        case .declined: return outgoing ? "\(kind) declined" : "Declined \(video ? "video " : "")call"
        case .noAnswer: return "No answer"
        case .busy: return "\(peerName) was busy"
        case .failed: return "\(kind) failed"
        }
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return total >= 3600 ? String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60) : String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Where the calls are kept: the encrypted core store on a phone, a fake in tests.
@MainActor
protocol CallHistoryBacking: AnyObject {
    func add(_ record: CallRecord)
    func list() -> [CallRecord]
    func delete(ids: [String])
    func clear()
    func markMissedSeen()
    func missedUnseen() -> Int
}

/// The calls on this phone (at most 500), newest first. They live in the encrypted core store once it is open (`attach`); the
/// first time, records an older build kept in the phone's settings are moved there and that key is removed.
@MainActor
@Observable
final class CallLog {
    static let shared = CallLog()
    private(set) var records: [CallRecord] = []
    /// Missed incoming calls not yet seen (the call tab's badge).
    private(set) var missedUnseen = 0
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var backing: CallHistoryBacking?
    static let legacyKey = "lime.callLog"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    /// The store is open: move any old records in (once), then read from it.
    func attach(_ backing: CallHistoryBacking?) {
        self.backing = backing
        guard let backing else { records = []; missedUnseen = 0; return }
        if let data = defaults.data(forKey: Self.legacyKey) {
            if let old = try? JSONDecoder().decode([CallRecord].self, from: data) { old.forEach { backing.add($0) } }
            defaults.removeObject(forKey: Self.legacyKey)
        }
        // Calls logged before the store opened (in memory only) go in too.
        let pending = records
        pending.forEach { backing.add($0) }
        reload()
    }

    func reload() {
        guard let backing else { return }
        records = backing.list()
        missedUnseen = backing.missedUnseen()
    }

    func add(_ record: CallRecord) {
        if let backing {
            backing.add(record)
            reload()
        } else {
            records.removeAll { $0.id == record.id }
            records.insert(record, at: 0)
            if !record.outgoing && record.outcome == .missed { missedUnseen += 1 }
        }
    }

    func records(with peerID: String) -> [CallRecord] { records.filter { $0.peerID == peerID } }

    func delete(ids: [String]) {
        if let backing { backing.delete(ids: ids); reload() } else { records.removeAll { ids.contains($0.id) } }
    }

    func clear() {
        if let backing { backing.clear(); reload() } else { records = []; missedUnseen = 0 }
        defaults.removeObject(forKey: Self.legacyKey)
    }

    /// The call tab was opened.
    func markMissedSeen() {
        if let backing { backing.markMissedSeen(); reload() } else { missedUnseen = 0 }
    }
}

/// The core store's `call_history` table, as the log's backing.
@MainActor
final class CoreCallHistory: CallHistoryBacking {
    private let core: LimeStore
    init(_ core: LimeStore) { self.core = core }

    func add(_ r: CallRecord) {
        try? core.callHistoryAdd(record: CallHistoryRecord(
            id: r.id, peer: r.peerID, peerName: r.peerName, video: r.video, outgoing: r.outgoing,
            atMs: Int64(r.date.timeIntervalSince1970 * 1000), durationMs: Int64(r.duration * 1000), outcome: r.outcome.rawValue))
    }

    func list() -> [CallRecord] {
        ((try? core.callHistoryList()) ?? []).map {
            CallRecord(id: $0.id, peerID: $0.peer, peerName: $0.peerName, video: $0.video, outgoing: $0.outgoing,
                       date: Date(timeIntervalSince1970: Double($0.atMs) / 1000), duration: Double($0.durationMs) / 1000,
                       outcome: CallOutcome(rawValue: $0.outcome) ?? .failed)
        }
    }

    func delete(ids: [String]) { try? core.callHistoryDelete(ids: ids) }
    func clear() { try? core.callHistoryClear() }
    func markMissedSeen() { try? core.callHistoryMarkMissedSeen() }
    func missedUnseen() -> Int { Int((try? core.callHistoryMissedUnseenCount()) ?? 0) }
}

#if DEBUG
extension CallLog {
    /// UI tests and screenshots (`-lime-demo-calls`): a few made-up calls with the demo chats' people.
    func seedDemo(now: Date = Date()) {
        func make(_ id: String, _ peer: String, _ name: String, video: Bool, outgoing: Bool, minutesAgo: Double, seconds: Double, _ outcome: CallOutcome) -> CallRecord {
            CallRecord(id: id, peerID: peer, peerName: name, video: video, outgoing: outgoing, date: now.addingTimeInterval(-minutesAgo * 60), duration: seconds, outcome: outcome)
        }
        for record in [
            make("d5", "sam", "Sam Park", video: false, outgoing: true, minutesAgo: 3 * 24 * 60, seconds: 0, .noAnswer),
            make("d4", "lee", "Lee Wong", video: false, outgoing: false, minutesAgo: 26 * 60, seconds: 61, .completed),
            make("d3", "sam", "Sam Park", video: true, outgoing: true, minutesAgo: 4, seconds: 252, .completed),
            make("d2", "lee", "Lee Wong", video: false, outgoing: false, minutesAgo: 2, seconds: 0, .missed),
            make("d1", "lee", "Lee Wong", video: false, outgoing: false, minutesAgo: 1, seconds: 0, .missed),
        ] { add(record) }
    }
}
#endif
