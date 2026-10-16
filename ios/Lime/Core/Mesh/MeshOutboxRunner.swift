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
        }
    }

    /// Uploads what is carried, if there is internet and no upload is running. `upload` does the call (the real one is `engine.uploadAll`).
    /// Returns how many the server stored.
    @discardableResult
    func uploadIfOnline(online: Bool, upload: () async throws -> UInt32) async -> UInt32 {
        guard online, !uploading else { return 0 }
        uploading = true
        defer { uploading = false }
        let stored = (try? await upload()) ?? 0
        if stored > 0 { log("mesh_uploaded", ["stored": String(stored)]) }
        return stored
    }
}
