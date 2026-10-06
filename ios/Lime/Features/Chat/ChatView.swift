import SwiftUI

struct ChatView: View {
    let conversationID: Conversation.ID
    @Environment(ConversationStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @FocusState private var composerFocused: Bool

    var body: some View {
        if let conversation = store.conversation(conversationID) {
            content(conversation)
        }
    }

    private func content(_ conversation: Conversation) -> some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(rows(conversation)) { row in
                            switch row.kind {
                            case .day(let text):
                                Text(text)
                                    .font(Theme.caption.weight(.medium))
                                    .foregroundStyle(Theme.textSecondary)
                                    .padding(.vertical, 12)
                                    .accessibilityAddTraits(.isHeader)
                            case .message(let message, let showSender):
                                MessageBubble(message: message,
                                              sender: store.person(message.senderID, in: conversation),
                                              showSender: showSender && conversation.isGroup)
                                    .padding(.bottom, 8)
                            }
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 84)
                    .padding(.bottom, 8)
                }
                .accessibilityIdentifier("chat-scroll")
                .scrollDismissesKeyboard(.interactively)
                .defaultScrollAnchor(.bottom)
                .onChange(of: conversation.messages.count) {
                    withAnimation { proxy.scrollTo("bottom") }
                }
            }
        }
        .overlay(alignment: .top) { header(conversation) }
        .safeAreaInset(edge: .bottom) { composer(conversation) }
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: Header

    private func header(_ conversation: Conversation) -> some View {
        HStack(spacing: 8) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .frame(width: 48, height: 48)
                    .limeGlass()
            }
            .accessibilityLabel("Back")
            .accessibilityIdentifier("back-button")

            HStack(spacing: 8) {
                ConversationAvatar(conversation: conversation, size: 36)
                    .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 0) {
                    Text(conversation.title)
                        .font(Theme.secondary.weight(.semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    if conversation.isGroup {
                        Text(conversation.subtitle)
                            .font(Theme.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .frame(minHeight: 48)
            .limeGlass()
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("chat-title")

            Spacer(minLength: 0)

            HStack(spacing: 0) {
                glassIcon("magnifyingglass", label: "Search in chat")
                glassIcon("phone", label: "Call")
                glassIcon("ellipsis", label: "More")
            }
            .padding(.horizontal, 4)
            .limeGlass()
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }

    private func glassIcon(_ symbol: String, label: String) -> some View {
        Button { store.comingSoon(label) } label: {
            Image(systemName: symbol)
                .font(.system(size: 18))
                .foregroundStyle(Theme.text)
                .frame(width: 44, height: 48)
        }
        .accessibilityLabel(label)
    }

    // MARK: Composer

    private func composer(_ conversation: Conversation) -> some View {
        HStack(alignment: .bottom, spacing: 8) {
            Button { store.comingSoon("Attachments") } label: {
                Image(systemName: "plus")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.text)
                    .frame(width: 40, height: 44)
            }
            .accessibilityLabel("Add attachment")

            // `axis: .vertical` makes Return insert a new line rather than submit.
            TextField("Send message…", text: $draft, axis: .vertical)
                .lineLimit(1...5)
                .font(Theme.body)
                .foregroundStyle(Theme.text)
                .focused($composerFocused)
                .padding(.vertical, 10)
                .accessibilityIdentifier("composer-field")

            if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button { store.comingSoon("Voice messages") } label: {
                    Image(systemName: "mic")
                        .font(.system(size: 20))
                        .foregroundStyle(Theme.text)
                        .frame(width: 40, height: 44)
                }
                .accessibilityLabel("Voice message")
            } else {
                Button {
                    store.send(draft, in: conversation.id)
                    draft = ""
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.primaryInk)
                        .frame(width: 36, height: 36)
                        .background(Theme.primary, in: Circle())
                        .frame(width: 40, height: 44)
                }
                .accessibilityLabel("Send")
                .accessibilityIdentifier("send-button")
            }
        }
        .padding(.horizontal, 10)
        .limeGlass(in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }

    // MARK: Rows

    private struct Row: Identifiable {
        enum Kind { case day(String), message(Message, showSender: Bool) }
        let id: String
        let kind: Kind
    }

    private func rows(_ conversation: Conversation) -> [Row] {
        var result: [Row] = []
        var lastDay: Date?
        var lastSender: String??
        let cal = Calendar.current
        for message in conversation.messages {
            if lastDay == nil || !cal.isDate(lastDay!, inSameDayAs: message.date) {
                result.append(Row(id: "day-\(message.id)", kind: .day(MessageFormat.day(message.date))))
                lastSender = nil
            }
            lastDay = message.date
            let showSender = !message.isOwn && lastSender != .some(message.senderID)
            result.append(Row(id: message.id, kind: .message(message, showSender: showSender)))
            lastSender = .some(message.senderID)
        }
        return result
    }
}

struct MessageBubble: View {
    let message: Message
    let sender: Person?
    let showSender: Bool
    @ScaledMetric(relativeTo: .body) private var avatarSize: CGFloat = 36

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.isOwn { Spacer(minLength: 56) }
            if !message.isOwn, let sender {
                if showSender { AvatarView(person: sender, size: avatarSize) }
                else { Color.clear.frame(width: avatarSize, height: 1) }
            }
            VStack(alignment: message.isOwn ? .trailing : .leading, spacing: 4) {
                if showSender, let sender {
                    Text(sender.name)
                        .font(Theme.caption.weight(.medium))
                        .foregroundStyle(Theme.text)
                }
                Text(message.text)
                    .font(Theme.body)
                    .foregroundStyle(message.isOwn ? Theme.ownBubbleInk : Theme.text)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(message.isOwn ? Theme.ownBubble : Theme.bubbleOther,
                                in: RoundedRectangle(cornerRadius: Theme.bubbleRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.bubbleRadius, style: .continuous)
                            .strokeBorder(message.isOwn ? Color.clear : Theme.bubbleEdge, lineWidth: 0.5)
                    )
                    .accessibilityIdentifier(message.isOwn ? "own-bubble" : "other-bubble")
                Text(MessageFormat.clock(message.date))
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            if !message.isOwn { Spacer(minLength: 56) }
        }
    }
}
