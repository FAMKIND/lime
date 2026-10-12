import Foundation

extension ConversationStore {
    /// A person's public profile: the last answer this session at once, then fresh from the server (nothing is stored on disk).
    func loadProfile(_ userID: String) async {
        guard let core, let link else { return }
        guard let token = try? await link.token() else { return }
        let found = try? await Task.detached(priority: .userInitiated) {
            try core.fetchProfile(transport: link.transport, authToken: token, userId: userID)
        }.value
        if let profile = found ?? nil { publicProfiles[userID] = profile }
    }

    /// What was shared in a chat of this kind, optionally from one person (`"me"` is mine), newest first.
    func shared(in conversationID: String, from sender: String?, kind: SharedKind) -> [Message] {
        #if DEBUG
        if isDemo { return demoShared(in: conversationID, from: sender, kind: kind) }
        #endif
        guard let core else { return [] }
        return ((try? core.listShared(conversationId: conversationID, senderId: sender, kind: kind)) ?? []).map(Message.init)
    }

    /// Demo mode (UI tests): the same filtering over the in-memory messages.
    private func demoShared(in conversationID: String, from sender: String?, kind: SharedKind) -> [Message] {
        let messages = conversation(conversationID)?.messages ?? []
        return messages.filter { message in
            guard !message.deleted, !message.isSystem, message.call == nil else { return false }
            if let sender, (sender == "me" ? !message.isOwn : message.senderID != sender) { return false }
            switch kind {
            case .media: return message.attachments.contains { $0.kind == .image || $0.kind == .video }
            case .files: return message.attachments.contains { $0.kind != .image && $0.kind != .video }
            case .links: return message.linkPreview != nil || message.text.lowercased().contains("http://") || message.text.lowercased().contains("https://")
            }
        }.sorted { $0.date > $1.date }
    }
}

extension ConversationStore {
    /// Opens a profile in the tab that is showing.
    func openProfile(_ route: ProfileRoute) {
        switch section {
        case .link: path.append(route)
        case .call: callPath.append(route)
        case .jam: jamPath.append(route)
        }
    }

    /// Your own header avatar: your profile.
    func openMyProfile() {
        let me = meProvider()
        openProfile(ProfileRoute(userID: me.id, name: me.name, isMe: true))
    }
}
