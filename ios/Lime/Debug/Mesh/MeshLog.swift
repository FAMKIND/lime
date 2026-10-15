#if DEBUG
import Foundation
import Observation
import UIKit

/// The mesh's diagnostics (LIME-141, Debug builds only), like the call diagnostics: links up and down, frames in and out (sizes only), the
/// engine's counts every minute, restores, the scan cycle. **No tags, digests or ids in full**: callers pass four-character prefixes. Shown
/// live and written line by line (JSON lines) so a run that is backgrounded or ended still leaves its record.
struct MeshEvent: Identifiable {
    let id = UUID()
    let time: Date
    let kind: String
    let detail: String
}

@MainActor
@Observable
final class MeshLog {
    private(set) var events: [MeshEvent] = []
    private(set) var fileURL: URL?
    @ObservationIgnored private var handle: FileHandle?
    @ObservationIgnored private static let stamp: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static var directory: URL {
        let url = URL.documentsDirectory.appending(path: "mesh-logs", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func savedRuns() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "jsonl" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    func begin() {
        guard handle == nil else { return }
        let url = Self.directory.appending(path: "mesh-\(Int(Date().timeIntervalSince1970)).jsonl")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        fileURL = url
        handle = try? FileHandle(forWritingTo: url)
        UIDevice.current.isBatteryMonitoringEnabled = true
        write(["kind": "header", "device": UIDevice.current.model, "ios": UIDevice.current.systemVersion, "battery": Int(UIDevice.current.batteryLevel * 100),
               "state": "\(UIDevice.current.batteryState.rawValue)", "started": Self.stamp.string(from: Date())])
    }

    func record(_ kind: String, _ detail: [String: String] = [:]) {
        begin()
        let event = MeshEvent(time: Date(), kind: kind, detail: detail.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))
        events.append(event)
        if events.count > 400 { events.removeFirst(events.count - 400) }
        var line: [String: Any] = ["kind": kind, "t": Self.stamp.string(from: event.time), "battery": Int(UIDevice.current.batteryLevel * 100)]
        for (key, value) in detail where line[key] == nil { line[key] = value }
        write(line)
    }

    private func write(_ line: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: line, options: [.sortedKeys]), let handle else { return }
        handle.seekToEndOfFile()
        handle.write(data + Data("\n".utf8))
    }
}
#endif
