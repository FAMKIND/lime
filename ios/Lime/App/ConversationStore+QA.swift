import Foundation
import SwiftUI

/// The Messages list's own actions (pin, mark unread, delete for me), private labels, and group pictures (LIME-104).
extension ConversationStore {
    // MARK: Messages list

    func setPinned(_ id: Conversation.ID, _ pinned: Bool) async {
        #if DEBUG
        if isDemo {
            if let index = conversations.firstIndex(where: { $0.id == id }) { conversations[index].isPinned = pinned }
            conversations.sort { $0.isPinned && !$1.isPinned }   // stable: pinned first, the rest keep their order
            return
        }
        #endif
        guard let core else { return }
        try? await Task.detached(priority: .userInitiated) { try core.setPinned(conversationId: id, pinned: pinned) }.value
        await reload()
    }

    func setMarkedUnread(_ id: Conversation.ID, _ unread: Bool) async {
        #if DEBUG
        if isDemo {
            if let index = conversations.firstIndex(where: { $0.id == id }) {
                conversations[index].markedUnread = unread
                if !unread { conversations[index].unread = 0 }
            }
            return
        }
        #endif
        guard let core else { return }
        if unread {
            try? await Task.detached(priority: .userInitiated) { try core.setMarkedUnread(conversationId: id, unread: true) }.value
        } else {
            try? await Task.detached(priority: .userInitiated) { try core.markRead(conversationId: id) }.value
        }
        await reload()
    }

    /// Deletes a chat from this phone only. A group I am still in is left first.
    func deleteChat(_ id: Conversation.ID) async {
        #if DEBUG
        if isDemo { conversations.removeAll { $0.id == id }; return }
        #endif
        guard let core else { return }
        // A group that is still going is left first; one that ended (I left it, or the owner deleted it) is just removed from my list.
        if id.hasPrefix("grp:"), conversation(id)?.isRequest == false, conversation(id)?.groupEnded == nil {
            await leaveGroup(id)
        }
        try? await Task.detached(priority: .userInitiated) { try core.deleteChat(conversationId: id) }.value
        await reload()
    }

    // MARK: Private labels

    /// My private label for a person (shown only on this phone). Empty removes it.
    func setLabel(_ label: String, for userID: String) async {
        let text = label.trimmingCharacters(in: .whitespacesAndNewlines)
        #if DEBUG
        if isDemo {
            applyLabel(text.isEmpty ? nil : String(text.prefix(30)), to: userID)
            return
        }
        #endif
        guard let core else { return }
        try? await Task.detached(priority: .userInitiated) { try core.setContactLabel(userId: userID, label: text.isEmpty ? nil : text) }.value
        await reload()
    }

    func applyLabel(_ label: String?, to userID: String) {
        for index in conversations.indices {
            for member in conversations[index].members.indices where conversations[index].members[member].id == userID {
                conversations[index].members[member].label = label
            }
        }
    }

    // MARK: Group pictures

    func setGroupPhoto(_ jpeg: Data, in id: Conversation.ID) async -> Bool {
        #if DEBUG
        if isDemo { AvatarCache.shared.set(jpeg, for: id); markGroupAvatar(id, emoji: nil); return true }
        #endif
        guard let core, let link else { return false }
        do {
            let token = try await link.token()
            try await Task.detached(priority: .userInitiated) { try core.setGroupPhoto(transport: link.transport, authToken: token, conversationId: id, jpeg: jpeg) }.value
            AvatarCache.shared.set(jpeg, for: id)
            await reload()
            Task { await deliverNow() }
            return true
        } catch {
            report(ConnectionProblem.from(error))
            return false
        }
    }

    /// An emoji for the group (or none): any photo it had is removed, here and from the server.
    func setGroupEmoji(_ emoji: String?, in id: Conversation.ID) async -> Bool {
        #if DEBUG
        if isDemo { AvatarCache.shared.set(nil, for: id); markGroupAvatar(id, emoji: emoji); return true }
        #endif
        guard let core, let link else { return false }
        do {
            let token = try await link.token()
            try await Task.detached(priority: .userInitiated) {
                try core.setGroupAvatarEmoji(transport: link.transport, authToken: token, conversationId: id, emoji: emoji)
            }.value
            AvatarCache.shared.set(nil, for: id)
            await reload()
            Task { await deliverNow() }
            return true
        } catch {
            report(ConnectionProblem.from(error))
            return false
        }
    }

    func removeGroupPhoto(in id: Conversation.ID) async -> Bool {
        #if DEBUG
        if isDemo { AvatarCache.shared.set(nil, for: id); markGroupAvatar(id, emoji: nil); return true }
        #endif
        guard let core, let link else { return false }
        do {
            let token = try await link.token()
            try await Task.detached(priority: .userInitiated) { try core.removeGroupPhoto(transport: link.transport, authToken: token, conversationId: id) }.value
            AvatarCache.shared.set(nil, for: id)
            await reload()
            Task { await deliverNow() }
            return true
        } catch {
            report(ConnectionProblem.from(error))
            return false
        }
    }

    /// Fetches the pictures of groups whose photo this phone does not have yet (new, changed or removed).
    func refreshGroupPhotos() async {
        #if DEBUG
        if isDemo { return }
        #endif
        guard let core, let link, let token = try? await link.token() else { return }
        let changed = (try? await Task.detached(priority: .utility) {
            try core.refreshGroupPhotos(transport: link.transport, authToken: token)
        }.value) ?? []
        guard !changed.isEmpty else { return }
        let loaded = await Task.detached(priority: .utility) { changed.map { ($0, (try? core.groupPhoto(conversationId: $0)) ?? nil) } }.value
        for (id, data) in loaded { AvatarCache.shared.set(data, for: id) }
    }

    #if DEBUG
    private func markGroupAvatar(_ id: Conversation.ID, emoji: String?) {
        guard let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[index].emoji = emoji
        if let details = demoGroups[id] { var changed = details; changed.emoji = emoji; demoGroups[id] = changed }
    }
    #endif
}
