import Foundation

/// One message that matches a search, ready to show.
struct MessageHit: Identifiable, Equatable, Sendable {
    var id: String { messageID }
    let messageID: String
    let conversationID: String
    /// The chat's title (the person's name, or the group's).
    let conversationTitle: String
    /// A few words around the match, with each matched word between `SearchText.startMark` and `endMark`.
    let marked: String
    let date: Date
    let fromMe: Bool
    /// When the message is a reply, the message it replies to: the hit opens that thread.
    var threadRoot: String? = nil

    /// The snippet for display: matched words bold, in the accent colour's weight.
    var snippet: AttributedString { SearchText.attributed(marked) }
}

/// Where tapping a search result goes: a chat, scrolled to (and briefly highlighting) one message.
struct ChatTarget: Hashable {
    let conversationID: String
    let messageID: String
    /// The words searched for, highlighted when the chat opens.
    var words: [String] = []
}

struct SearchResults: Equatable, Sendable {
    var chats: [Conversation] = []
    var messages: [MessageHit] = []
    var isEmpty: Bool { chats.isEmpty && messages.isEmpty }
}

/// The marker characters LimeCore puts around matched words, and what the app does with them. The
/// same word matching is used by the in-memory demo, so the screens behave alike without a database.
enum SearchText {
    static let startMark: Character = "\u{E000}"
    static let endMark: Character = "\u{E001}"

    /// The snippet as styled text: marks removed, the matched words bold.
    static func attributed(_ marked: String) -> AttributedString {
        var result = AttributedString()
        var bold = false
        var run = ""
        func flush() {
            guard !run.isEmpty else { return }
            var piece = AttributedString(run)
            if bold { piece.inlinePresentationIntent = .stronglyEmphasized }
            result.append(piece)
            run = ""
        }
        for character in marked {
            if character == startMark { flush(); bold = true }
            else if character == endMark { flush(); bold = false }
            else { run.append(character) }
        }
        flush()
        return result
    }

    /// The snippet with the marks removed.
    static func plain(_ marked: String) -> String {
        marked.filter { $0 != startMark && $0 != endMark }
    }

    /// The words typed, without punctuation, folded for comparing (case and diacritics ignored).
    static func words(_ text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    }

    /// True when every typed word is the start of some word of `text`.
    static func matches(_ text: String, query: String) -> Bool {
        let wanted = words(query)
        guard !wanted.isEmpty else { return false }
        let have = words(text)
        return wanted.allSatisfy { w in have.contains { $0.hasPrefix(w) } }
    }

    /// `text` with the first word that starts with each typed word wrapped in the marks (the demo's version of a snippet).
    static func mark(_ text: String, query: String) -> String {
        let wanted = words(query)
        var out = ""
        var word = ""
        func flushWord() {
            guard !word.isEmpty else { return }
            let folded = word.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            if wanted.contains(where: { folded.hasPrefix($0) }) { out += "\(startMark)\(word)\(endMark)" } else { out += word }
            word = ""
        }
        for character in text {
            if character.isLetter || character.isNumber { word.append(character) } else { flushWord(); out.append(character) }
        }
        flushWord()
        return out
    }
}
