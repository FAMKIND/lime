import Foundation

/// A message that just arrived from someone else, ready to be announced.
struct IncomingMessage: Identifiable, Equatable, Sendable {
    let id: String
    let conversationID: String
    let conversationTitle: String
    /// Who wrote it: their id (for the avatar colour) and name.
    let senderID: String
    let senderName: String
    /// The words without Markdown (what a notification may show).
    let text: String
    /// When it is a reply in a thread: the message it answers.
    let threadRoot: String?
    let isGroup: Bool
    /// A stranger's first message: waits in Requests, so nothing of it is shown.
    let isRequest: Bool
    let date: Date
}

/// Which screen the person is looking at (the chat, or one thread in it).
struct ViewingTarget: Equatable, Sendable {
    let conversationID: String
    var threadRoot: String? = nil
}

/// How a new message is announced.
enum Presentation: Equatable, Sendable {
    /// Nothing: notifications are off, or this chat is muted.
    case none
    /// The message is on screen already: a subtle tick, no banner.
    case tick
    /// Another chat while Lime is open: a banner at the top, and the sound unless it is off.
    case banner(sound: Bool)
    /// Lime is in the background but still running: a local notification.
    case local(sound: Bool)
    /// Quiet (Do not disturb, or outside work hours): delivered silently and kept for a summary when the quiet ends.
    case held
}

/// What a local notification says.
struct NotificationContent: Equatable, Sendable {
    let title: String
    let body: String
    /// Groups a chat's notifications together.
    let threadIdentifier: String
    let conversationID: String
    let threadRoot: String?
    let messageID: String
    let sound: Bool
}

/// The rules, as pure functions so they can be tested without a phone.
enum NotificationPolicy {
    static func presentation(for message: IncomingMessage, enabled: Bool, muted: Bool, sound: NotificationSound,
                             appActive: Bool, viewing: ViewingTarget?, quiet: Bool = false) -> Presentation {
        guard enabled, !muted else { return .none }
        // Quiet hours hold everything (a message in the chat on screen still just ticks). Nothing here is marked urgent: the flag that
        // would break through is reserved for emergency mode, which users cannot send yet.
        if quiet, !(appActive && viewing?.conversationID == message.conversationID && viewing?.threadRoot == message.threadRoot) { return .held }
        let loud = sound != .none
        guard appActive else { return .local(sound: loud) }
        if let viewing, viewing.conversationID == message.conversationID {
            // A reply is on screen only in its own thread; a timeline message only in the chat itself.
            if viewing.threadRoot == message.threadRoot { return .tick }
        }
        return .banner(sound: loud)
    }

    /// The words of a banner or notification for the person's preview choice. A request never shows its
    /// words, whatever the choice (nobody has accepted that person yet).
    static func content(for message: IncomingMessage, preview: NotificationPreview, sound: Bool) -> NotificationContent {
        let title: String
        let body: String
        let reply = message.threadRoot != nil
        if message.isRequest {
            title = message.senderName
            body = "Wants to message you"
        } else {
            switch preview {
            case .hidden:
                title = "Lime"
                body = reply ? "New reply" : "New message"
            case .nameOnly:
                title = message.conversationTitle
                body = reply ? "New reply" : "New message"
            case .nameAndMessage:
                title = message.conversationTitle
                let words = shortened(message.text)
                let who = message.isGroup ? "\(message.senderName): " : ""
                body = (reply ? "Replied in a thread: " : "") + who + words
            }
        }
        return NotificationContent(title: title, body: body, threadIdentifier: message.conversationID,
                                   conversationID: message.conversationID, threadRoot: message.threadRoot,
                                   messageID: message.id, sound: sound)
    }

    /// One short line: whitespace folded, cut at about 140 characters.
    static func shortened(_ text: String, limit: Int = 140) -> String {
        let folded = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard folded.count > limit else { return folded }
        return folded.prefix(limit).trimmingCharacters(in: .whitespaces) + "…"
    }
}

/// Spots messages that arrived since the last look. The first look only learns what is already here,
/// so opening the app never announces old history.
struct ArrivalDetector {
    private var seen = Set<String>()
    private(set) var primed = false

    /// `candidates`: every message from someone else that is currently known.
    mutating func arrivals(among candidates: [IncomingMessage]) -> [IncomingMessage] {
        defer { primed = true; seen.formUnion(candidates.map(\.id)) }
        guard primed else { return [] }
        return candidates.filter { !seen.contains($0.id) }.sorted { $0.date < $1.date }
    }

    mutating func reset() { seen = []; primed = false }
}
