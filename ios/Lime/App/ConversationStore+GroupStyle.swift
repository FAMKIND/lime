import Foundation
import UIKit

/// A group's colour and cover (LIME-257): set by its owner or an admin from Edit Cover on the group's page, carried in the group's signed, encrypted state like its
/// name and photo (the server holds only ciphertext), shown to every member. The cover is kept in `AvatarCache` under `group-cover:<id>`, the colour in `groupTones`;
/// with no colour chosen a group's comes from its id, as before.
extension ConversationStore {
    static func groupCoverKey(_ id: String) -> String { "group-cover:\(id)" }

    /// The group's colour: the one chosen, else one from its id.
    func groupTone(_ id: String) -> Int { groupTones[id] ?? AvatarTone.tone(for: id) }

    /// Reads what this phone holds for the group (its colour and cover), once.
    func loadGroupStyle(_ id: String) async {
        #if DEBUG
        if isDemo { return }
        #endif
        guard let core else { return }
        let held = await Task.detached(priority: .utility) { ((try? core.groupTone(conversationId: id)) ?? nil, (try? core.groupCover(conversationId: id)) ?? nil) }.value
        groupTones[id] = held.0.map { Int($0) }
        AvatarCache.shared.set(held.1, for: Self.groupCoverKey(id))
    }

    /// Fetches the covers of groups whose cover this phone does not have yet (new, changed or removed), then reads every group's colour and cover.
    func refreshGroupCovers() async {
        #if DEBUG
        if isDemo { return }
        #endif
        guard let core, let link, let token = try? await link.token() else { return }
        _ = try? await Task.detached(priority: .utility) { try core.refreshGroupCovers(transport: link.transport, authToken: token) }.value
        for conversation in conversations where conversation.id.hasPrefix("grp:") { await loadGroupStyle(conversation.id) }
    }

    @discardableResult
    func setGroupTone(_ id: String, tone: Int?) async -> Bool {
        #if DEBUG
        if isDemo { groupTones[id] = tone; return true }
        #endif
        guard let core else { return false }
        do {
            try await Task.detached(priority: .userInitiated) { try core.setGroupTone(conversationId: id, tone: tone.map { Int64($0) }) }.value
            groupTones[id] = tone
            await deliverNow()
            return true
        } catch {
            report(ConnectionProblem.from(error))
            return false
        }
    }

    @discardableResult
    func setGroupCover(_ id: String, jpeg: Data) async -> Bool {
        #if DEBUG
        if isDemo { AvatarCache.shared.set(jpeg, for: Self.groupCoverKey(id)); return true }
        #endif
        guard let core, let link else { return false }
        do {
            let token = try await link.token()
            try await Task.detached(priority: .userInitiated) { try core.setGroupCover(transport: link.transport, authToken: token, conversationId: id, jpeg: jpeg) }.value
            AvatarCache.shared.set(jpeg, for: Self.groupCoverKey(id))
            await deliverNow()
            return true
        } catch {
            report(ConnectionProblem.from(error))
            return false
        }
    }

    @discardableResult
    func removeGroupCover(_ id: String) async -> Bool {
        #if DEBUG
        if isDemo { AvatarCache.shared.set(nil, for: Self.groupCoverKey(id)); return true }
        #endif
        guard let core, let link else { return false }
        do {
            let token = try await link.token()
            try await Task.detached(priority: .userInitiated) { try core.removeGroupCover(transport: link.transport, authToken: token, conversationId: id) }.value
            AvatarCache.shared.set(nil, for: Self.groupCoverKey(id))
            await deliverNow()
            return true
        } catch {
            report(ConnectionProblem.from(error))
            return false
        }
    }
}
