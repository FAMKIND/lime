import SwiftUI

struct ChatView: View {
    let conversationID: Conversation.ID
    /// Opened from a search result: scroll to this message and highlight it for a moment.
    var focusMessageID: String? = nil
    @Environment(ConversationStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var composerModel = RichComposerModel()
    @State private var pickingEmoji = false
    /// A link the person tapped in a message that is not https: shown to be confirmed first.
    @State private var pendingLink: URL?
    @State private var confirmingBlock = false
    // In-chat find (the header's magnifier): the matches, which one is current, and where to scroll.
    @State private var finding = false
    @State private var findQuery = ""
    @State private var findHits: [MessageHit] = []
    @State private var findIndex = 0
    @State private var highlightedID: String?
    @State private var scrollRequest: ScrollRequest?
    @FocusState private var findFocused: Bool

    struct ScrollRequest: Equatable { let id: String; let token = UUID() }

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
        .safeAreaInset(edge: .top) { if finding { findBar }  }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { titlePill(conversation) }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { startFinding() } label: { Image(systemName: "magnifyingglass") }
                    .accessibilityLabel("Search in chat")
                    .accessibilityIdentifier("chat-search-button")
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
        .overlay(alignment: .top) { if finding { findBar.padding(.top, 62) } }
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
                                          highlighted: highlightedID == message.id,
                                          onRetry: { Task { await store.resend(message.id) } })
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
            .environment(\.openURL, OpenURLAction { url in
                if MessageRender.opensWithoutAsking(url) { return .systemAction }
                pendingLink = url
                return .handled
            })
            .confirmationDialog("Open this link?", isPresented: Binding(get: { pendingLink != nil }, set: { if !$0 { pendingLink = nil } }), titleVisibility: .visible, presenting: pendingLink) { url in
                Button("Open \(url.scheme == "mailto" ? "mail" : "link")") { UIApplication.shared.open(url) }
                    .accessibilityIdentifier("link-open")
                Button("Cancel", role: .cancel) {}.accessibilityIdentifier("link-dialog-cancel")
            } message: { url in
                Text(url.absoluteString)
            }
            .sheet(item: $composerModel.linkRequest) { request in LinkSheet(request: request, composer: composerModel) }
            .scrollDismissesKeyboard(.interactively)
            .defaultScrollAnchor(.bottom)
            .refreshable { await store.syncNow() }
            .onChange(of: scrollRequest) { _, request in
                guard let request else { return }
                withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(request.id, anchor: .center) }
            }
            #if DEBUG
            .task {
                // Screenshots: the composer with some text selected, so the toolbar is up.
                guard store.demoCompose else { return }
                try? await Task.sleep(for: .milliseconds(600))
                guard let view = composerModel.textView else { return }
                view.attributedText = ComposerDocument.attributed(fromMarkdown: "Ok I have Unit 7 ready for review")
                composerModel.didEdit()
                view.becomeFirstResponder()
                view.selectedRange = (view.text as NSString).range(of: "Unit 7")
            }
            #endif
            #if DEBUG
            .task {
                // Screenshots: open with the find bar already typed.
                if let typed = store.demoQuery, focusMessageID == nil { startFinding(); findQuery = typed }
            }
            #endif
            .task {
                // Opened from a search result: land on the message, highlight it, then let it fade.
                guard let focusMessageID else { return }
                try? await Task.sleep(for: .milliseconds(250))
                highlightedID = focusMessageID
                scrollRequest = ScrollRequest(id: focusMessageID)
                try? await Task.sleep(for: .seconds(4))
                if highlightedID == focusMessageID && !finding { withAnimation { highlightedID = nil } }
            }
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

    // MARK: Find in this chat

    private func startFinding() {
        finding = true
        findFocused = true
    }

    private func stopFinding() {
        finding = false
        findQuery = ""
        findHits = []
        highlightedID = nil
    }

    private func step(by delta: Int) {
        let next = findIndex + delta
        guard findHits.indices.contains(next) else { return }
        findIndex = next
        show(findHits[next])
    }

    private func show(_ hit: MessageHit) {
        highlightedID = hit.messageID
        scrollRequest = ScrollRequest(id: hit.messageID)
    }

    /// The field, "3 of 12", the arrows (up is older) and Done.
    private var findBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.textSecondary)
            TextField("Find in chat", text: $findQuery)
                .font(Theme.body)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($findFocused)
                .accessibilityIdentifier("find-field")
                .task(id: findQuery) {
                    let wanted = findQuery
                    guard !wanted.trimmingCharacters(in: .whitespaces).isEmpty else { findHits = []; highlightedID = nil; return }
                    try? await Task.sleep(for: .milliseconds(150))
                    guard !Task.isCancelled else { return }
                    let hits = await store.findInChat(wanted, in: conversationID)
                    guard !Task.isCancelled else { return }
                    findHits = hits
                    findIndex = max(hits.count - 1, 0) // start at the newest match
                    if let last = hits.last { show(last) } else { highlightedID = nil }
                }
            Text(findStatus)
                .font(Theme.secondary).foregroundStyle(Theme.textSecondary).lineLimit(1)
                .accessibilityIdentifier("find-count")
            Button { step(by: -1) } label: { Image(systemName: "chevron.up").frame(width: 32, height: 36) }
                .disabled(findIndex <= 0 || findHits.isEmpty)
                .accessibilityLabel("Previous match").accessibilityIdentifier("find-up")
            Button { step(by: 1) } label: { Image(systemName: "chevron.down").frame(width: 32, height: 36) }
                .disabled(findIndex >= findHits.count - 1 || findHits.isEmpty)
                .accessibilityLabel("Next match").accessibilityIdentifier("find-down")
            Button("Done") { stopFinding() }
                .font(Theme.secondary.weight(.semibold))
                .accessibilityIdentifier("find-done")
        }
        .foregroundStyle(Theme.text)
        .padding(.horizontal, 14).frame(minHeight: 48)
        .limeGlass(in: Capsule())
        .padding(.horizontal, 12).padding(.vertical, 4)
    }

    /// "3 of 12", "No matches", or nothing before anything is typed.
    private var findStatus: String {
        if findQuery.trimmingCharacters(in: .whitespaces).isEmpty { return "" }
        if findHits.isEmpty { return "No matches" }
        return "\(findIndex + 1) of \(findHits.count)"
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
                Button { startFinding() } label: {
                    Image(systemName: "magnifyingglass").font(.system(size: 18)).foregroundStyle(Theme.text).frame(width: 44, height: 48)
                }
                .accessibilityLabel("Search in chat")
                .accessibilityIdentifier("chat-search-button")
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
        VStack(spacing: 8) {
            if conversation.keyChangePending { keyChangeBar(conversation) }
            if conversation.isRequest { requestBar(conversation) } else { composer(conversation) }
        }
    }

    /// The other person's security key changed (usually a new phone): nothing moves until it is accepted.
    private func keyChangeBar(_ conversation: Conversation) -> some View {
        VStack(spacing: 10) {
            Text("\(conversation.title)'s security key changed. This usually means they signed in on a new phone. Accept it to keep chatting.")
                .font(Theme.secondary)
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("key-change-note")
            Button { Task { await store.trustKey(conversation.id) } } label: {
                Text("Accept new key").font(Theme.title).foregroundStyle(Theme.accentInk)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(Theme.accent, in: Capsule())
            }
            .accessibilityIdentifier("key-change-accept")
        }
        .padding(16)
        .limeGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.horizontal, 12)
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

    /// The composer (design 04): the text above, and under it `+`, emoji and Aa on the left, mic or send on the right.
    /// Select text, or tap Aa, and the formatting toolbar appears above the keyboard.
    private func composer(_ conversation: Conversation) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                RichComposerField(model: composerModel)
                    .onAppear { composerModel.hasText = false }
                if !composerModel.hasText {
                    Text("Send message…").font(Theme.body).foregroundStyle(Theme.textSecondary)
                        .padding(.leading, 4).padding(.top, 8).allowsHitTesting(false).accessibilityHidden(true)
                }
            }
            HStack(spacing: 2) {
                composerButton("plus", label: "Add attachment", id: "composer-plus") { store.comingSoon("Attachments") }
                composerButton("face.smiling", label: "Emoji", id: "composer-emoji") { pickingEmoji = true }
                Button { composerModel.toggleToolbar() } label: {
                    Text("Aa").font(.system(size: 17, weight: .medium)).foregroundStyle(composerModel.toolbarVisible ? Theme.accentInk : Theme.text)
                        .frame(width: 44, height: 40)
                        .background(composerModel.toolbarVisible ? Theme.accent : Color.clear, in: Capsule())
                }
                .accessibilityLabel("Formatting").accessibilityIdentifier("composer-aa")
                .accessibilityAddTraits(composerModel.toolbarVisible ? [.isSelected] : [])
                Spacer(minLength: 0)
                if composerModel.canSend {
                    Button { sendDraft(in: conversation) } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Theme.primaryInk)
                            .frame(width: 36, height: 36)
                            .background(Theme.primary, in: Circle())
                            .frame(width: 44, height: 40)
                    }
                    .accessibilityLabel("Send")
                    .accessibilityIdentifier("send-button")
                } else {
                    composerButton("mic", label: "Voice message", id: "composer-mic") { store.comingSoon("Voice messages") }
                }
            }
        }
        .padding(.horizontal, 12).padding(.top, 2).padding(.bottom, 4)
        .limeGlass(in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
        .overlay { EmojiKeyboardField(isActive: $pickingEmoji) { composerModel.insertEmoji($0) }.frame(width: 1, height: 1).opacity(0.01) }
    }

    private func composerButton(_ symbol: String, label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 20)).foregroundStyle(Theme.text).frame(width: 44, height: 40)
        }
        .accessibilityLabel(label).accessibilityIdentifier(id)
    }

    /// Sends what is written, as Markdown (LimeCore writes it the one way), and empties the composer.
    private func sendDraft(in conversation: Conversation) {
        let markdown = composerModel.markdown()
        guard !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        store.send(markdown, in: conversation.id)
        composerModel.clear()
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
    /// The message a search or find landed on.
    var highlighted: Bool = false
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
                FormattedMessageText(markdown: message.text, ink: message.isOwn ? Theme.ownBubbleInk : Theme.text)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(message.isOwn ? Theme.ownBubble : Theme.bubbleOther,
                                in: RoundedRectangle(cornerRadius: Theme.bubbleRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.bubbleRadius, style: .continuous)
                            .strokeBorder(message.isOwn ? Color.clear : Theme.bubbleEdge, lineWidth: 0.5)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.bubbleRadius, style: .continuous)
                            .strokeBorder(Theme.accent, lineWidth: highlighted ? 3 : 0)
                    )
                    .animation(.easeInOut(duration: 0.2), value: highlighted)
                    .accessibilityIdentifier(message.isOwn ? "own-bubble" : "other-bubble")
                    .overlay(alignment: .topLeading) {
                        // For assistive tools and UI tests: which message a search or find landed on.
                        if highlighted { Color.clear.frame(width: 1, height: 1).accessibilityIdentifier("match-marker-\(message.id)") }
                    }
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
                        case .undelivered:
                            Button("· Not delivered. Tap to resend", action: onRetry)
                                .foregroundStyle(Color.red)
                                .accessibilityIdentifier("delivery-undelivered")
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
