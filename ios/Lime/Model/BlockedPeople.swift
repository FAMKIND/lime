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
    /// The unread messages in a chat without the blocked people's (LIME-332): the numbers Back and a Messages row show. In a group the unread ones are the newest
    /// incoming messages (as many as the chat's unread count, which can also count replies that are not in the timeline: those are kept); a chat marked unread by hand
    /// still counts 1, as a row always did.
    static func unreadMessages(_ conversation: Conversation, blocked: Set<String>) -> Int {
        let base = conversation.unreadCount
        guard conversation.unread > 0, conversation.isGroup, !blocked.isEmpty else { return base }
        let tail = conversation.messages.filter { !$0.isOwn && !$0.isSystem }.suffix(conversation.unread)
        let fromOthers = tail.filter { !isBlocked($0.senderID, in: blocked) }.count + max(0, conversation.unread - tail.count)
        return conversation.markedUnread ? max(fromOthers, 1) : fromOthers
    }

    /// "N comments" without the blocked people's (LIME-332): `total` is what core counted (published comments); the collapsed rows stay, only the count drops them.
    static func visibleCommentCount(total: Int, comments: [JamCommentInfo], blocked: Set<String>) -> Int {
        guard !blocked.isEmpty else { return total }
        let theirs = comments.filter { $0.state == "published" && isBlocked($0.author, in: blocked) }.count
        return max(0, total - theirs)
    }

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
