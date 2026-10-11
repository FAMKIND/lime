import Foundation

/// The filters on the link list (LIME-124): what kind of chat, pinned, muted, a private label. All that are on apply together, and
/// with the All | Unread segment.
struct ChatFilter: Equatable {
    enum Kind: Equatable { case direct, group }
    var kind: Kind?
    var pinned = false
    var muted = false
    var label: String?

    /// How many filters are on (the number on the filter button).
    var activeCount: Int { (kind == nil ? 0 : 1) + (pinned ? 1 : 0) + (muted ? 1 : 0) + (label == nil ? 0 : 1) }
    var isOn: Bool { activeCount > 0 }

    func apply(_ chats: [Conversation], unreadOnly: Bool, isMuted: (String) -> Bool) -> [Conversation] {
        chats.filter { chat in
            if unreadOnly && !chat.isUnread { return false }
            switch kind {
            case .direct?: if chat.isGroup { return false }
            case .group?: if !chat.isGroup { return false }
            case nil: break
            }
            if pinned && !chat.isPinned { return false }
            if muted && !isMuted(chat.id) { return false }
            if let label, chat.isGroup || chat.members.first?.label != label { return false }
            return true
        }
    }

    /// The private labels in use on direct chats, sorted.
    static func labels(in chats: [Conversation]) -> [String] {
        Set(chats.filter { !$0.isGroup }.compactMap { $0.members.first?.label }.filter { !$0.isEmpty }).sorted()
    }
}

/// The filters on the Calls list: voice or video, incoming or outgoing.
struct CallFilter: Equatable {
    enum Direction: Equatable { case incoming, outgoing }
    var video: Bool?
    var direction: Direction?

    var activeCount: Int { (video == nil ? 0 : 1) + (direction == nil ? 0 : 1) }
    var isOn: Bool { activeCount > 0 }

    func apply(_ records: [CallRecord], missedOnly: Bool) -> [CallRecord] {
        records.filter { call in
            if missedOnly && !call.isMissedIncoming { return false }
            if let video, call.video != video { return false }
            switch direction {
            case .incoming?: if call.outgoing { return false }
            case .outgoing?: if !call.outgoing { return false }
            case nil: break
            }
            return true
        }
    }
}
