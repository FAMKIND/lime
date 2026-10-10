import Foundation

struct Person: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    /// Index into the avatar palette (the web app's `--lime-avatar-0…7`).
    let tone: Int
    /// My private label for this person ("Grade 4 · Lincoln"): shown beside their name, only on this phone.
    var label: String? = nil

    var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        return parts.compactMap { $0.first }.map(String.init).joined().uppercased()
    }
}

/// Where one of my messages has got to. A received message is `.received`.
enum DeliveryState: String, Hashable, Sendable {
    case sending, sent, failed, undelivered, received
    /// A line of the timeline about the group itself ("Jean added Lee"), not a message.
    case system

    /// LimeCore's `local_state`; the older local-only states count as sent.
    init(localState: String) {
        self = DeliveryState(rawValue: localState) ?? .sent
    }
}

extension Person {
    /// A person's colour comes from their user id alone, the same on every screen and every phone.
    init(id: String, name: String) {
        self.init(id: id, name: name, tone: AvatarTone.tone(for: id))
    }
}

struct Message: Identifiable, Hashable, Sendable {
    let id: String
    /// `nil` means the message is mine.
    let senderID: String?
    var text: String
    let date: Date
    var state: DeliveryState = .received
    /// Pictures and files that came with the message (LIME-98c).
    var attachments: [AttachmentItem] = []
    /// Its text was edited (only the latest text is kept), or it was deleted for everyone (only its place remains).
    var edited = false
    var deleted = false
    /// The emoji reactions on it.
    var reactions: [ReactionChip] = []
    /// Forwarded from another chat (the original sender is never shown).
    var forwarded = false
    /// The link card it carries (built on the sender's phone).
    var linkPreview: LinkPreviewItem?
    /// For a reply: the message it answers.
    var threadRoot: String?
    /// When other messages reply to this one: how many, the newest, who, and what is unread.
    var thread: ThreadInfo?

    var isOwn: Bool { senderID == nil }
    /// Edit and Delete for everyone are offered on my own sent messages for a day.
    static let editWindow: TimeInterval = 24 * 3600
    func canEdit(now: Date = Date()) -> Bool {
        isOwn && !deleted && (state == .sent || state == .sending || state == .failed) && !isSystem && now.timeIntervalSince(date) <= Self.editWindow
    }
    func canDeleteForEveryone(now: Date = Date()) -> Bool {
        isOwn && !isSystem && now.timeIntervalSince(date) <= Self.editWindow && (state == .sent || state == .sending || state == .failed)
    }
    var isSystem: Bool { state == .system }
}

/// "Jean reacted ❤️ to “True that”" in a Messages row.
struct ReactionPreview: Hashable, Sendable {
    let emoji: String
    /// `nil` when it was me.
    let reactorName: String?
    let messageID: String
    let text: String
}

/// A link card under a message: the page's title and site, and a picture (an encrypted attachment).
struct LinkPreviewItem: Hashable, Sendable {
    let url: String
    let title: String
    let site: String
    var image: AttachmentItem?
}

/// One emoji under a message: how many people used it, whether I did, and who.
struct ReactionChip: Hashable, Sendable, Identifiable {
    let emoji: String
    let count: Int
    let mine: Bool
    let people: [String]
    var id: String { emoji }
}

/// What a message with replies shows under its bubble ("3 replies · 8:20 AM").
struct ThreadInfo: Hashable, Sendable {
    let replyCount: Int
    let lastReplyAt: Date
    /// Up to three people who replied, the newest first.
    let repliers: [Person]
    /// Replies from others not yet seen in the thread.
    let unread: Int

    /// `me` is how the app shows the signed-in person (LimeCore calls them "me").
    init(_ summary: ThreadSummary, me: Person) {
        replyCount = Int(summary.replyCount)
        lastReplyAt = Date(timeIntervalSince1970: Double(summary.lastReplyAt) / 1000)
        repliers = summary.repliers.map { $0.id == "me" ? me : Person(id: $0.id, name: $0.name, tone: Int($0.tone)) }
        unread = Int(summary.unread)
    }

    init(replyCount: Int, lastReplyAt: Date, repliers: [Person], unread: Int) {
        self.replyCount = replyCount
        self.lastReplyAt = lastReplyAt
        self.repliers = repliers
        self.unread = unread
    }

    /// "1 reply · 6:35 PM", or the date instead of the time when the last reply was not today.
    var summaryText: String { summary(now: Date()) }

