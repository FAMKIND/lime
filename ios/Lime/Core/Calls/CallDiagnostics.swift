import Foundation

/// A short, private log of what a call did (signalling, ICE state, candidate kinds, TURN status, CallKit actions), for finding why
/// a call did not connect. No IP addresses, no SDP, no keys: candidate *types* only. In a Debug build it is kept in a file in Caches, with
/// complete file protection, and shared only through the Debug-only Share button. **In Release it is in memory only: no file is written** (the
/// security review's F-05; LIME-166), and a file an earlier build left behind is removed.
@MainActor
final class CallDiagnostics {
    static let shared = CallDiagnostics()
    private(set) var lines: [String] = []
    private let url: URL
    private let clock: () -> Date
    private let persists: Bool

    /// A file only in a Debug build.
    static let persistsByDefault: Bool = {
        #if DEBUG
        true
        #else
        false
        #endif
    }()

    init(url: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("call-diagnostics.log"),
         clock: @escaping () -> Date = Date.init, persists: Bool = CallDiagnostics.persistsByDefault) {
        self.url = url
        self.clock = clock
        self.persists = persists
        if persists {
            lines = (try? String(contentsOf: url, encoding: .utf8))?.split(separator: "\n").map(String.init) ?? []
        } else {
            try? FileManager.default.removeItem(at: url)   // what an earlier build wrote
        }
    }

    func log(_ event: String) {
        let stamp = Self.format.string(from: clock())
        lines.append("\(stamp) \(event)")
        if lines.count > 2000 { lines.removeFirst(lines.count - 2000) }
        guard persists else { return }
        // Complete protection: unreadable while the phone is locked. A line logged then is kept in `lines` and written with the next one.
        try? Data(lines.joined(separator: "\n").utf8).write(to: url, options: [.atomic, .completeFileProtection])
    }

    func clear() {
        lines = []
        try? FileManager.default.removeItem(at: url)
    }

    var fileURL: URL { url }
    var text: String { lines.joined(separator: "\n") }

    /// `typ host|srflx|relay|prflx` of a candidate line, never its address.
    nonisolated static func candidateKind(_ candidate: String) -> String {
        let parts = candidate.split(separator: " ")
        if let index = parts.firstIndex(of: "typ"), index + 1 < parts.count { return String(parts[index + 1]) }
        return "?"
    }

    private static let format: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()
}
