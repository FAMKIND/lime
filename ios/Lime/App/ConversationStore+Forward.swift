import Foundation
import SwiftUI
import UIKit

/// Forwarding, my own chat and link cards (LIME-106).
extension ConversationStore {
    /// At most this many chats per forward.
    static let maxForwardChats = 5

    /// The chats a message can be forwarded to: every chat and group I am in (not requests), mine included.
    var forwardTargets: [Conversation] { conversations.filter { !$0.isRequest } }

    /// Forwards messages to up to five chats. Each forward is a new message labelled "Forwarded"; files are shared by reference.
    @discardableResult
    func forward(_ ids: [Message.ID], to targets: [Conversation.ID]) async -> Bool {
        guard !ids.isEmpty, !targets.isEmpty, targets.count <= Self.maxForwardChats else { return false }
        #if DEBUG
        if isDemo { demoForward(ids, to: targets); return true }
        #endif
        guard let core else { return false }
        let done = (try? await Task.detached(priority: .userInitiated) {
            try core.forwardMessages(messageIds: ids, toConversations: targets)
        }.value) != nil
        await reload()
        Task { await deliverNow() }
        return done
    }

    /// My own chat: it is a chat with myself under my own name, kept on this phone. Created the first time.
    func openSelfChat() async {
        let me = meProvider()
        #if DEBUG
        if isDemo { demoSelfChat(me); path.append("dm:\(me.id)"); return }
        #endif
        guard let core else { return }
        let id = try? await Task.detached(priority: .userInitiated) { try core.ensureSelfChat(name: me.name) }.value
        await reload()
        if let id { path.append(id) }
    }

    /// The id my own chat has (whether or not it exists yet).
    var selfChatID: Conversation.ID { "dm:\(meProvider().id)" }

    // MARK: Sending with a link card

    func sendNow(_ text: String, preview: OutgoingPreview, in id: Conversation.ID, replyTo root: String? = nil) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        #if DEBUG
        if isDemo { demoSendWithPreview(trimmed, preview: preview, in: id, replyTo: root); return }
        #endif
        guard let core else { return }
        let item = try? await Task.detached(priority: .userInitiated) {
            try core.queueTextWithPreview(conversationId: id, text: trimmed, replyTo: root, preview: preview)
        }.value
        guard item != nil else { return }
        await reload()
        if root != nil { await openThread(root!) }
        await deliverNow()
    }
}

#if DEBUG
extension ConversationStore {
    private func demoMessage(_ id: Message.ID) -> Message? {
        for conversation in conversations { if let m = conversation.messages.first(where: { $0.id == id }) { return m } }
        for list in threads.values { if let m = list.first(where: { $0.id == id }) { return m } }
        return nil
    }

    func demoForward(_ ids: [Message.ID], to targets: [Conversation.ID]) {
        let sources = ids.compactMap(demoMessage).filter { !$0.deleted && !$0.isSystem }
        for target in targets {
            guard let index = conversations.firstIndex(where: { $0.id == target }) else { continue }
            for source in sources {
                var copy = Message(id: UUID().uuidString, senderID: nil, text: source.text, date: Date(), state: .sent)
                copy.attachments = source.attachments
                copy.linkPreview = source.linkPreview
                copy.forwarded = true
                conversations[index].messages.append(copy)
            }
        }
    }

    func demoSelfChat(_ me: Person) {
        let id = "dm:\(me.id)"
        guard !conversations.contains(where: { $0.id == id }) else { return }
        conversations.insert(Conversation(id: id, title: me.name, members: [me], messages: []), at: 0)
    }

    func demoSendWithPreview(_ text: String, preview: OutgoingPreview, in id: Conversation.ID, replyTo root: String?) {
        var message = Message(id: UUID().uuidString, senderID: nil, text: text, date: Date(), state: .sent)
        var image: AttachmentItem?
        if !preview.image.isEmpty {
            let attachmentID = UUID().uuidString.lowercased()
            demoAttachmentData[attachmentID] = preview.image
            image = AttachmentItem(id: attachmentID, mime: "image/jpeg", name: "", size: Int64(preview.image.count), width: Int(preview.imageWidth ?? 600), height: Int(preview.imageHeight ?? 315), thumb: Data(), downloaded: true)
        }
        message.linkPreview = LinkPreviewItem(url: preview.url, title: preview.title, site: preview.site, image: image)
        if let root {
            demoThreads[root, default: []].append(message)
            threads[root] = demoThreads[root]
        } else if let index = conversations.firstIndex(where: { $0.id == id }) {
            conversations[index].messages.append(message)
        }
    }
}
#endif
