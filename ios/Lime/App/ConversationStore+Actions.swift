import Foundation
import SwiftUI
import UIKit

/// Message actions (LIME-105): reactions, edit, copy and delete.
extension ConversationStore {
    /// The six emoji of the quick row (the "+" opens every emoji).
    static let quickReactions = ["👍", "❤️", "😂", "😮", "😢", "🙏"]

    /// Puts my emoji on a message, or takes it off when it is already mine.
    func toggleReaction(_ emoji: String, on message: Message, in conversationID: Conversation.ID) async {
        let on = !(message.reactions.first { $0.emoji == emoji }?.mine ?? false)
        #if DEBUG
        if isDemo { demoReact(emoji, on: on, messageID: message.id); return }
        #endif
        guard let core else { return }
        try? await Task.detached(priority: .userInitiated) {
            try core.react(conversationId: conversationID, messageId: message.id, emoji: emoji, on: on)
        }.value
        await reload()
        Task { await deliverNow() }
    }

    func editMessage(_ message: Message, to text: String, in conversationID: Conversation.ID) async -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !message.attachments.isEmpty else { return false }
        #if DEBUG
        if isDemo { demoEdit(message.id, to: trimmed); return true }
        #endif
        guard let core else { return false }
        let done = (try? await Task.detached(priority: .userInitiated) {
            try core.editMessage(conversationId: conversationID, messageId: message.id, text: trimmed)
        }.value) != nil
        await reload()
        Task { await deliverNow() }
        return done
    }

    func deleteMessages(_ ids: [Message.ID], for everyone: Bool, in conversationID: Conversation.ID) async {
        #if DEBUG
        if isDemo { for id in ids { demoDelete(id, everyone: everyone) }; return }
        #endif
        guard let core else { return }
        for id in ids {
            try? await Task.detached(priority: .userInitiated) {
                if everyone { try core.deleteMessageForEveryone(conversationId: conversationID, messageId: id) }
                else { try core.deleteMessageForMe(conversationId: conversationID, messageId: id) }
            }.value
        }
        await reload()
        Task { await deliverNow() }
    }

    /// Copies a message: its plain words, and its formatting as rich text where the place you paste it takes that.
    func copyToPasteboard(_ message: Message) {
        let plain = messagePlainText(text: message.text)
        var item: [String: Any] = ["public.utf8-plain-text": plain]
        if let rich = try? AttributedString(markdown: message.text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)),
           let rtf = try? NSAttributedString(rich).data(from: NSRange(location: 0, length: NSAttributedString(rich).length),
                                                           documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]) {
            item["public.rtf"] = rtf
        }
        UIPasteboard.general.setItems([item])
    }

    /// Where a message is: in the main timeline or in a thread (so an action reaches the right list).
    func conversationID(of message: Message.ID) -> Conversation.ID? {
        conversations.first { c in c.messages.contains { $0.id == message } }?.id
            ?? threads.first { $0.value.contains { $0.id == message } }.flatMap { root in
                conversations.first { c in c.messages.contains { $0.id == root.key } }?.id
            }
    }
}

#if DEBUG
extension ConversationStore {
    private func mutate(_ id: Message.ID, _ change: (inout Message) -> Void) {
        for c in conversations.indices {
            if let m = conversations[c].messages.firstIndex(where: { $0.id == id }) { change(&conversations[c].messages[m]) }
            if let l = conversations[c].latest, l.id == id { var copy = l; change(&copy); conversations[c].latest = copy }
        }
        for root in threads.keys {
            if let m = threads[root]?.firstIndex(where: { $0.id == id }) { change(&threads[root]![m]) }
            if let m = demoThreads[root]?.firstIndex(where: { $0.id == id }) { change(&demoThreads[root]![m]) }
        }
    }

    func demoReact(_ emoji: String, on: Bool, messageID: Message.ID) {
        mutate(messageID) { message in
            var chips = message.reactions
            if let i = chips.firstIndex(where: { $0.emoji == emoji }) {
                let chip = chips[i]
                let people = on ? ["You"] + chip.people.filter { $0 != "You" } : chip.people.filter { $0 != "You" }
                if people.isEmpty { chips.remove(at: i) } else { chips[i] = ReactionChip(emoji: emoji, count: people.count, mine: on, people: people) }
            } else if on {
                chips.append(ReactionChip(emoji: emoji, count: 1, mine: true, people: ["You"]))
            }
            message.reactions = chips
        }
        // A reaction is the newest thing in the chat's row ("You reacted 👍 to …"); it changes no unread count.
        if on, let c = conversations.firstIndex(where: { $0.messages.contains { $0.id == messageID } }),
           let target = conversations[c].messages.first(where: { $0.id == messageID }) {
            conversations[c].lastReaction = ReactionPreview(emoji: emoji, reactorName: nil, messageID: messageID, text: messagePlainText(text: target.text))
            conversations[c].activityAt = Date()
        }
    }

    func demoEdit(_ id: Message.ID, to text: String) { mutate(id) { $0.text = text; $0.edited = true } }

    func demoDelete(_ id: Message.ID, everyone: Bool) {
        if everyone {
            mutate(id) { $0.deleted = true; $0.text = ""; $0.attachments = []; $0.reactions = []; $0.edited = false }
        } else {
            for c in conversations.indices { conversations[c].messages.removeAll { $0.id == id } }
            for root in threads.keys { threads[root]?.removeAll { $0.id == id }; demoThreads[root]?.removeAll { $0.id == id } }
        }
    }
}
#endif
