import Foundation

/// The mesh's side of sending real messages (LIME-142), apart from the radio and the screens, so it can be tested with a fake engine:
/// - **pump**: what the app could not send (kept sealed in LimeCore's mesh outbox) goes onto the mesh; a Hello goes out when something new was
///   queued; the engine's notes (queued, passed, delivered with delay and hops) go to the log;
/// - **upload**: with internet, everything the phone carries goes to the server through `mesh-drop`, once at a time.
@MainActor
final class MeshOutboxRunner {
    private let engine: MeshEngineProtocol
    private weak var driver: MeshDriver?
    private let log: (_ kind: String, _ detail: [String: String]) -> Void
    private(set) var uploading = false

    init(engine: MeshEngineProtocol, driver: MeshDriver?, log: @escaping (String, [String: String]) -> Void) {
        self.engine = engine
        self.driver = driver
        self.log = log
    }

    /// Returns how many packets were newly queued.
    @discardableResult
    func pump() -> UInt32 {
        let queued = (try? engine.pumpOutbox()) ?? 0
        if queued > 0 { driver?.packetQueued() }
        drainNotes()
        return queued
    }

    /// The engine's notes as log lines ("mesh_delivered kind=message id=ab12 after=9s hops=2" becomes kind `mesh_delivered`, with the rest as details).
    /// Called when a reply from a neighbour's fetch brought items (relay download): the chats are reloaded.
    var onFetchedMessages: (() -> Void)?

    func drainNotes() {
        for line in engine.takeNotes() {
            let parts = line.split(separator: " ").map(String.init)
            guard let kind = parts.first else { continue }
            var detail: [String: String] = [:]
            for part in parts.dropFirst() {
                let pair = part.split(separator: "=", maxSplits: 1).map(String.init)
                if pair.count == 2 { detail[pair[0]] = pair[1] }
            }
            log(kind, detail)
            if kind == "fetch_reply", let items = detail["items"].flatMap({ Int($0) }), items > 0 { onFetchedMessages?() }
        }
    }

    /// Uploads what is carried, if there is internet and no upload is running. `upload` does the call (the real one is `engine.uploadAll`; the
    /// core writes `upload_try`, `upload_ok`, `upload_fail` and `upload_dropped` lines per packet). `trigger` says what asked for it
    /// (connectivity, active, tick, sync, frame) and is logged when something was skipped or failed. Returns how many the server stored.
    @discardableResult
    func uploadIfOnline(online: Bool, trigger: String = "", upload: () async throws -> UInt32) async -> UInt32 {
        guard online else { if trigger != "tick" { log("upload_skip", ["why": "offline", "trigger": trigger]) }; return 0 }
        guard !uploading else { log("upload_skip", ["why": "busy", "trigger": trigger]); return 0 }
        uploading = true
        defer { uploading = false }
        do {
            let stored = try await upload()
            drainNotes()
            if stored > 0 { log("mesh_uploaded", ["stored": String(stored), "trigger": trigger]) }
            return stored
        } catch {
            drainNotes()
            log("upload_error", ["error": String(describing: error), "trigger": trigger])
            return 0
        }
    }
}
