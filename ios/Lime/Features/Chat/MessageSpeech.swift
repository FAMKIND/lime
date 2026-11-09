import Foundation

/// What VoiceOver says for one message as one element (LIME-130-3a): "<Sender or You>, <text or kind>, <time>, <edited>, <delivery state>,
/// <reactions>, <replies>". The pure part, so the words are tested without a screen.
enum MessageSpeech {
    /// `senderName` is the other person's name (nil for my own messages, who read as "You").
    static func label(for message: Message, senderName: String?, includeBody: Bool = true) -> String {
        var parts: [String] = [message.isOwn ? "You" : (senderName ?? "Someone")]
        if includeBody { parts.append(body(of: message)) }
        if !message.deleted {
            parts.append(MessageFormat.clock(message.date))
            if message.edited { parts.append("edited") }
            if message.isOwn, let state = stateWords(message.state) { parts.append(state) }
            if !message.reactions.isEmpty {
                let total = message.reactions.reduce(0) { $0 + $1.count }
                parts.append("\(total) \(total == 1 ? "reaction" : "reactions"): " + message.reactions.map { "\($0.emoji) \($0.count)\($0.mine ? " (you)" : "")" }.joined(separator: ", "))
            }
            if let thread = message.thread {
                parts.append("\(thread.replyCount) \(thread.replyCount == 1 ? "reply" : "replies")" + (thread.unread > 0 ? ", \(thread.unread) unread" : ""))
            }
        }
        return parts.joined(separator: ", ")
    }

    /// The words of the message, or what kind of thing it is.
    static func body(of message: Message) -> String {
        if message.deleted { return "This message was deleted" }
        if message.emergency != nil { return "Emergency status" }
        if let call = message.call { return (call.video ? "Video call" : "Call") + (call.duration > 0 ? ", \(MessageSpeech.duration(call.duration))" : "") }
        var pieces: [String] = []
        if message.forwarded { pieces.append("Forwarded") }
        let text = messagePlainText(text: message.text)
        if !text.isEmpty { pieces.append(text) }
        if !message.attachments.isEmpty { pieces.append(attachments(message.attachments)) }
        if let preview = message.linkPreview { pieces.append("Link: \(preview.title)") }
        return pieces.isEmpty ? "Message" : pieces.joined(separator: ", ")
    }

    /// "Photo", "3 photos", "Voice message", "File: report.pdf" …
    static func attachments(_ items: [AttachmentItem]) -> String {
        let images = items.filter { $0.kind == .image }
        var out: [String] = []
        if images.count == 1, let only = images.first { out.append(only.isSticker ? StickerPack.spokenName(forFileName: only.name) : (GIF.isGIF(mime: only.mime) ? "GIF" : "Photo")) }
        else if images.count > 1 { out.append("\(images.count) photos") }
        for item in items where item.kind != .image {
            switch item.kind {
            case .audio: out.append("Voice message")
            case .video: out.append("Video")
            default: out.append(item.name.isEmpty ? "File" : "File: \(item.name)")
            }
        }
        return out.joined(separator: ", ")
    }

    /// The delivery state as words (nil when it says nothing: received, or the quiet "sent" of an older message is still spoken).
    static func stateWords(_ state: DeliveryState) -> String? {
        switch state {
        case .sending: "sending"
        case .sent: "sent"
        case .failed: "not sent, retry available"
        case .undelivered: "not delivered, resend available"
        case .waiting, .passed, .offline: state.statusWords?.lowercased()
        case .received, .system: nil
        }
    }

    /// The web addresses in a message's text, for "Open link" actions (the text itself is not a set of separate stops with one stop per message).
    static func links(in text: String) -> [URL] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [] }
        let plain = messagePlainText(text: text)
        return detector.matches(in: plain, range: NSRange(plain.startIndex..., in: plain)).compactMap(\.url).filter { ["http", "https"].contains($0.scheme?.lowercased()) }
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return total >= 60 ? "\(total / 60) min \(total % 60) s" : "\(total) s"
    }
}
