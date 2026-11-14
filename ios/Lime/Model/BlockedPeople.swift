import Foundation

/// What a person blocked from anywhere looks like in the app (LIME-330), by core's rules (LIME-329): the words of the collapsed row and the reactions without them.
enum BlockedPeople {
    static let rowWords = "Message from someone you blocked"

    /// "Message from someone you blocked", or "3 messages from someone you blocked".
    static func collapsedWords(count: Int) -> String {
        count == 1 ? rowWords : "\(count) messages from someone you blocked"
    }

    /// What a quote of a blocked person's message reads as.
    static let quoteWords = "a blocked person\u{2019}s message"

    /// The chips without the blocked people's: not in the faces, not in the count (core's `visibleReactions`).
    static func visible(_ chips: [ReactionChip], blocked: Set<String>) -> [ReactionChip] {
        guard !blocked.isEmpty else { return chips }
        let reactions = chips.map { Reaction(emoji: $0.emoji, count: UInt32($0.count), mine: $0.mine, people: $0.people, personIds: $0.personIDs) }
        return visibleReactions(reactions: reactions, blockedIds: Array(blocked)).map {
            ReactionChip(emoji: $0.emoji, count: Int($0.count), mine: $0.mine, people: $0.people, personIDs: $0.personIds)
        }
    }

    /// Is this sender blocked? (core's `fromBlocked`.)
    static func isBlocked(_ id: String?, in blocked: Set<String>) -> Bool {
        guard let id else { return false }
        return fromBlocked(senderId: id, blockedIds: Array(blocked))
    }
}

extension BlockedPeople {
    /// Does this chat count as unread for a badge? Not when all its unread messages are from blocked people (LIME-330): a chat marked unread by hand still does.
    static func countsAsUnread(_ conversation: Conversation, blocked: Set<String>) -> Bool {
        guard conversation.isUnread else { return false }
        if conversation.markedUnread || blocked.isEmpty || !conversation.isGroup || conversation.unread <= 0 { return true }
        let tail = conversation.messages.filter { !$0.isOwn && !$0.isSystem }.suffix(conversation.unread)
        guard !tail.isEmpty else { return true }
        return !tail.allSatisfy { isBlocked($0.senderID, in: blocked) }
    }
}

extension Message {
    /// This message with the blocked people's reactions left out (LIME-330).
    func hidingBlockedReactions(_ blocked: Set<String>) -> Message {
        guard !blocked.isEmpty, !reactions.isEmpty else { return self }
        var copy = self
        copy.reactions = BlockedPeople.visible(reactions, blocked: blocked)
        return copy
    }
}
