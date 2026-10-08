#if DEBUG
import Foundation
import Observation
import UIKit

// LIME-103: a throwaway, Debug-only Bluetooth LE field test. Nothing here ships: the whole `Debug/Nearby`
// folder is behind `#if DEBUG`, and it is deleted or replaced by the mesh (see docs/spike-ble.md).

/// One thing that happened, for the screen.
struct NearbyEvent: Identifiable, Sendable {
    let id = UUID()
    let time: Date
    let kind: String
    let detail: String
}

/// The run's log: shown live, and written line by line (JSON lines) to a file so a run that is killed or
/// backgrounded still leaves its record. No messages, no user data, no keys: only what Bluetooth did.
@MainActor
@Observable
final class NearbyLog {
    private(set) var events: [NearbyEvent] = []
    private(set) var fileURL: URL?
    @ObservationIgnored private var handle: FileHandle?
    @ObservationIgnored private static let stamp: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static var directory: URL {
        let url = URL.documentsDirectory.appending(path: "nearby-logs", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Earlier runs, newest first.
    static func savedRuns() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return files.filter { $0.pathExtension == "jsonl" }.sorted {
            let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return a > b
        }
    }

    /// Starts a run's file with a header line (device model, iOS version, the scenario label, battery).
    func begin(label: String, extra: [String: Any]) {
        events = []
        let safe = label.map { $0.isLetter || $0.isNumber || $0 == "-" ? $0 : "_" }
        let name = "nearby-\(String(safe).prefix(40))-\(Int(Date().timeIntervalSince1970)).jsonl"
        let url = Self.directory.appending(path: name)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        fileURL = url
        handle = try? FileHandle(forWritingTo: url)
        UIDevice.current.isBatteryMonitoringEnabled = true
        var header: [String: Any] = [
            "kind": "header", "scenario": label, "device": Self.machine(), "ios": UIDevice.current.systemVersion,
            "app": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?",
            "battery": Self.battery(), "started": Self.stamp.string(from: Date()), "spike": "LIME-103",
        ]
        header.merge(extra) { _, new in new }
        write(header)
    }

    func record(_ kind: String, _ fields: [String: Any] = [:]) {
        let now = Date()
        var line = fields
        line["t"] = Self.stamp.string(from: now)
        line["ms"] = Int(now.timeIntervalSince1970 * 1000)
        line["kind"] = kind
        write(line)
        let detail = fields.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
        events.append(NearbyEvent(time: now, kind: kind, detail: detail))
        if events.count > 300 { events.removeFirst(events.count - 300) }
    }

    func end(summary: [String: Any]) {
        var line = summary
        line["battery"] = Self.battery()
        record("summary", line)
        try? handle?.close()
        handle = nil
    }

    private func write(_ object: [String: Any]) {
        guard let handle, let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return }
        try? handle.write(contentsOf: data + Data("\n".utf8))
    }

    /// Battery percent (-1 when unknown, as on a simulator) and state.
    static func battery() -> [String: Any] {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let level = UIDevice.current.batteryLevel
        let state: String
        switch UIDevice.current.batteryState {
        case .charging: state = "charging"
        case .full: state = "full"
        case .unplugged: state = "unplugged"
        default: state = "unknown"
        }
        return ["percent": level < 0 ? -1 : Int((level * 100).rounded()), "state": state]
    }

    /// The hardware model, e.g. "iPhone14,4".
    static func machine() -> String {
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var bytes = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &bytes, &size, nil, 0)
        return String(decoding: bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
#endif
