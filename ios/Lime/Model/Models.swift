import Foundation

struct Person: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    /// Index into the avatar palette (the web app's `--lime-avatar-0…7`).
    let tone: Int

    var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        return parts.compactMap { $0.first }.map(String.init).joined().uppercased()
    }
}

/// Where one of my messages has got to. A received message is `.received`.
enum DeliveryState: String, Hashable, Sendable {
    case sending, sent, failed, received

    /// LimeCore's `local_state`; the older local-only states count as sent.
    init(localState: String) {
        self = DeliveryState(rawValue: localState) ?? .sent
    }
}

struct Message: Identifiable, Hashable, Sendable {
    let id: String
    /// `nil` means the message is mine.
    let senderID: String?
    let text: String
    let date: Date
    var state: DeliveryState = .received

    var isOwn: Bool { senderID == nil }
}

struct Conversation: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let members: [Person]
    var messages: [Message]
    var isPinned: Bool = false
    var unread: Int = 0
    /// A stranger's first message: it waits in Requests until accepted or blocked.
    var isRequest: Bool = false

    var isGroup: Bool { members.count > 1 }
    var subtitle: String { isGroup ? "\(members.count + 1) members" : "" }
    var lastMessage: Message? { messages.last }
}

// MARK: LimeCore records to the app's models

extension Message {
    init(_ item: MessageItem) {
        self.init(id: item.id, senderID: item.senderId, text: item.text,
                  date: Date(timeIntervalSince1970: Double(item.sentAt) / 1000),
                  state: item.senderId == nil ? DeliveryState(localState: item.localState) : .received)
    }
}

extension Conversation {
    init(_ summary: ConversationSummary, messages: [MessageItem]) {
        self.init(
            id: summary.id, title: summary.title,
            members: summary.members.map { Person(id: $0.id, name: $0.name, tone: Int($0.tone)) },
            messages: messages.map(Message.init),
            isPinned: summary.isPinned, unread: Int(summary.unread),
            isRequest: summary.requestState == "pending")
    }
}
