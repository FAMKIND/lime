import Foundation

/// Group calls through LimeCore and the signed-in session. All the rules live in the core; these are only the calls.
@MainActor
final class StoreGroupCallCore: GroupCallCore {
    private weak var store: ConversationStore?
    private let diag = CallDiagnostics.shared
    init(store: ConversationStore) { self.store = store }

    func start(conversationID: String, video: Bool) async throws -> GroupCallInfo {
        guard let core = store?.core else { throw AuthError.network }
        return try await Task.detached(priority: .userInitiated) { try core.startGroupCall(conversationId: conversationID, video: video) }.value
    }

    func join(callID: String) async throws -> GroupCallJoin {
        guard let core = store?.core else { throw AuthError.network }
        return try await Task.detached(priority: .userInitiated) { try core.joinGroupCall(callId: callID) }.value
    }

    func leave(callID: String) async {
        guard let core = store?.core else { return }
        _ = try? await Task.detached(priority: .userInitiated) { try core.leaveGroupCall(callId: callID) }.value
    }

    func recover() async -> [String] {
        guard let core = store?.core else { return [] }
        return (try? await Task.detached(priority: .userInitiated) { try core.recoverGroupCalls() }.value) ?? []
    }

    func participantGone(callID: String, participant: String) async {
        guard let core = store?.core else { return }
        _ = try? await Task.detached(priority: .userInitiated) { try core.groupCallParticipantGone(callId: callID, participant: participant) }.value
    }

    func token(room: String, participant: String) async -> LiveKitToken? {
        guard let store, let core = store.core, let link = store.link else { return nil }
        return await Retry.once(after: .seconds(1), log: { CallDiagnostics.shared.log($0) }) { () async throws -> LiveKitToken? in
            let token = try await link.token()
            return try await Task.detached(priority: .userInitiated) {
                try core.fetchLivekitToken(transport: link.transport, authToken: token, room: room, participant: participant)
            }.value
        }
    }

    func iceServers() async -> [IceServer] {
        guard let store else { return [] }
        return await StoreSignalling(store: store).iceServers()
    }

    func deliver() async -> GroupCallSendReport? {
        guard let store, let core = store.core, let link = store.link else { return nil }
        do {
            let token = try await link.token()
            return try await Task.detached(priority: .userInitiated) { try core.deliverGroupCallOps(transport: link.transport, authToken: token) }.value
        } catch {
            diag.log("group call: sending failed (\(error))")
            return nil
        }
    }

    func requestKey(callID: String, participant: String) async {
        guard let core = store?.core else { return }
        _ = try? await Task.detached(priority: .userInitiated) { try core.requestGroupCallKey(callId: callID, participant: participant) }.value
    }

    func takeEvents() -> [GroupCallEvent] {
        (try? store?.core?.takeGroupCallEvents()) ?? []
    }

    func activeCall(conversationID: String) -> GroupCallInfo? {
        (try? store?.core?.activeGroupCall(conversationId: conversationID)) ?? nil
    }

    func emojiState(callID: String) -> GroupCallEmojiState? {
        try? store?.core?.groupCallEmojiState(callId: callID)
    }

    func isCustomNamed(conversationID: String) -> Bool {
        (try? store?.core?.groupIsCustomNamed(conversationId: conversationID)) ?? true
    }

    func title(of conversationID: String) -> String {
        store?.conversations.first { $0.id == conversationID }?.title ?? "Group"
    }
}