    func summary(now: Date, calendar: Calendar = .current) -> String {
        let stamp = calendar.isDate(lastReplyAt, inSameDayAs: now) ? MessageFormat.clock(lastReplyAt) : lastReplyAt.formatted(.dateTime.month(.abbreviated).day())
        return "\(replyCount) \(replyCount == 1 ? "reply" : "replies") · \(stamp)"
    }
}

/// Where tapping a group's header goes: its details.
struct GroupTarget: Hashable {
    let conversationID: String
}

/// Where tapping a thread (or a search hit inside one) goes: the thread of one message, optionally landing on a reply.
struct ThreadTarget: Hashable {
    let conversationID: String
    let rootID: String
    var focusMessageID: String? = nil
    var words: [String] = []
}

struct Conversation: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    var members: [Person]
    var messages: [Message]
    var isPinned: Bool = false
    var unread: Int = 0
    /// A stranger's first message: it waits in Requests until accepted or blocked.
    var isRequest: Bool = false
    /// The other person's security key changed: accept it to keep chatting.
    var keyChangePending: Bool = false
    /// Their key was confirmed in person (a scanned QR code matched).
    var verified: Bool = false
    /// When they were verified in person.
    var verifiedAt: Date?
    /// A group chat (even one with a single other person left).
    var isGroupChat: Bool = false
    /// A group's emoji avatar.
    var emoji: String?
    /// The newest thing in the conversation, a reply in a thread included (the main timeline is `messages`).
    var latest: Message?
    /// `latest` is a reply.
    var latestIsReply = false
    /// I marked it unread by hand.
    var markedUnread = false
    /// The newest thing is a reaction (shown in the Messages preview; it changes no unread count).
    var lastReaction: ReactionPreview?
    /// When the newest thing happened (a reaction counts): what the row's time shows.
    var activityAt: Date?

    var isGroup: Bool { isGroupChat || members.count > 1 }
    var subtitle: String { isGroup ? "\(members.count + 1) members" : "" }
    var lastMessage: Message? { latest ?? messages.last }
    /// Shows the unread dot: something new, or marked unread by hand.
    var isUnread: Bool { unread > 0 || markedUnread }
}

// MARK: LimeCore records to the app's models

extension Message {
    init(_ item: MessageItem) {
        self.init(id: item.id, senderID: item.senderId, text: item.text,
                  date: Date(timeIntervalSince1970: Double(item.sentAt) / 1000),
                  state: item.localState == "system" ? .system
                      : (item.senderId == nil ? DeliveryState(localState: item.localState) : .received))
        attachments = item.attachments.map(AttachmentItem.init)
        edited = item.edited
        deleted = item.deleted
        reactions = item.reactions.map { ReactionChip(emoji: $0.emoji, count: Int($0.count), mine: $0.mine, people: $0.people) }
        forwarded = item.forwarded
        threadRoot = item.threadRoot
        linkPreview = item.linkPreview.map { LinkPreviewItem(url: $0.url, title: $0.title, site: $0.site, image: $0.image.map(AttachmentItem.init)) }
    }
}

extension Conversation {
    init(_ summary: ConversationSummary, messages: [MessageItem]) {
        self.init(
            id: summary.id, title: summary.title,
            members: summary.members.map { Person(id: $0.id, name: $0.name, tone: Int($0.tone), label: $0.label) },
            messages: messages.map(Message.init),
            isPinned: summary.isPinned, unread: Int(summary.unread),
            isRequest: summary.requestState == "pending", keyChangePending: summary.keyChangePending, verified: summary.verified,
            verifiedAt: summary.verifiedAt.map { Date(timeIntervalSince1970: Double($0) / 1000) },
            isGroupChat: summary.isGroup, emoji: summary.groupEmoji,
            latest: summary.lastMessage.map(Message.init), latestIsReply: summary.lastIsReply, markedUnread: summary.markedUnread,
            lastReaction: summary.lastReaction.map { ReactionPreview(emoji: $0.emoji, reactorName: $0.reactorId == nil ? nil : $0.reactorName, messageID: $0.messageId, text: $0.text) },
            activityAt: summary.activityAt > 0 ? Date(timeIntervalSince1970: Double(summary.activityAt) / 1000) : nil)
    }
}

/// The one place a person's avatar colour is worked out: from their user id, with the same rule
/// LimeCore uses when it names a conversation's people (so a search result, a chat header, Messages
/// and Requests all agree, on every phone). `String.hashValue` would not do: Swift randomises it per launch.
enum AvatarTone {
    nonisolated static func tone(for id: String) -> Int {
        var hash: UInt32 = 0
        for byte in id.utf8 { hash = hash &* 31 &+ UInt32(byte) }
        return Int(hash % 8)
    }
}
