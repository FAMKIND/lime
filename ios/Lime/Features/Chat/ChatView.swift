import SwiftUI

struct ChatView: View {
    let conversationID: Conversation.ID
    @Environment(ConversationStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @State private var confirmingBlock = false
    @FocusState private var composerFocused: Bool

    var body: some View {
        if let conversation = store.conversation(conversationID) {
            if #available(iOS 26, *) {
                nativeContent(conversation)
            } else {
                legacyContent(conversation)
            }
        }
    }

    // MARK: iOS 26+: system back button, toolbar and scroll edge effect (as in Apple Messages)

    @available(iOS 26, *)
    private func nativeContent(_ conversation: Conversation) -> some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()
            messageScroll(conversation, top: 8)
                .scrollEdgeEffectStyle(.soft, for: .top)
                .scrollEdgeEffectStyle(.soft, for: .bottom)
        }
        .safeAreaBar(edge: .bottom) { bottomBar(conversation) }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { titlePill(conversation) }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { store.comingSoon("Search in chat") } label: { Image(systemName: "magnifyingglass") }
                    .accessibilityLabel("Search in chat")
                Button { store.comingSoon("Call") } label: { Image(systemName: "phone") }
                    .accessibilityLabel("Call")
                Button { store.comingSoon("More") } label: { Image(systemName: "ellipsis") }
                    .accessibilityLabel("More")
            }
        }
    }

    // MARK: iOS 17-25: custom glass header and a subtle top veil

    private func legacyContent(_ conversation: Conversation) -> some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()
            messageScroll(conversation, top: 84)
        }
        .overlay(alignment: .top) { TopFade() }
        .overlay(alignment: .top) { header(conversation) }
        .safeAreaInset(edge: .bottom) { bottomBar(conversation) }
        .toolbar(.hidden, for: .navigationBar)
        .swipeBackEnabled()
    }

    // MARK: Shared

    private func messageScroll(_ conversation: Conversation, top: CGFloat) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                let lastOwnID = conversation.messages.last(where: \.isOwn)?.id
                LazyVStack(spacing: 0) {
                    ForEach(ChatRow.rows(for: conversation)) { row in
                        switch row.kind {
                        case .day(let text):
                            Text(text)
                                .font(Theme.caption.weight(.medium))
                                .foregroundStyle(Theme.textSecondary)
                                .padding(.vertical, 12)
                                .accessibilityAddTraits(.isHeader)
                        case .message(let message, let showAvatar):
                            MessageBubble(message: message,
                                          sender: store.person(message.senderID, in: conversation),
                                          showAvatar: showAvatar,
                                          showName: showAvatar && conversation.isGroup,
                                          showState: message.isOwn && (message.state != .sent || message.id == lastOwnID),
                                          onRetry: { Task { await store.deliverNow() } })
                                .padding(.bottom, 8)
                        }
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 16)
                .padding(.top, top)
                .padding(.bottom, 8)
            }
            .accessibilityIdentifier("chat-scroll")
            .scrollDismissesKeyboard(.interactively)
            .defaultScrollAnchor(.bottom)
            .refreshable { await store.syncNow() }
            .onChange(of: conversation.messages.count) {
                withAnimation { proxy.scrollTo("bottom") }
                // A message that arrives while the chat is open is read.
                Task { await store.markRead(conversationID) }
            }
            .task { await store.markRead(conversationID) }
        }
    }

    private func titlePill(_ conversation: Conversation) -> some View {
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
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("chat-title")
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

            titlePill(conversation)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .frame(minHeight: 48)
            .limeGlass()

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

    // MARK: Bottom: the composer, or Accept / Block for a request

    @ViewBuilder
    private func bottomBar(_ conversation: Conversation) -> some View {
        if conversation.isRequest { requestBar(conversation) } else { composer(conversation) }
    }

    private func requestBar(_ conversation: Conversation) -> some View {
        VStack(spacing: 12) {
            Text("\(conversation.title) isn't in your chats yet. Accept to reply.")
                .font(Theme.secondary)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("request-note")
            HStack(spacing: 12) {
                Button { confirmingBlock = true } label: {
                    Text("Block").font(Theme.title).foregroundStyle(Theme.text)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Theme.surface, in: Capsule())
                }
                .accessibilityIdentifier("request-block")
                Button { Task { await store.accept(conversation.id) } } label: {
                    Text("Accept").font(Theme.title).foregroundStyle(Theme.accentInk)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Theme.accent, in: Capsule())
                }
                .accessibilityIdentifier("request-accept")
            }
        }
        .padding(16)
        .limeGlass(in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
        .confirmationDialog("Block \(conversation.title)?", isPresented: $confirmingBlock, titleVisibility: .visible) {
            Button("Block", role: .destructive) {
                Task {
                    await store.block(conversation.id)
                    store.path = NavigationPath()
                }
            }
            .accessibilityIdentifier("request-block-confirm")
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Their new messages won't be shown on this phone.")
        }
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
}

struct MessageBubble: View {
    let message: Message
    let sender: Person?
    let showAvatar: Bool
    /// Sender names appear above the bubble in groups only; a DM's title already names the person.
    let showName: Bool
    /// Own messages say "Sending…" or "Sent" (the last one always; others only while unsettled).
    var showState: Bool = false
    var onRetry: () -> Void = {}
    @ScaledMetric(relativeTo: .body) private var avatarSize: CGFloat = 36

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.isOwn { Spacer(minLength: 56) }
            if !message.isOwn, let sender {
                if showAvatar { AvatarView(person: sender, size: avatarSize) }
                else { Color.clear.frame(width: avatarSize, height: 1) }
            }
            VStack(alignment: message.isOwn ? .trailing : .leading, spacing: 4) {
                if showName, let sender {
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
                HStack(spacing: 4) {
                    Text(MessageFormat.clock(message.date))
                    if showState {
                        switch message.state {
                        case .sending: Text("· Sending…").accessibilityIdentifier("delivery-sending")
                        case .sent: Text("· Sent").accessibilityIdentifier("delivery-sent")
                        case .failed:
                            Button("· Not sent. Tap to retry", action: onRetry)
                                .foregroundStyle(Color.red)
                                .accessibilityIdentifier("delivery-failed")
                        case .received: EmptyView()
                        }
                    }
                }
                .font(Theme.caption)
                .foregroundStyle(Theme.textSecondary)
            }
            if !message.isOwn { Spacer(minLength: 56) }
        }
    }
}
