import SwiftUI

/// Who a thread's replies answer, in one glance (like a quote): the author's avatar, "Replies · Name", and one line of what they wrote
/// (or a label for a picture, video, voice message or file). In the Replies screen it is a card under the title; above the composer
/// it reads "Reply to Name · quote" with an X that leaves Replies.
struct ReplyContext: View {
    let root: Message
    let conversation: Conversation?
    let compact: Bool
    var onClose: (() -> Void)?
    @Environment(ConversationStore.self) private var store

    private var author: Person? {
        guard let conversation else { return nil }
        return store.person(root.senderID, in: conversation)
    }
    private var name: String { root.isOwn ? "You" : (author?.name ?? "Someone") }

    /// One line of the root message.
    private var quote: String {
        if root.deleted { return "This message was deleted" }
        let words = messagePlainText(text: root.text).replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        if !words.isEmpty { return words }
        return AttachmentFormat.summary(root.attachments) ?? ""
    }

    var body: some View {
        HStack(spacing: 10) {
            if let author { AvatarView(person: author, size: compact ? 26 : 34) }
            else if root.isOwn { AvatarView(person: store.meProvider(), size: compact ? 26 : 34) }
            VStack(alignment: .leading, spacing: 1) {
                Text(compact ? "Reply to \(name)" : "Replies · \(name)")
                    .font(Theme.secondary.weight(.semibold)).foregroundStyle(Theme.text).lineLimit(1)
                    .accessibilityIdentifier("reply-context-title")
                if !quote.isEmpty {
                    Text(quote).font(Theme.caption).foregroundStyle(Theme.textSecondary).lineLimit(1)
                        .accessibilityIdentifier("reply-context-quote")
                }
            }
            Spacer(minLength: 4)
            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.textSecondary)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Leave Replies").accessibilityIdentifier("reply-context-close")
            }
        }
        .padding(.horizontal, 14).padding(.vertical, compact ? 6 : 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .limeGlass(in: RoundedRectangle(cornerRadius: compact ? 16 : 20, style: .continuous))
        .padding(.horizontal, 16).padding(.vertical, compact ? 2 : 6)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(compact ? "reply-context-strip" : "reply-context-card")
    }
}
