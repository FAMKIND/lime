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

/// The calls on this phone, newest first (at most 200), in this phone's own settings.
@MainActor
@Observable
final class CallLog {
    static let shared = CallLog()
    private(set) var records: [CallRecord] = []
    @ObservationIgnored private let defaults: UserDefaults
    private static let key = "lime.callLog"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        records = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode([CallRecord].self, from: $0) } ?? []
    }

    func add(_ record: CallRecord) {
        records.removeAll { $0.id == record.id }
        records.insert(record, at: 0)
        if records.count > 200 { records.removeLast(records.count - 200) }
        if let data = try? JSONEncoder().encode(records) { defaults.set(data, forKey: Self.key) }
    }

    func records(with peerID: String) -> [CallRecord] { records.filter { $0.peerID == peerID } }

    func clear() {
        records = []
        defaults.removeObject(forKey: Self.key)
    }
}
