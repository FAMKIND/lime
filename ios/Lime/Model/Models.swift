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

struct Message: Identifiable, Hashable, Sendable {
    let id: String
    /// `nil` means the message is mine.
    let senderID: String?
    let text: String
    let date: Date

    var isOwn: Bool { senderID == nil }
}

struct Conversation: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let members: [Person]
    var messages: [Message]
    var isPinned: Bool = false
    var unread: Int = 0

    var isGroup: Bool { members.count > 1 }
    var subtitle: String { isGroup ? "\(members.count + 1) members" : "" }
    var lastMessage: Message? { messages.last }
}
