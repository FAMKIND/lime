import Foundation

/// A chat's day separators and messages, in order. `showAvatar` is true for the first of a run of
/// incoming messages from one sender (in DMs and groups alike).
struct ChatRow: Identifiable {
    enum Kind {
        case day(String)
        case message(Message, showAvatar: Bool)
    }

    let id: String
    let kind: Kind

    static func rows(for conversation: Conversation, calendar: Calendar = .current) -> [ChatRow] {
        var result: [ChatRow] = []
        var lastDay: Date?
        var lastSender: String??
        for message in conversation.messages {
            if lastDay == nil || !calendar.isDate(lastDay!, inSameDayAs: message.date) {
                result.append(ChatRow(id: "day-\(message.id)", kind: .day(MessageFormat.day(message.date))))
                lastSender = nil
            }
            lastDay = message.date
            let showAvatar = !message.isOwn && lastSender != .some(message.senderID)
            result.append(ChatRow(id: message.id, kind: .message(message, showAvatar: showAvatar)))
            lastSender = .some(message.senderID)
        }
        return result
    }
}
