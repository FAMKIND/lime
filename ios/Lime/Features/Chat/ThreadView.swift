import SwiftUI

/// A thread (design 04): the message it hangs from at the top, then its replies, then its own composer
/// (with formatting). New replies arrive live. Replies are not in the main chat.
struct ThreadView: View {
    let target: ThreadTarget
    @Environment(NotificationCoordinator.self) private var notifications
    @Environment(ConversationStore.self) private var store
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.dismiss) private var dismiss
    @State private var composerModel = RichComposerModel()
    @State private var highlightedID: String?
    @State private var scrollRequest: UUID?
    // The Replies screen's own find (its magnifier): the matches in this thread, which one is current.
    @State private var finding = false
    @State private var findQuery = ""
    @State private var findHits: [MessageHit] = []
    @State private var findIndex = 0
    @State private var findScroll: String?
    @FocusState private var findFocused: Bool
    @State private var actions = MessageActionsState()
    @State private var selection: Set<Message.ID>?
    /// How many of the newest replies are laid out (LIME-173); a thread rarely has more, and older ones come with the button under the root.
    @State private var replyWindow = ThreadWindow.first

    private var messages: [Message] { store.threads[target.rootID] ?? [] }

    /// Where the screen rests when it opens (and after a turn to landscape): the newest reply, or with none the first line of the root message.
    private func settle(_ proxy: ScrollViewProxy) {
        if messages.count > 1 {
            proxy.scrollTo("bottom", anchor: .bottom)
        } else if let root = messages.first {
            proxy.scrollTo(root.id, anchor: .top)
        }
    }

    /// Scrolls to a message (a search hit, a find match): an older reply outside the window brings the window out to it first.
    private func reveal(_ id: String, proxy: ScrollViewProxy) {
        if let index = messages.dropFirst().firstIndex(where: { $0.id == id }) {
            let replyIndex = index - 1
            let needed = ThreadWindow.covering(index: replyIndex, replies: messages.count - 1, window: replyWindow)
            if needed != replyWindow {
                replyWindow = needed
                Task { try? await Task.sleep(for: .milliseconds(80)); withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(id, anchor: .center) } }
                return
            }
        }
        withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(id, anchor: .center) }
    }
    private var conversation: Conversation? { store.conversation(target.conversationID) }

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()
            ScrollViewReader { proxy in
                ScrollView {
                    // An eager stack, not a lazy one (LIME-173): a lazy stack's estimated height collapses after the scroll, so a very tall first message left
                    // the screen blank until a touch. Here the height is exact and the first frame is right (as in chats since LIME-164).
                    VStack(spacing: 0) {
                        if let root = messages.first {
                            bubble(root, isRoot: true).id(root.id)
                            HStack(spacing: 10) {
                                Text(replyCountText).font(Theme.font(.caption, weight: .semibold)).foregroundStyle(Theme.textSecondary)
                                    .accessibilityIdentifier("thread-count")
                                Rectangle().fill(Theme.hairline).frame(height: 0.5)
                            }
                            .padding(.vertical, 10)
                            .accessibilityElement(children: .combine)
                            let hidden = ThreadWindow.hidden(replies: messages.count - 1, window: replyWindow)
                            if hidden > 0 {
                                Button { replyWindow = ThreadWindow.grown(window: replyWindow, replies: messages.count - 1) } label: {
                                    Text("Show \(min(hidden, ThreadWindow.page)) earlier \(min(hidden, ThreadWindow.page) == 1 ? "reply" : "replies")")
                                        .font(Theme.font(.subheadline, weight: .semibold)).foregroundStyle(Theme.text)
                                        .frame(maxWidth: .infinity, minHeight: 44)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("thread-earlier")
                            }
                            ForEach(ThreadWindow.shown(Array(messages.dropFirst()), window: replyWindow)) { reply in bubble(reply, isRoot: false).id(reply.id) }
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 8)
                }
                .accessibilityIdentifier("thread-scroll")
                .environment(\.chatConversationID, target.conversationID)
                .scrollDismissesKeyboard(.interactively)
                .hidesKeyboardOnTap()
                .keepsNewestAboveKeyboard(proxy: proxy, newestID: "bottom")
                // With replies it opens at the newest one; with none, at the top of the message they hang from (a long one reads from its first line).
                .defaultScrollAnchor(messages.count > 1 ? .bottom : .top)
                // After a turn to landscape (or when it first appears) the newest message is brought clear of the composer.
                .onChange(of: verticalSizeClass) { _, _ in
                    Task { try? await Task.sleep(for: .milliseconds(250)); settle(proxy) }
                }
                .task { try? await Task.sleep(for: .milliseconds(250)); settle(proxy) }
                .linkOpening()
                .environment(\.mentionContext, conversation.map { store.mentionContext(for: $0) })
                .attachmentPresenting()
                .onChange(of: messages.count) { _, count in
                    // A reply arrived: show it. The root message loading (0 to 1) is not a reply: it keeps its first line at the top.
                    if count > 1 { withAnimation { proxy.scrollTo("bottom") } } else { settle(proxy) }
                    Task { await store.markThreadRead(target.rootID, in: target.conversationID) }
                }
                .onChange(of: scrollRequest) { _, _ in
                    guard let id = target.focusMessageID else { return }
                    reveal(id, proxy: proxy)
                }
                .onChange(of: findScroll) { _, id in
                    guard let id else { return }
                    reveal(id, proxy: proxy)
                }
            }
        }
        .messageActions(actions, conversationID: target.conversationID, inThread: true, selection: $selection)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // The call mini player floats above this screen's own composer, as in a chat (LIME-150-fix4); below it would be the home indicator.
            VStack(spacing: 0) {
                CallMiniPlayer(gapBelow: CallMiniPlayer.floatGapAboveComposer)
                if let selection {
                    SelectionBar(count: selection.count,
                                 onDelete: { actions.deleting = messages.filter { selection.contains($0.id) } },
                                 onForward: { actions.requestForward(messages.filter { selection.contains($0.id) }, store: store) })
                } else {
                    ChatComposer(model: composerModel, onSend: { markdown in
                        Task { await store.sendReply(markdown, root: target.rootID, in: target.conversationID) }
                    }, onSendAttachments: { items, caption in
                        store.sendAttachments(items, caption: caption, in: target.conversationID, replyTo: target.rootID)
                    }, onSendPreview: { markdown, preview in
                        Task { await store.sendNow(markdown, preview: preview, in: target.conversationID, replyTo: target.rootID) }
                    })
                    .composerMentions(composerModel, in: conversation)
                }
            }
        }
        .safeAreaInset(edge: .top) {
            VStack(spacing: 0) {
                if finding { findBar }
            }
        }
        .navigationTitle("Replies")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                // Who the replies answer, like a chat's header: their avatar, "Replies · Name", and how many replies.
                HStack(spacing: 8) {
                    if let root = messages.first, let author = rootAuthor(root) {
                        AvatarView(person: author, size: 30)
                            .contentShape(Circle())
                            .onTapGesture { store.openProfile(ProfileRoute(userID: author.id, name: author.name, conversationID: target.conversationID)) }
                            .accessibilityIdentifier("replies-author-avatar")
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        Text(rootAuthor(messages.first).map { "Replies · \($0.name)" } ?? "Replies")
                            .font(Theme.font(.headline, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                        Text(replyCountText).font(Theme.caption).foregroundStyle(Theme.textSecondary).lineLimit(1)
                            .accessibilityIdentifier("replies-subtitle")
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("replies-title")
            }
            ToolbarItem(placement: .topBarTrailing) {
                if selection != nil {
                    Button("Cancel") { selection = nil }.font(Theme.title).foregroundStyle(Theme.text).accessibilityIdentifier("select-cancel")
                } else {
                    Button { startFinding() } label: { ToolIconLabel(symbol: "magnifyingglass") }
                        .accessibilityLabel("Search in Replies")
                        .accessibilityIdentifier("replies-search-button")
                }
            }
        }
        .task {
            await store.openThread(target.rootID)
            await store.markThreadRead(target.rootID, in: target.conversationID)
            // Opened from a search hit: land on that reply and highlight it for a moment.
            if let focus = target.focusMessageID {
                try? await Task.sleep(for: .milliseconds(300))
                highlightedID = focus
                scrollRequest = UUID()
                try? await Task.sleep(for: .seconds(4))
                if highlightedID == focus { withAnimation { highlightedID = nil } }
            }
        }
        .onAppear { notifications.viewing = ViewingTarget(conversationID: target.conversationID, threadRoot: target.rootID) }
        .onDisappear {
            store.closeThread(target.rootID)
            if notifications.viewing == ViewingTarget(conversationID: target.conversationID, threadRoot: target.rootID) { notifications.viewing = nil }
        }
    }

    // MARK: Find in these replies

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
        highlightedID = findHits[next].messageID
        findScroll = findHits[next].messageID
    }

    private var findWords: [String] { finding ? SearchText.words(findQuery) : [] }

    private var findStatus: String {
        if findQuery.trimmingCharacters(in: .whitespaces).isEmpty { return "" }
        if findHits.isEmpty { return "No matches" }
        return "\(findIndex + 1) of \(findHits.count)"
    }

    private var findBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.textSecondary)
            TextField("Find in replies", text: $findQuery)
                .font(Theme.body)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($findFocused)
                .selectionTint()
                .accessibilityIdentifier("replies-find-field")
                .task(id: findQuery) {
                    let wanted = findQuery
                    guard !wanted.trimmingCharacters(in: .whitespaces).isEmpty else { findHits = []; highlightedID = nil; return }
                    try? await Task.sleep(for: .milliseconds(150))
                    guard !Task.isCancelled else { return }
                    let hits = await store.findInThread(wanted, root: target.rootID, in: target.conversationID)
                    guard !Task.isCancelled else { return }
                    findHits = hits
                    findIndex = max(hits.count - 1, 0)
                    if let last = hits.last { highlightedID = last.messageID; findScroll = last.messageID } else { highlightedID = nil }
                }
            Text(findStatus).font(Theme.secondary).foregroundStyle(Theme.textSecondary).lineLimit(1)
                .accessibilityIdentifier("replies-find-count")
            Button { step(by: -1) } label: { Image(systemName: "chevron.up").frame(width: 32, height: 36) }
                .disabled(findIndex <= 0 || findHits.isEmpty)
                .accessibilityLabel("Previous match").accessibilityIdentifier("replies-find-up")
            Button { step(by: 1) } label: { Image(systemName: "chevron.down").frame(width: 32, height: 36) }
                .disabled(findIndex >= findHits.count - 1 || findHits.isEmpty)
                .accessibilityLabel("Next match").accessibilityIdentifier("replies-find-down")
            Button("Done") { stopFinding() }
                .font(Theme.font(.subheadline, weight: .semibold))
                .accessibilityIdentifier("replies-find-done")
        }
        .foregroundStyle(Theme.text)
        .padding(.horizontal, 14).frame(minHeight: 48)
        .limeGlass(in: Capsule())
        .padding(.horizontal, 12).padding(.vertical, 4)
    }

    /// Whose message the replies answer ("You" for mine).
    private func rootAuthor(_ root: Message?) -> Person? {
        guard let root else { return nil }
        if root.isOwn { return Person(id: store.meProvider().id, name: "You", tone: store.meProvider().tone) }
        return conversation.flatMap { store.person(root.senderID, in: $0) }
    }

    private var replyCountText: String {
        let n = messages.dropFirst().filter { !$0.deleted }.count   // a deleted reply keeps its line below, but is not counted
        return n == 0 ? "No replies yet" : "\(n) \(n == 1 ? "reply" : "replies")"
    }

    private func bubble(_ message: Message, isRoot: Bool) -> some View {
        MessageBubble(message: message,
                      sender: conversation.flatMap { store.person(message.senderID, in: $0) },
                      showAvatar: !message.isOwn,
                      showName: false,
                      showState: message.isOwn && message.state != .sent,
                      highlighted: highlightedID == message.id,
                      findWords: finding ? findWords : (highlightedID == target.focusMessageID ? target.words : []),
                      onRetry: { Task { await store.resend(message.id) } },
                      onActions: { actions.menu = message },
                      onShowReactions: { actions.reactors = message },
                      selection: selection.map { $0.contains(message.id) },
                      onToggleSelect: { if var current = selection { if current.contains(message.id) { current.remove(message.id) } else { current.insert(message.id) }; selection = current } })
            .padding(.bottom, 16)
    }
}
