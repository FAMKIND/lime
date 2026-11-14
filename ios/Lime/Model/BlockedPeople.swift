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
        let fromOthers = timelineUnread(conversation, blocked: blocked) + visibleUnreadReplies(conversation, blocked: blocked)
        return conversation.markedUnread ? max(fromOthers, 1) : fromOthers
    }

    /// The unread replies in a chat's threads (core's count; they are not in the timeline) and how many of them a blocked person wrote (LIME-333).
    private static func replyUnread(_ conversation: Conversation) -> (total: Int, senders: [String]) {
        let threads = conversation.messages.compactMap(\.thread)
        return (threads.reduce(0) { $0 + $1.unread }, threads.flatMap(\.unreadSenders))
    }

    private static func visibleUnreadReplies(_ conversation: Conversation, blocked: Set<String>) -> Int {
        let replies = replyUnread(conversation)
        return max(0, replies.total - replies.senders.filter { isBlocked($0, in: blocked) }.count)
    }

    /// The unread messages in the timeline that are not a blocked person's: the newest incoming ones, as many as the chat's unread count less its unread replies.
    private static func timelineUnread(_ conversation: Conversation, blocked: Set<String>) -> Int {
        let count = max(0, conversation.unread - replyUnread(conversation).total)
        let tail = conversation.messages.filter { !$0.isOwn && !$0.isSystem }.suffix(count)
        return tail.filter { !isBlocked($0.senderID, in: blocked) }.count + max(0, count - tail.count)
    }

    /// "N comments" without the blocked people's (LIME-332): `total` is what core counted (published comments); the collapsed rows stay, only the count drops them.
    static func visibleCommentCount(total: Int, comments: [JamCommentInfo], blocked: Set<String>) -> Int {
        guard !blocked.isEmpty else { return total }
        let theirs = comments.filter { $0.state == "published" && isBlocked($0.author, in: blocked) }.count
        return max(0, total - theirs)
    }

    /// A post's numbers without the blocked people's (LIME-332, 333): comments, hearts and their faces; the "New comments" dot stays only if a published comment from
    /// someone else (not me, not blocked) exists. Core stops raising the dot for a blocked person's new comments; this also covers one that was already there.
    static func visibleCounts(_ counts: JamCountsInfo, comments: [JamCommentInfo], blocked: Set<String>, me: String) -> JamCountsInfo {
        guard !blocked.isEmpty else { return counts }
        var counts = counts
        counts.comments = UInt32(visibleCommentCount(total: Int(counts.comments), comments: comments, blocked: blocked))
        let theirHearts = counts.likers.filter { isBlocked($0, in: blocked) }.count
        counts.likers = counts.likers.filter { !isBlocked($0, in: blocked) }
        counts.likes = UInt32(max(0, Int(counts.likes) - theirHearts))
        if counts.unseen {
            counts.unseen = comments.contains { $0.state == "published" && $0.author != me && !isBlocked($0.author, in: blocked) }
        }
        return counts
    }

    /// Does this chat count as unread for a badge? Not when all its unread messages are from blocked people (LIME-330): a chat marked unread by hand still does.
    static func countsAsUnread(_ conversation: Conversation, blocked: Set<String>) -> Bool {
        guard conversation.isUnread else { return false }
        if conversation.markedUnread || blocked.isEmpty || !conversation.isGroup || conversation.unread <= 0 { return true }
        return timelineUnread(conversation, blocked: blocked) + visibleUnreadReplies(conversation, blocked: blocked) > 0
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
