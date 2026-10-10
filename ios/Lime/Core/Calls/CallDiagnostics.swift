import Foundation

/// A short, private log of what a call did (signalling, ICE state, candidate kinds, TURN status, CallKit actions), for finding why
/// a call did not connect. No IP addresses, no SDP, no keys: candidate *types* only. Kept on this phone (a file in Caches),
/// shared only when the person taps Share in Debug builds.
@MainActor
final class CallDiagnostics {
    static let shared = CallDiagnostics()
    private(set) var lines: [String] = []
    private let url: URL
    private let clock: () -> Date

    init(url: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("call-diagnostics.log"),
         clock: @escaping () -> Date = Date.init) {
        self.url = url
        self.clock = clock
        lines = (try? String(contentsOf: url, encoding: .utf8))?.split(separator: "\n").map(String.init) ?? []
    }

    func log(_ event: String) {
        let stamp = Self.format.string(from: clock())
        lines.append("\(stamp) \(event)")
        if lines.count > 400 { lines.removeFirst(lines.count - 400) }
        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
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
