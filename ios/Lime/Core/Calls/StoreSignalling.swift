import Foundation

/// Sends call signalling over Lime's encrypted channel and fetches the TURN relay's credentials, through the signed-in session.
@MainActor
final class StoreSignalling: CallSignalling {
    private weak var store: ConversationStore?
    init(store: ConversationStore) { self.store = store }

    func send(peer: String, op: String, payload: [String: Any]) async -> Bool {
        guard let store, let core = store.core, let link = store.link,
              let data = try? JSONSerialization.data(withJSONObject: payload), let json = String(data: data, encoding: .utf8) else { return false }
        let started = Date()
        let diag = CallDiagnostics.shared
        defer { let waited = core.takeLockWaitMs(); if waited > 250 { diag.log("waited \(waited) ms for the core lock") } }
        do {
            let token = try await link.token()
            try await Task.detached(priority: .userInitiated) {
                try core.sendCallSignal(transport: link.transport, authToken: token, peerUserId: peer, opType: op, payload: json)
            }.value
            diag.log("send \(op) ok \(Int(Date().timeIntervalSince(started) * 1000)) ms")
            return true
        } catch {
            diag.log("send \(op) FAILED \(Int(Date().timeIntervalSince(started) * 1000)) ms: \(error)")
            return false
        }
    }

    func iceServers() async -> [IceServer] {
        let fallback = [IceServer(urls: ["stun:turn.limechat.org:3478"], username: nil, credential: nil)]
        guard let store, let core = store.core, let link = store.link else { return fallback }
        let turn = await Retry.once(after: .seconds(1), log: { CallDiagnostics.shared.log($0) }) { () async throws -> TurnServers? in
            let token = try await link.token()
            return try await Task.detached(priority: .userInitiated) {
                try core.fetchTurnServers(transport: link.transport, authToken: token)
            }.value
        }
        guard let turn else {
            CallDiagnostics.shared.log("relay unavailable: placing the call without it")
            return fallback
        }
        return [IceServer(urls: turn.urls, username: turn.username, credential: turn.credential)]
    }
}

/// Tries a network step again once, a second later; `nil` if both tries fail (the call goes on without it).
@MainActor
enum Retry {
    static func once<T>(after delay: Duration, log: (String) -> Void = { _ in }, _ step: () async throws -> T?) async -> T? {
        for attempt in 1...2 {
            do {
                if let value = try await step() { return value }
                return nil // answered "not configured": no point asking again
            } catch {
                log("relay credentials: try \(attempt) failed (\(error))")
                if attempt == 1 { try? await Task.sleep(for: delay) }
            }
        }
        return nil
    }
}
