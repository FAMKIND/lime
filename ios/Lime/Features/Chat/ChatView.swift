import SwiftUI

struct ChatView: View {
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    let conversationID: Conversation.ID
    /// Opened from a search result: scroll to this message and highlight it for a moment.
    var focusMessageID: String? = nil
    /// The words of the search that led here: highlighted in the chat like find does.
    var focusWords: [String] = []
    @Environment(ConversationStore.self) private var store
    @Environment(NotificationCoordinator.self) private var notifications
    @Environment(\.dismiss) private var dismiss
    @State private var composerModel = RichComposerModel()
    /// "Waiting for internet": the one-line reason (LIME-142).
    @State private var offlineReason: String?
    @State private var confirmingBlock = false
    @State private var confirmingLeave = false
    @State private var showingSeal = false
    @State private var labelling = false
    @State private var labelText = ""
    // In-chat find (the header's magnifier): the matches, which one is current, and where to scroll.
    @State private var finding = false
    @State private var findQuery = ""
    @State private var findHits: [MessageHit] = []
    @State private var findIndex = 0
    /// The query `findHits` answers. The search task restarts whenever the chat reappears (Back from Replies);
    /// without this it would search again and open Replies again.
    @State private var searchedQuery: String?
    @State private var highlightedID: String?
    #if DEBUG
    /// What a chat's opening did (LIME-152a-fix), written to the diagnostics log.
    @State private var openProbe = ChatOpenProbe()
    #endif
    @State private var scrollRequest: ScrollRequest?
    /// How many of the newest rows are laid out (LIME-164): the first page, growing as you scroll up.
    @State private var windowRows = ChatWindow.first
    /// The opening scroll is done: only now does scrolling near the top load older rows.
    @State private var openSettled = false
    /// The list's content height and offset, kept in a plain box (no redraws), to keep your place when older rows are added.
    @State private var metrics = ScrollMetrics()
    @State private var loadingOlder = false
    @State private var restorer = ScrollRestorer()
    @FocusState private var findFocused: Bool
    // The long-press menu and Select mode (LIME-105).
    @State private var actions = MessageActionsState()
    @State private var selection: Set<Message.ID>?

    /// What to highlight in the bubbles: the typed find words, or the search that opened this chat (until it fades).
    private var highlightWords: [String] {
        if finding { return SearchText.words(findQuery) }
        return highlightedID == focusMessageID ? focusWords : []
    }

    /// Tapping a call bubble asks whether to call back (a stray tap in class must not ring anyone).
    @State private var callBack: CallBubble?

    struct ScrollRequest: Equatable { let id: String; let token = UUID() }

    var body: some View {
        if let conversation = store.conversation(conversationID) {
            Group {
                if #available(iOS 26, *) {
                    nativeContent(conversation)
                } else {
                    legacyContent(conversation)
                }
            }
            .confirmSheet("Leave \(conversation.title)?", isPresented: $confirmingLeave) {
                Button("Leave group", role: .destructive) {
                    Task {
                        await store.leaveGroup(conversation.id)
                        store.path = NavigationPath()
                    }
                }
                .accessibilityIdentifier("chat-leave-confirm")
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You won't get new messages from this group. Someone can add you back.")
            }
            .confirmSheet(conversation.isGroup ? "Call \(conversation.title) again?" : "Call \(conversation.title) back?", isPresented: Binding(get: { callBack != nil }, set: { if !$0 { callBack = nil } })) {
                // The same two rows, icons and order as the header's call menu (one pattern everywhere).
                CallChoiceRows(voice: { startCall(conversation, video: false) }, video: { startCall(conversation, video: true) }, idPrefix: "call-back")
                Button("Cancel", role: .cancel) {}
            }
            .messageActions(actions, conversationID: conversationID, selection: $selection) { message in
                store.path.append(ThreadTarget(conversationID: conversationID, rootID: message.id))
            }
            .sheet(isPresented: $labelling) {
                LabelSheet(name: conversation.title, text: $labelText) { saved in
                    labelling = false
                    if saved, let person = conversation.members.first { Task { await store.setLabel(labelText, for: person.id) } }
                }
            }
            // One confirmation for both ways in: the request bar's Block and the ⋯ menu's "Block <Name>".
            .confirmSheet("Block \(conversation.title)?", isPresented: $confirmingBlock) {
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
            // The call button is always its own circle (glass; lime while a group call is live) beside the capsule.
            ToolbarItem(placement: .topBarTrailing) { if selection == nil { callCircle(conversation) } }
                .sharedBackgroundVisibility(headerCall(conversation) == nil ? .visible : .hidden)
            // A fixed gap, so the system does not merge the call circle's glass with the capsule's: they stay two shapes.
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
            // One item (so one glass pill), with the icons close together.
            ToolbarItem(placement: .topBarTrailing) {
                if selection != nil { cancelSelectButton } else { toolGroup(conversation) }
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
        .alert("Waiting for internet", isPresented: Binding(get: { offlineReason != nil }, set: { if !$0 { offlineReason = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(offlineReason ?? "") }
    }

    // MARK: Shared

    private func messageScroll(_ conversation: Conversation, top: CGFloat) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                let all = ChatRow.rows(for: conversation)
                let rows = Array(ChatWindow.shown(all, window: windowRows))
                let hidden = ChatWindow.hidden(total: all.count, window: windowRows)
                let lastOwnID = conversation.messages.last(where: { $0.isOwn && !$0.isSystem })?.id
                // The newest rows are laid out whole (their height is exact, so the chat opens at the newest message on the first frame however long
                // it is); older ones are added a page at a time as you scroll near the top, keeping your place (LIME-164). A lazy stack estimated
                // the height of rows it had not drawn, and the first scroll landed in a region that was never laid out: a blank chat until a drag.
                VStack(spacing: 0) {
                    if hidden > 0 {
                        Button { loadOlder(proxy: proxy, firstShown: rows.first?.id, total: all.count) } label: {
                            Text("Earlier messages").font(Theme.font(.caption, weight: .medium)).foregroundStyle(Theme.textSecondary)
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("chat-earlier")
                    }
                    chatRows(rows, in: conversation, lastOwnID: lastOwnID)
                }
                .padding(.horizontal, 20)
                .padding(.top, top)
                .padding(.bottom, 8)
            }
            .accessibilityIdentifier("chat-scroll")
            .modifier(OlderOnScrollModifier(metrics: metrics, restorer: restorer, enabled: openSettled && !loadingOlder && ChatWindow.hidden(total: ChatRow.rows(for: conversation).count, window: windowRows) > 0) {
                let all = ChatRow.rows(for: conversation)
                loadOlder(proxy: proxy, firstShown: ChatWindow.shown(all, window: windowRows).first?.id, total: all.count)
            })
            #if DEBUG
            .modifier(ChatOpenProbeModifier(probe: openProbe, conversationID: conversationID, messages: conversation.messages.count, loaded: store.isLoaded))
            #endif
            .environment(\.chatConversationID, conversationID)
            .linkOpening()
            .attachmentPresenting()
            .scrollDismissesKeyboard(.interactively)
            .defaultScrollAnchor(.bottom)
            .task(id: conversationID) {
                // Opening a chat: once its rows have been laid out, settle at the newest message. `defaultScrollAnchor` alone is not
                // enough on every iOS version (a chat pushed at launch opened at its top on iOS 18); this is a no-op when it worked.
                // Not for a search result's jump to a message.
                guard focusMessageID == nil else { return }
                #if DEBUG
                openProbe.open(conversationID, messages: conversation.messages.count, loaded: store.isLoaded)
                openProbe.log("window=\(windowRows) of \(ChatRow.rows(for: conversation).count) rows")
                #endif
                for delay in [0, 120, 350] {
                    try? await Task.sleep(for: .milliseconds(delay))
                    #if DEBUG
                    openProbe.log("scrollTo bottom after \(delay) ms: rows=\(ChatRow.rows(for: conversation).count) window=\(windowRows) messages=\(conversation.messages.count) loaded=\(store.isLoaded) target=\(openProbe.snap.contentH > 0 ? "laid out" : "not laid out yet")")
                    #endif
                    proxy.scrollTo("bottom", anchor: .bottom)
                    #if DEBUG
                    try? await Task.sleep(for: .milliseconds(60))
                    openProbe.log("  after the scroll: \(openProbe.snap.text)")
                    #endif
                }
                openSettled = true
            }
            .onChange(of: verticalSizeClass) { _, _ in
                Task { try? await Task.sleep(for: .milliseconds(250)); proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .refreshable { await store.pullToRefresh() }
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
                // A message arrives just after the chat opens (the test of a chat that must not open blank).
                guard store.isDemo, ProcessInfo.processInfo.arguments.contains("-lime-demo-arrival") else { return }
                try? await Task.sleep(for: .milliseconds(350))
                store.demoReceive(conversationID, text: "Arrived while open")
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
                jump(to: focusMessageID, in: conversation)
                try? await Task.sleep(for: .seconds(4))
                if highlightedID == focusMessageID && !finding { withAnimation { highlightedID = nil } }
            }
            .onChange(of: conversation.messages.count) {
                withAnimation { proxy.scrollTo("bottom") }
                // A message that arrives while the chat is open is read.
                Task { await store.markRead(conversationID) }
            }
            .task { await store.markRead(conversationID) }
            // Opening a chat looks for a new photo of the people in it (at most once a minute each).
            .task { await store.refreshPhotos(of: store.conversation(conversationID)?.members.map(\.id) ?? []) }
            .onAppear { notifications.viewing = ViewingTarget(conversationID: conversationID) }
            .onDisappear { if notifications.viewing == ViewingTarget(conversationID: conversationID) { notifications.viewing = nil } }
        }
    }

    /// One more page of older rows, keeping the place: what is on screen stays exactly where it is while the older rows appear above it.
    private func loadOlder(proxy: ScrollViewProxy, firstShown: String?, total: Int) {
        let next = ChatWindow.grown(window: windowRows, total: total)
        guard next > windowRows, !loadingOlder else { return }
        loadingOlder = true
        let before = (height: metrics.contentH, offset: metrics.offsetY)
        windowRows = next
        Task { @MainActor in
            // Wait for the new layout (the content grows by the height of the older rows), then put the offset back by that much.
            for _ in 0..<30 {
                try? await Task.sleep(for: .milliseconds(30))
                if metrics.contentH != before.height { break }
            }
            #if DEBUG
            openProbe.log("older page: window \(windowRows - ChatWindow.page)→\(next) rows; content \(Int(before.height))→\(Int(metrics.contentH)), offset was \(Int(before.offset)), set to \(Int(before.offset + (metrics.contentH - before.height)))")
            #endif
            if let scrollToY = restorer.scrollToY, metrics.contentH != before.height {
                scrollToY(before.offset + (metrics.contentH - before.height))
            } else if let firstShown {
                proxy.scrollTo(firstShown, anchor: .top)
            }
            try? await Task.sleep(for: .milliseconds(120))
            loadingOlder = false
        }
    }

    /// Makes sure a message is among the rows shown, then asks for the scroll to it (a search hit, a quote, the unread marker).
    private func jump(to id: String, in conversation: Conversation) {
        let all = ChatRow.rows(for: conversation)
        if let index = all.firstIndex(where: { $0.id == id }) {
            windowRows = ChatWindow.covering(index: index, total: all.count, window: windowRows)
        }
        Task {
            try? await Task.sleep(for: .milliseconds(120))
            scrollRequest = ScrollRequest(id: id)
        }
    }

    @ViewBuilder
    private func chatRows(_ rows: [ChatRow], in conversation: Conversation, lastOwnID: String?) -> some View {
                    ForEach(rows) { row in
                        switch row.kind {
                        case .day(let text):
                            Text(text)
                                .font(Theme.font(.caption, weight: .medium))
                                .foregroundStyle(Theme.textSecondary)
                                .padding(.vertical, 12)
                                .accessibilityAddTraits(.isHeader)
                        case .system(let message):
                            Text(message.text)
                                .font(Theme.caption)
                                .foregroundStyle(Theme.textSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.vertical, 6).padding(.horizontal, 24)
                                .frame(maxWidth: .infinity)
                                .accessibilityIdentifier("system-line")
                        case .deletedRun(let count):
                            Text("\(count) messages deleted")
                                .font(Theme.caption.italic())
                                .foregroundStyle(Theme.textSecondary)
                                .padding(.vertical, 6).padding(.horizontal, 24)
                                .frame(maxWidth: .infinity)
                                .padding(.bottom, 2)
                                .accessibilityIdentifier("deleted-run")
                        case .message(let message, let showAvatar):
                            MessageBubble(message: message,
                                          sender: store.person(message.senderID, in: conversation),
                                          showAvatar: showAvatar,
                                          showName: showAvatar && conversation.isGroup,
                                          showState: message.isOwn && (message.state != .sent || message.id == lastOwnID),
                                          highlighted: highlightedID == message.id,
                                          findWords: highlightWords,
                                          onRetry: { Task { await store.resend(message.id) } },
                                          onWhy: { offlineReason = OfflineReason.text(for: message, in: conversation) },
                                          onOpenThread: { store.path.append(ThreadTarget(conversationID: conversation.id, rootID: message.id)) },
                                          onActions: { actions.menu = message },
                                          onShowReactions: { actions.reactors = message },
                                          onCallBack: conversation.isGroup ? groupCallTap(message, conversation) : { callBack = message.call },
                                          conversationID: conversation.id,
                                          onAvatarTap: conversation.isGroup ? { if let who = store.person(message.senderID, in: conversation) { store.openProfile(ProfileRoute(userID: who.id, name: who.name, conversationID: conversation.id)) } } : nil,
                                          selection: selection.map { $0.contains(message.id) },
                                          onToggleSelect: { toggleSelection(message.id) })
                                .padding(.bottom, 16)
                        }
                    }
                    Color.clear.frame(height: 1).id("bottom")
    }

    private func sealExplanation(_ conversation: Conversation) -> String {
        let name = conversation.members.first?.name.split(separator: " ").first.map(String.init) ?? conversation.title
        guard let date = conversation.verifiedAt else { return "You scanned \(name)'s QR code in person." }
        return "You scanned \(name)'s QR code in person on \(date.formatted(.dateTime.month(.wide).day().year()))."
    }

    private func titlePill(_ conversation: Conversation) -> some View {
        HStack(spacing: 8) {
            ConversationAvatar(conversation: conversation, size: 36)
                .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    Text(conversation.title)
                        .font(Theme.font(.subheadline, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    // "Verified in person" (they scanned each other's QR codes): a small seal after the name, with the date when tapped.
                    if conversation.verified && !conversation.isGroup {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                            .contentShape(Rectangle())
                            .onTapGesture { showingSeal = true }
                            .accessibilityLabel("Verified in person").accessibilityAddTraits(.isButton)
                            .accessibilityIdentifier("chat-verified")
                    }
                }
                if conversation.isGroup {
                    Text(conversation.subtitle)
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                } else if let person = conversation.members.first, person.label == nil, let status = store.status(of: person.id), let words = StatusPlan.caption(state: status.state, until: status.until) {
                    Text(words)
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .accessibilityIdentifier("chat-status")
                } else if let person = conversation.members.first, let label = person.label {
                    // My label for them, then their status when they have one ("Grade 4 · Do not disturb").
                    let status = store.status(of: person.id).flatMap { StatusPlan.caption(state: $0.state, until: $0.until) }
                    Text(status.map { "\(label) · \($0)" } ?? label)
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .accessibilityIdentifier("chat-label")
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if conversation.isGroup && !conversation.isRequest { store.path.append(GroupTarget(conversationID: conversation.id)) }
            else { openProfile(conversation) }
        }
        .accessibilityElement(children: conversation.verified ? .contain : .combine)
        .accessibilityAddTraits(conversation.isGroup || canOpenProfile(conversation) ? .isButton : [])
        .accessibilityIdentifier("chat-title")
        .alert("Verified in person", isPresented: $showingSeal) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(sealExplanation(conversation))
        }
    }

    /// A one-to-one chat's header (the avatar or the name), and the ⋯ menu's Profile, open the person's profile; in Note to Self, your own.
    private func canOpenProfile(_ conversation: Conversation) -> Bool {
        !conversation.isGroup && !conversation.isRequest && conversation.members.first != nil
    }

    private func openProfile(_ conversation: Conversation) {
        guard canOpenProfile(conversation), let person = conversation.members.first else { return }
        if conversation.id == store.selfChatID { store.openMyProfile(); return }
        store.path.append(ProfileRoute(userID: person.id, name: conversation.title, conversationID: conversation.id))
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
        searchedQuery = nil
        highlightedID = nil
    }

    private func step(by delta: Int) {
        let next = findIndex + delta
        guard findHits.indices.contains(next) else { return }
        findIndex = next
        show(findHits[next])
    }

    private func show(_ hit: MessageHit) {
        // A hit in a reply opens that Replies screen, with the words highlighted.
        if let root = hit.threadRoot {
            store.path.append(ThreadTarget(conversationID: conversationID, rootID: root, focusMessageID: hit.messageID, words: SearchText.words(findQuery)))
            return
        }
        highlightedID = hit.messageID
        if let conversation = store.conversation(conversationID) { jump(to: hit.messageID, in: conversation) } else { scrollRequest = ScrollRequest(id: hit.messageID) }
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
                .selectionTint()
                .accessibilityIdentifier("find-field")
                .task(id: findQuery) {
                    let wanted = findQuery
                    guard wanted != searchedQuery else { return }
                    guard !wanted.trimmingCharacters(in: .whitespaces).isEmpty else { findHits = []; highlightedID = nil; searchedQuery = wanted; return }
                    try? await Task.sleep(for: .milliseconds(150))
                    guard !Task.isCancelled else { return }
                    let hits = await store.findInChat(wanted, in: conversationID)
                    guard !Task.isCancelled else { return }
                    findHits = hits
                    searchedQuery = wanted
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
                .font(Theme.font(.subheadline, weight: .semibold))
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

            if selection == nil {
                if headerCall(conversation) == nil {
                    callCircle(conversation).limeGlass(in: Circle())
                } else {
                    callCircle(conversation)
                }
            }

            Group {
                if selection != nil { cancelSelectButton } else { toolGroup(conversation) }
            }
            .padding(.horizontal, 2)
            .limeGlass()
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
        // The bar of buttons keeps to a size that fits one line across the screen; the messages below follow the full size (LIME-168).
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    /// The ⋯ menu: mute this chat's notifications (1 hour, 8 hours, 1 week, always), or unmute it.
    private func moreMenu<Icon: View>(_ conversation: Conversation, @ViewBuilder label: () -> Icon) -> some View {
        let settings = notifications.settings
        return Menu {
            if canOpenProfile(conversation) {
                Button { openProfile(conversation) } label: { Label("Profile", systemImage: "person.crop.circle") }
                    .accessibilityIdentifier("chat-profile")
            }
            if settings.isMuted(conversation.id), let until = settings.activeMutes().first(where: { $0.conversationID == conversation.id })?.until {
                Button { settings.unmute(conversation.id) } label: {
                    Label("Unmute (\(MuteText.until(until).lowercased()))", systemImage: "bell")
                }
                .accessibilityIdentifier("chat-unmute")
            } else {
                Menu {
                    ForEach(MuteDuration.allCases) { duration in
                        Button(duration.title) { settings.mute(conversation.id, for: duration) }
                            .accessibilityIdentifier("mute-\(duration.rawValue)")
                    }
                } label: { Label("Mute", systemImage: "bell.slash") }
                .accessibilityIdentifier("chat-mute")
            }
            Divider()
            if conversation.isGroup {
                Button { store.path.append(GroupTarget(conversationID: conversation.id)) } label: {
                    Label("Group details", systemImage: "person.2")
                }
                .accessibilityIdentifier("chat-group-details")
                Button(role: .destructive) { confirmingLeave = true } label: {
                    Label("Leave group", systemImage: "rectangle.portrait.and.arrow.right")
                }
                .accessibilityIdentifier("chat-leave")
            } else if conversation.id != store.selfChatID {   // nothing to block or label in my own chat
                if let person = conversation.members.first {
                    Button {
                        labelText = person.label ?? ""
                        labelling = true
                    } label: { Label(person.label == nil ? "Add a label" : "Edit label", systemImage: "tag") }
                    .accessibilityIdentifier("chat-label-button")
                }
                // Blocking someone you already chat with (the request bar's Block is only for strangers).
                Button(role: .destructive) { confirmingBlock = true } label: {
                    Label("Block \(conversation.title)", systemImage: "hand.raised")
                }
                .accessibilityIdentifier("chat-block")
            }
        } label: { label() }
        .accessibilityLabel("More")
        .accessibilityIdentifier("chat-more")
    }

    private var cancelSelectButton: some View {
        Button("Cancel") { selection = nil }
            .font(Theme.title).foregroundStyle(Theme.text)
            .padding(.horizontal, 10).frame(minHeight: 44)
            .accessibilityIdentifier("select-cancel")
    }

    /// Search, call and ⋯ close together: each icon keeps a 44 pt target, and the targets overlap by 6 pt so the icons sit 38 pt apart.
    private func toolGroup(_ conversation: Conversation) -> some View {
        HStack(spacing: -6) {
            toolIcon("magnifyingglass", label: "Search in chat", id: "chat-search-button") { startFinding() }
            moreMenu(conversation) { ToolIconLabel(symbol: "ellipsis") }
        }
    }

    /// The call that is on in this group, for the header's own call button (nil: the ordinary phone menu).
    private func headerCall(_ conversation: Conversation) -> GroupCallInfo? {
        _ = store.groupCalls.changes
        guard conversation.isGroup, !conversation.isRequest, conversation.groupEnded == nil else { return nil }
        return store.groupCalls.core.activeCall(conversationID: conversation.id)
    }

    /// The call button is always its own circle beside the search/⋯ capsule, in every chat, so a call starting never rearranges the header:
    /// the ordinary phone menu (a glass circle) with no call, and the same circle turned lime with the call's own icon while a group call is
    /// live (tap joins, or returns to the call I am in). No count here: the card in the chat has it.
    @ViewBuilder
    private func callCircle(_ conversation: Conversation) -> some View {
        if let live = headerCall(conversation) {
            LiveCallButton(video: live.video, returning: store.groupCalls.inCall && store.groupCalls.conversationID == conversation.id) {
                if store.groupCalls.inCall && store.groupCalls.conversationID == conversation.id {
                    store.groupCalls.minimized = false
                } else {
                    joinGroupCall(live, conversation)
                }
            }
        } else {
            callMenu(conversation)
        }
    }

    /// The call button: voice or video, to one accepted person, or to a group (LIME-112b).
    private func callMenu(_ conversation: Conversation) -> some View {
        Menu {
            CallChoiceRows(voice: { startCall(conversation, video: false) }, video: { startCall(conversation, video: true) }, idPrefix: "chat-call")
        } label: { ToolIconLabel(symbol: "phone") }
            .accessibilityLabel("Call")
            .accessibilityIdentifier("chat-call-button")
    }

    /// The live call card's button joins the call while it is on, or returns to it when I am already in it.
    private func groupCallTap(_ message: Message, _ conversation: Conversation) -> (() -> Void)? {
        guard let call = message.call, message.id.hasPrefix("call:") else { return nil }
        // An ended group call never calls one person: it asks whether to call the group again (the same sheet as a call back).
        guard CallBubbleTap.action(isGroup: true, call: call) == .join else { return { callBack = call } }
        let callID = String(message.id.dropFirst(5))
        return {
            if store.groupCalls.inCall && store.groupCalls.conversationID == conversation.id { store.groupCalls.minimized = false; return }
            if let live = store.groupCalls.core.activeCall(conversationID: conversation.id), live.callId == callID { joinGroupCall(live, conversation) }
        }
    }

    private func joinGroupCall(_ call: GroupCallInfo, _ conversation: Conversation) {
        Task { _ = await store.groupCalls.join(callID: call.callId, conversationID: conversation.id, title: conversation.title, video: call.video) }
    }

    private func startCall(_ conversation: Conversation, video: Bool) {
        if conversation.isGroup {
            guard !conversation.isRequest, conversation.groupEnded == nil else { return }
            Task { _ = await store.groupCalls.start(conversationID: conversation.id, title: conversation.title, video: video) }
            return
        }
        guard !conversation.isRequest, conversation.groupEnded == nil, let peer = conversation.members.first else { return }
        Task { _ = await store.calls.start(peerID: peer.id, name: conversation.title, video: video) }
    }

    private func toolIcon(_ symbol: String, label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { ToolIconLabel(symbol: symbol) }
            .accessibilityLabel(label)
            .accessibilityIdentifier(id)
    }

    // MARK: Bottom: the composer, or Accept / Block for a request

    @ViewBuilder
    private func bottomBar(_ conversation: Conversation) -> some View {
        // The mini player floats 4 pt above the composer (its own padding); the rest keeps its 8 pt spacing.
        VStack(spacing: 0) {
            CallMiniPlayer(gapBelow: CallMiniPlayer.floatGapAboveComposer)
            bottomRest(conversation)
        }
    }

    @ViewBuilder
    private func bottomRest(_ conversation: Conversation) -> some View {
        VStack(spacing: 8) {
            if conversation.isGroup { EmergencyPanel(conversation: conversation) }
            #if DEBUG
            NearbyOfferBar(waitingInChat: conversation.messages.contains { $0.state == .waiting })
            #endif
            if conversation.keyChangePending { keyChangeBar(conversation) }
            if let selection {
                SelectionBar(count: selection.count,
                             onDelete: { actions.deleting = conversation.messages.filter { selection.contains($0.id) } },
                             onForward: { actions.requestForward(conversation.messages.filter { selection.contains($0.id) }, store: store) })
            } else if conversation.isRequest { requestBar(conversation) }
            else if let ended = conversation.groupEnded { endedBar(conversation, ended) }
            else { composer(conversation) }
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
            Text(conversation.isGroup ? "You were added to \(conversation.title) by someone who isn't in your chats yet. Accept to join in."
                                      : "\(conversation.title) isn't in your chats yet. Accept to reply.")
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
    }

    // MARK: Composer

    private func toggleSelection(_ id: Message.ID) {
        guard var current = selection else { return }
        if current.contains(id) { current.remove(id) } else { current.insert(id) }
        selection = current
    }

    /// A group that ended is read-only: "You left this group" or "<Owner> deleted this group".
    private func endedBar(_ conversation: Conversation, _ ended: String) -> some View {
        let words = ended == "left" ? "You left this group." : (conversation.messages.last { $0.isSystem && $0.text.contains("deleted this group") }.map { $0.text + "." } ?? "This group was deleted.")
        return VStack(spacing: 10) {
            Text(words).font(Theme.secondary).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
                .accessibilityIdentifier("group-ended-note")
            Button {
                Task { await store.deleteChat(conversation.id); store.path = NavigationPath() }
            } label: {
                Text("Remove from my list").font(Theme.font(.body, weight: .semibold)).foregroundStyle(Color.red).frame(maxWidth: .infinity, minHeight: 48)
            }
            .accessibilityIdentifier("group-ended-remove")
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
        .limeGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.horizontal, 16).padding(.bottom, 4)
    }

    private func composer(_ conversation: Conversation) -> some View {
        ChatComposer(model: composerModel, onSend: { markdown in store.send(markdown, in: conversation.id) },
                     onSendAttachments: conversation.isRequest ? nil : { items, caption in store.sendAttachments(items, caption: caption, in: conversation.id) },
                     onSendPreview: conversation.isRequest || conversation.id == store.selfChatID ? nil : { markdown, preview in Task { await store.sendNow(markdown, preview: preview, in: conversation.id) } })
    }
}

/// A frame kept without telling SwiftUI (a class property is not observed).
final class FrameBox { var frame: CGRect = .zero }

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
    /// The words find (or a search result) is looking for: highlighted inside the bubble.
    var findWords: [String] = []
    var onRetry: () -> Void = {}
    /// "Waiting for internet": tap for the one-line reason.
    var onWhy: () -> Void = {}
    /// Tapping the "N replies" row under a message that has them.
    var onOpenThread: (() -> Void)? = nil
    /// Long-press: the actions menu (reactions, Reply, Edit, Copy, Select, Delete).
    var onActions: (() -> Void)? = nil
    /// Tap the reaction cluster on the bubble's corner: the sheet of who reacted with what.
    var onShowReactions: (() -> Void)? = nil
    /// Tapping a call bubble (the call-back question).
    var onCallBack: (() -> Void)? = nil
    /// The chat this bubble is in (a group's live call card looks up who is in the call).
    var conversationID: String = ""
    /// Tapping a sender's avatar (in a group): their profile.
    var onAvatarTap: (() -> Void)? = nil
    /// Select mode: `nil` outside it, otherwise whether this message is selected; tapping toggles.
    var selection: Bool? = nil
    var onToggleSelect: (() -> Void)? = nil
    /// Only the bubble and the sender's name (no avatar, footer or replies): the lifted copy the long-press menu shows (LIME-152d).
    var liftedOnly = false
    @Environment(\.menuFrameSink) private var menuFrameSink
    /// Where the bubble is on the screen, so the menu can lift a copy of it to the same place. A plain box, not state: the frame changes
    /// while a chat is opening and while it scrolls, and SwiftUI must not redraw every bubble each time (LIME-152a-fix).
    @State private var frameBox = FrameBox()
    @Environment(\.pressedLink) private var pressedLink
    @ScaledMetric(relativeTo: .body) private var scaledAvatar: CGFloat = 36
    /// Grows with the text, but not so far that it crowds the bubble (LIME-168).
    private var avatarSize: CGFloat { min(scaledAvatar, 48) }

    var body: some View {
        if liftedOnly {
            VStack(alignment: message.isOwn ? .trailing : .leading, spacing: 4) {
                if showName, let sender {
                    Text(sender.name).font(Theme.font(.caption, weight: .medium)).foregroundStyle(Theme.text)
                }
                content
            }
            .allowsHitTesting(false)
        } else {
            row
        }
    }

    private var row: some View {
        HStack(alignment: .top, spacing: 8) {
            if let selection, !message.isOwn { selectionCircle(selection) }
            if message.isOwn { Spacer(minLength: 56) }
            if !message.isOwn, let sender {
                if showAvatar {
                    AvatarView(person: sender, size: avatarSize)
                        .contentShape(Circle())
                        .onTapGesture { onAvatarTap?() }
                        .accessibilityAddTraits(onAvatarTap == nil ? [] : .isButton)
                        .accessibilityLabel(onAvatarTap == nil ? "" : "\(sender.name), profile")
                        .accessibilityIdentifier("message-avatar-\(sender.id)")
                }
                else { Color.clear.frame(width: avatarSize, height: 1) }
            }
            BubbleColumn(trailing: message.isOwn, spacing: 4) {
                if showName, let sender {
                    Text(sender.name)
                        .font(Theme.font(.caption, weight: .medium))
                        .foregroundStyle(Theme.text)
                }
                // Top to bottom: the bubble; one footer row (reactions on the leading side, the time and status on the trailing
                // side, as wide as the bubble); then the replies.
                content
                HStack(spacing: 6) {
                    if hasReactions { reactionChips }
                    Spacer(minLength: 8)
                    timeStamp
                }
                .layoutValue(key: BubbleFooterKey.self, value: true)
                if let thread = message.thread, let onOpenThread {
                    ThreadSummaryRow(messageID: message.id, thread: thread, action: onOpenThread)
                }
            }
            if !message.isOwn { Spacer(minLength: 56) }
            if let selection, message.isOwn { selectionCircle(selection) }
        }
        .contentShape(Rectangle())
        .onTapGesture { if selection != nil { onToggleSelect?() } }
        .accessibilityElement(children: selection != nil ? .ignore : .contain)
        .accessibilityLabel(selection != nil ? "\(message.deleted ? "Deleted message" : messagePlainText(text: message.text))" : "")
        .accessibilityAddTraits(selection == true ? [.isButton, .isSelected] : (selection == false ? .isButton : []))
        .accessibilityIdentifier(selection != nil ? "select-row-\(message.id)" : "")
    }

    private func selectionCircle(_ on: Bool) -> some View {
        Image(systemName: on ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 24))
            .foregroundStyle(on ? Theme.text : Theme.textSecondary.opacity(0.7))
            .frame(width: 32, height: 36)
            .accessibilityHidden(true)
    }

    /// The attachments and the text bubble (or the "deleted" notice): the part a long-press opens the menu for.
    @ViewBuilder
    private var content: some View {
        VStack(alignment: message.isOwn ? .trailing : .leading, spacing: 4) {
            if message.deleted {
                Text("This message was deleted")
                    .font(Theme.body.italic()).foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .overlay(RoundedRectangle(cornerRadius: Theme.bubbleRadius, style: .continuous).strokeBorder(Theme.bubbleEdge, lineWidth: 0.8))
                    .accessibilityIdentifier("deleted-bubble")
            } else {
                if message.forwarded {
                    Label("Forwarded", systemImage: "arrowshape.turn.up.right")
                        .font(Theme.caption.italic()).foregroundStyle(Theme.textSecondary)
                        .labelStyle(.titleAndIcon)
                        .accessibilityIdentifier("forwarded-\(message.id)")
                }
                if let card = message.emergency {
                    EmergencyCardView(card: card, senderName: sender?.name ?? "You", date: message.date, id: message.id)
                }
                if let call = message.call { CallBubbleView(call: call, id: message.id, conversationID: conversationID, callerName: sender?.name, onTap: onCallBack) }
                if !message.attachments.isEmpty { AttachmentStack(message: message, isOwn: message.isOwn) }
                if let preview = message.linkPreview { MessageLinkCard(messageID: message.id, preview: preview, isOwn: message.isOwn) }
                if message.call == nil, message.emergency == nil, !message.text.isEmpty || message.attachments.isEmpty {
                    FormattedMessageText(markdown: message.text, ink: message.isOwn ? Theme.ownBubbleInk : Theme.text,
                                         link: message.isOwn ? Theme.linkOwn : Theme.linkOther, pressed: pressedLink?.absoluteString,
                                         find: findWords.isEmpty ? nil : FindStyle(words: findWords, current: highlighted))
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(message.isOwn ? Theme.ownBubble : Theme.bubbleOther,
                                    in: RoundedRectangle(cornerRadius: Theme.bubbleRadius, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.bubbleRadius, style: .continuous)
                                .strokeBorder(message.isOwn ? Color.clear : Theme.bubbleEdge, lineWidth: 0.5)
                        )
                        .animation(.easeInOut(duration: 0.2), value: highlighted)
                        .accessibilityIdentifier(message.isOwn ? "own-bubble" : "other-bubble")
                        .overlay(alignment: .topLeading) {
                            // For assistive tools and UI tests: which message a search or find landed on.
                            if highlighted { Color.clear.frame(width: 1, height: 1).accessibilityIdentifier("match-marker-\(message.id)") }
                        }
                }
            }
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frameBox.frame = $0 }
        .onLongPressGesture(minimumDuration: 0.4) { if selection == nil { lift() } }
        .environment(\.mediaLongPress, selection == nil && onActions != nil ? MediaLongPress(messageID: message.id, action: { lift() }) : nil)
        .environment(\.mediaSelecting, selection != nil)
    }

    /// A long-press: a light haptic, the bubble's place on the screen, then the menu.
    private func lift() {
        guard onActions != nil else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        menuFrameSink?.set(frameBox.frame)
        onActions?()
    }

    private var hasReactions: Bool { !message.reactions.isEmpty && !message.deleted }

    /// The time, "Edited" and the delivery state, on the trailing side of the footer.
    private var timeStamp: some View {
        HStack(spacing: 4) {
            Text(MessageFormat.clock(message.date)).accessibilityIdentifier("message-time-\(message.id)")
            if message.edited {
                Text("· Edited").accessibilityIdentifier("edited-\(message.id)")
            }
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
                case .waiting, .passed:
                    // On its way through nearby phones (LIME-142): words and an icon, grey (not an error), no retry (it resumes by itself).
                    Label(message.state.statusWords ?? "", systemImage: message.state.statusSymbol ?? "")
                        .labelStyle(.titleAndIcon).imageScale(.small)
                        .accessibilityLabel(message.state.statusWords ?? "")
                        .accessibilityIdentifier(message.state == .waiting ? "delivery-waiting" : "delivery-passed")
                case .offline:
                    // It cannot travel through nearby phones (a file, or someone who has not accepted you yet): waits for the internet and says why on tap.
                    Button(action: onWhy) {
                        Label(message.state.statusWords ?? "", systemImage: message.state.statusSymbol ?? "")
                            .labelStyle(.titleAndIcon).imageScale(.small)
                    }
                    .accessibilityLabel("Waiting for internet")
                    .accessibilityHint("Says why")
                    .accessibilityIdentifier("delivery-offline")
                case .received, .system: EmptyView()
                }
            }
        }
        .font(Theme.caption)
        .foregroundStyle(Theme.textSecondary)
        .lineLimit(1)
    }


    /// The reactions under the bubble: a soft grey chip each (mine a little deeper), no outline; the first five, then "+N".
    /// Tapping them lists who reacted with what.
    private var reactionChips: some View {
        let shown = Array(message.reactions.prefix(5))
        let more = message.reactions.count - shown.count
        let mine = message.reactions.contains(where: \.mine)
        return HStack(spacing: 4) {
            ForEach(shown) { chip in
                HStack(spacing: 3) {
                    Text(chip.emoji).font(.system(size: 14))
                    if chip.count > 1 { Text("\(chip.count)").font(Theme.font(.caption, weight: .semibold)).foregroundStyle(Theme.text) }
                }
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(chip.mine ? Theme.chipFillMine : Theme.chipFill, in: Capsule())
            }
            if more > 0 {
                Text("+\(more)").font(Theme.font(.caption, weight: .semibold)).foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Theme.chipFill, in: Capsule())
            }
        }
        .fixedSize()
        .contentShape(Rectangle())
        .onTapGesture { if selection == nil { onShowReactions?() } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Reactions: " + message.reactions.map { "\($0.emoji) \($0.count)" }.joined(separator: ", ") + (mine ? ", including yours" : ""))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("reaction-cluster-\(message.id)")
    }
}

/// Marks the footer row of a message (reactions and time) inside `BubbleColumn`.
struct BubbleFooterKey: LayoutValueKey {
    static let defaultValue = false
}

/// A message's column: its parts stacked, aligned to the bubble's side. The footer row is exactly as wide as the bubble (or as its
/// own contents if they need more), so the time sits under the bubble's edge, not at the edge of the screen.
struct BubbleColumn: Layout {
    var trailing: Bool
    var spacing: CGFloat = 4

    private func widths(_ subviews: Subviews, _ proposal: ProposedViewSize) -> (content: CGFloat, footer: CGFloat?) {
        var content: CGFloat = 0
        var footer: CGFloat?
        for view in subviews {
            if view[BubbleFooterKey.self] {
                footer = view.sizeThatFits(.unspecified).width
            } else {
                content = max(content, view.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil)).width)
            }
        }
        return (content, footer)
    }

    private func footerWidth(_ w: (content: CGFloat, footer: CGFloat?), _ proposal: ProposedViewSize) -> CGFloat {
        let wanted = max(w.content, w.footer ?? 0)
        return min(wanted, proposal.width ?? wanted)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = widths(subviews, proposal)
        let footer = footerWidth(w, proposal)
        var height: CGFloat = 0
        var width = max(w.content, footer)
        for (index, view) in subviews.enumerated() {
            let isFooter = view[BubbleFooterKey.self]
            let size = view.sizeThatFits(ProposedViewSize(width: isFooter ? footer : proposal.width, height: nil))
            height += size.height + (index == 0 ? 0 : spacing)
            width = max(width, size.width)
        }
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let w = widths(subviews, ProposedViewSize(width: bounds.width, height: nil))
        let footer = footerWidth(w, ProposedViewSize(width: bounds.width, height: nil))
        var y = bounds.minY
        for view in subviews {
            let isFooter = view[BubbleFooterKey.self]
            let size = view.sizeThatFits(ProposedViewSize(width: isFooter ? footer : bounds.width, height: nil))
            let x = trailing ? bounds.maxX - size.width : bounds.minX
            view.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(width: size.width, height: size.height))
            y += size.height + spacing
        }
    }
}

extension EnvironmentValues {
    /// The link a person just tapped, so its text can show pressed.
    @Entry var pressedLink: URL? = nil
}

/// An icon of the header's tool group: a full 44 pt target (the group overlaps neighbours by 6 pt to sit closer).
struct ToolIconLabel: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 18))
            .foregroundStyle(Theme.text)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }
}

/// "Add a label": my private note beside a person's name ("Grade 4 · Lincoln"). It stays on this phone: it is never sent to the
/// server or to them.
struct LabelSheet: View {
    let name: String
    @Binding var text: String
    var finish: (_ saved: Bool) -> Void
    @FocusState private var focused: Bool

    static let limit = 30

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Button("Cancel") { finish(false) }.foregroundStyle(Theme.text).accessibilityIdentifier("label-cancel")
                Spacer()
                Text("Label for \(name)").font(Theme.title).foregroundStyle(Theme.text).lineLimit(1)
                Spacer()
                Button("Save") { finish(true) }.font(Theme.title).foregroundStyle(Theme.text).accessibilityIdentifier("label-save")
            }
            TextField("Grade 4 · Lincoln", text: Binding(get: { text }, set: { text = String($0.prefix(Self.limit)) }))
                .font(Theme.body).selectionTint().focused($focused)
                .padding(.horizontal, 16).frame(minHeight: 52)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .onSubmit { finish(true) }
                .accessibilityIdentifier("label-field")
            HStack {
                Text("Only you see this. It's never sent to Lime's servers or to \(name).").font(Theme.secondary).foregroundStyle(Theme.textSecondary)
                Spacer(minLength: 8)
                Text("\(text.count)/\(Self.limit)").font(Theme.caption).foregroundStyle(Theme.textSecondary).accessibilityIdentifier("label-count")
            }
            if !text.isEmpty {
                Button(role: .destructive) { text = ""; finish(true) } label: { Text("Remove label").font(Theme.body) }
                    .accessibilityIdentifier("label-remove")
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .background(Theme.canvas.ignoresSafeArea())
        .presentationDetents([.medium])
        .onAppear { focused = true }
    }
}


/// A call in the chat (LIME-123): a symbol, "Voice call" / "Video call" / "Missed voice call", and its length or what became of it. The
/// same neutral bubble for both sides (the accent is for the primary action only); a missed incoming call is in the danger red.
struct CallBubbleView: View {
    let call: CallBubble
    let id: String
    /// The chat this is in (a group's live card asks who is in the call).
    var conversationID: String = ""
    /// Who started a group call (the title says "<Name> started a call").
    var callerName: String?
    var onTap: (() -> Void)?
    @Environment(ConversationStore.self) private var store

    var body: some View {
        if call.isGroup && call.live {
            liveCard
        } else {
            ordinary
        }
    }

    /// A group call that is on: one card that shows who is there and joins in one tap; it becomes "Call ended · 3:20" when the call ends.
    private var liveCard: some View {
        _ = store.groupCalls.changes
        let summary = store.groupCalls.liveSummary(conversationID: conversationID)
        let people = summary?.people ?? []
        let count = Int(summary?.info.participantCount ?? 0)
        let returning = store.groupCalls.inCall && store.groupCalls.conversationID == conversationID
        let who = LiveCardWords.who(people.map(\.name), count: count, iAmIn: returning)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                // No LIVE badge and no green here (LIME-150): a quiet card. The LIVE badge lives in the mini player.
                Image(systemName: call.video ? "video" : "phone").font(Theme.body).foregroundStyle(Theme.text)
                Text(call.title(startedBy: callerName)).font(Theme.font(.body, weight: .semibold)).foregroundStyle(Theme.text)
                    .accessibilityIdentifier("call-bubble-title")
            }
            if !people.isEmpty {
                HStack(spacing: -8) {
                    ForEach(people.prefix(5)) { person in
                        AvatarView(person: person, size: 28).overlay(Circle().stroke(Theme.surface, lineWidth: 2))
                    }
                }
            }
            Text(who).font(Theme.caption).foregroundStyle(Theme.textSecondary).accessibilityIdentifier("call-card-who")
            Button(action: { onTap?() }) {
                Text(returning ? "Return to call" : "Join call").font(Theme.font(.body, weight: .semibold)).foregroundStyle(Theme.text)
                    .frame(maxWidth: .infinity, minHeight: 44).background(Theme.pressed, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("call-card-join")
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: 300, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.bubbleRadius, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(LiveCardWords.spoken(who: who, video: call.video))
        .accessibilityIdentifier("call-bubble-\(id)")
    }

    private var ordinary: some View {
        let tint: Color = call.isMissedIncoming ? .red : Theme.text
        // A tap gesture, not a Button: a Button would take the touch from the bubble's long-press menu.
        return Group {
            // The same type and padding as a text message, so a call bubble is no taller than a two-line message.
            HStack(spacing: 10) {
                Image(systemName: call.symbol).font(Theme.body)
                    .foregroundStyle(tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text(call.title(startedBy: callerName)).font(Theme.body).foregroundStyle(tint)
                        .accessibilityIdentifier("call-bubble-title")
                    Text(call.chatDetail).font(Theme.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .accessibilityIdentifier("call-bubble-detail")
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.bubbleRadius, style: .continuous))
            .contentShape(Rectangle())
        }
        .onTapGesture { onTap?() }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("\(call.title(startedBy: callerName)), \(call.chatDetail)")
        .accessibilityHint(call.isGroup ? "" : "Calls back after asking")
        .accessibilityIdentifier("call-bubble-\(id)")
    }
}

/// The words of a live call card and the invite sheet.
enum LiveCardWords {
    /// "Jean is there", "Jean and Lee are there", "Jean, Lee and 2 others are there"; just a count when the names are not known.
    static func who(_ names: [String], count: Int, iAmIn: Bool = false) -> String {
        // Alone in my own call: not "1 person is there" (that is me).
        if iAmIn && names.isEmpty && count <= 1 { return "Waiting for others" }
        let firsts = names.map { $0.split(separator: " ").first.map(String.init) ?? $0 }
        switch (firsts.count, count) {
        case (0, 0): return "Nobody is there yet"
        case (0, 1): return "1 person is there"
        case (0, _): return "\(count) people are there"
        case (1, _): return "\(firsts[0]) is there" + (count > 1 ? " and \(count - 1) other\(count - 1 == 1 ? "" : "s")" : "")
        case (2, _) where count <= 2: return "\(firsts[0]) and \(firsts[1]) are there"
        default:
            let others = max(count - 2, firsts.count - 2)
            return "\(firsts[0]), \(firsts[1]) and \(others) other\(others == 1 ? "" : "s") are there"
        }
    }

    static func spoken(who: String, video: Bool) -> String { "\(video ? "Video" : "Voice") call in progress. \(who). Join" }
}

/// Why a message is "Waiting for internet" instead of being passed through nearby phones (LIME-142): one line, true.
enum OfflineReason {
    static func text(for message: Message, in conversation: Conversation) -> String {
        if !message.attachments.isEmpty { return "Photos need internet. Sends when you\u{2019}re online." }
        if conversation.isRequest || (!conversation.isGroup && conversation.members.first == nil) {
            return "They haven\u{2019}t accepted you yet. Sends when you\u{2019}re online."
        }
        return "No nearby phones. Sends when you\u{2019}re online."
    }
}

/// The header's call circle while a group call is live (LIME-146b): the same circle as the phone button, turned lime, with the call's icon.
/// No count (the card in the chat has it). Words and an icon, not colour alone: VoiceOver reads "Join video call" or "Return to call".
struct LiveCallButton: View {
    let video: Bool
    let returning: Bool
    let action: () -> Void
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let glyph = Image(systemName: video ? "video" : "phone").font(.system(size: 18)).foregroundStyle(Theme.accentInk)
        Button(action: action) {
            Group {
                if reduceTransparency {
                    glyph.frame(width: 44, height: 44).background(Theme.accent, in: Circle())
                } else if #available(iOS 26, *) {
                    glyph.frame(width: 44, height: 44).glassEffect(.regular.tint(Theme.accent.opacity(0.7)).interactive(), in: Circle())
                } else {
                    glyph.frame(width: 44, height: 44).background(Circle().fill(.ultraThinMaterial)).background(Theme.accent.opacity(0.8), in: Circle())
                }
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(LiveCallButton.label(video: video, returning: returning))
        .accessibilityIdentifier("chat-live-call-button")
    }

    nonisolated static func label(video: Bool, returning: Bool) -> String { returning ? "Return to call" : (video ? "Join video call" : "Join voice call") }
}

/// What tapping a call bubble does (LIME-146b). A group's live card joins in one tap; an ended group call never calls one person: it asks
/// whether to call the group again; a one-to-one bubble keeps the call-back question.
enum CallBubbleTap: Equatable {
    case join, callGroupAgain, callBack, nothing

    static func action(isGroup: Bool, call: CallBubble) -> CallBubbleTap {
        if isGroup { return call.isGroup && call.live ? .join : .callGroupAgain }
        return call.isGroup ? .nothing : .callBack
    }
}

#if DEBUG
/// LIME-143: the one-time offer when a message is "Waiting for a phone nearby" and no phone is in range.
struct NearbyOfferBar: View {
    let waitingInChat: Bool
    @State private var dismissed = false

    var body: some View {
        if !dismissed, MeshService.shared.shouldOfferNearby(waitingInChat: waitingInChat) {
            VStack(alignment: .leading, spacing: 10) {
                Text(NearbyMode.offerTitle).font(Theme.secondary).foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Button {
                        MeshService.shared.offerHandled()
                        MeshService.shared.setNearby(true)
                        dismissed = true
                    } label: {
                        Text(NearbyMode.offerButton).font(Theme.font(.subheadline, weight: .semibold)).foregroundStyle(Theme.accentInk)
                            .padding(.horizontal, 16).frame(minHeight: 44).background(Theme.accent, in: Capsule())
                    }
                    .accessibilityIdentifier("nearby-offer-on")
                    Button {
                        MeshService.shared.offerHandled()
                        dismissed = true
                    } label: {
                        Text(NearbyMode.offerNotNow).font(Theme.secondary).foregroundStyle(Theme.text).padding(.horizontal, 12).frame(minHeight: 44)
                    }
                    .accessibilityIdentifier("nearby-offer-not-now")
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 8)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("nearby-offer")
        }
    }
}
#endif

/// "Voice call" and "Video call" with their icons, in this order: the header's call menu and the "Call again?" sheet use this one view, so the
/// two never drift apart (LIME-150, item 10).
struct CallChoiceRows: View {
    let voice: () -> Void
    let video: () -> Void
    /// The accessibility identifiers are `<prefix>-voice` and `<prefix>-video`.
    let idPrefix: String

    var body: some View {
        Button(action: voice) { Label("Voice call", systemImage: "phone") }
            .accessibilityIdentifier("\(idPrefix)-voice")
        Button(action: video) { Label("Video call", systemImage: "video") }
            .accessibilityIdentifier("\(idPrefix)-video")
    }
}


#if DEBUG
/// A chat's open, in numbers, for the diagnostics log (a class, so logging never redraws the chat).
@MainActor
final class ChatOpenProbe {
    struct Snap: Equatable {
        var contentH: CGFloat = 0, visibleH: CGFloat = 0, offsetY: CGFloat = 0, insetTop: CGFloat = 0, insetBottom: CGFloat = 0
        var text: String { "content \(Int(contentH)) pt, visible \(Int(visibleH)) pt, offset \(Int(offsetY)), insets \(Int(insetTop))/\(Int(insetBottom))" }
    }
    private(set) var snap = Snap()
    private var started = Date()
    private var id = ""
    private var layouts = 0

    func open(_ id: String, messages: Int, loaded: Bool) {
        started = Date(); self.id = id; layouts = 0
        log("open: messages=\(messages) loaded=\(loaded)")
    }

    func log(_ line: String) {
        let ms = Int(Date().timeIntervalSince(started) * 1000)
        CallDiagnostics.shared.log("chat_open +\(ms)ms \(id.suffix(6)): \(line)")
    }

    func layout(_ new: Snap) {
        guard new != snap else { return }
        snap = new
        layouts += 1
        if layouts <= 12 || Date().timeIntervalSince(started) < 3 { log("layout #\(layouts): \(new.text)") }
    }

    func messagesChanged(_ count: Int, loaded: Bool) { log("messages now \(count) loaded=\(loaded)") }
}

struct ChatOpenProbeModifier: ViewModifier {
    let probe: ChatOpenProbe
    let conversationID: String
    let messages: Int
    let loaded: Bool

    func body(content: Content) -> some View {
        let base = content
            .onAppear { probe.log("scroll view appeared: messages=\(messages) loaded=\(loaded)") }
            .onChange(of: messages) { _, count in probe.messagesChanged(count, loaded: loaded) }
        if #available(iOS 18, *) {
            base.onScrollGeometryChange(for: ChatOpenProbe.Snap.self) {
                ChatOpenProbe.Snap(contentH: $0.contentSize.height, visibleH: $0.visibleRect.height, offsetY: $0.contentOffset.y, insetTop: $0.contentInsets.top, insetBottom: $0.contentInsets.bottom)
            } action: { _, new in probe.layout(new) }
        } else { base }
    }
}
#endif


/// A scroll view's content height and offset, kept without telling SwiftUI.
final class ScrollMetrics { var contentH: CGFloat = 0; var offsetY: CGFloat = 0 }

/// How to scroll the chat's list to an offset (set by the list on iOS 18 and later; nil before).
final class ScrollRestorer { var scrollToY: ((CGFloat) -> Void)? }

/// Tracks the list's size and offset and, near the top of a chat, loads the next page of older rows (iOS 18 and later; earlier systems have the
/// "Earlier messages" button). `restorer` lets the chat put the offset back after rows are added above.
struct OlderOnScrollModifier: ViewModifier {
    let metrics: ScrollMetrics
    let restorer: ScrollRestorer
    let enabled: Bool
    let load: () -> Void

    func body(content: Content) -> some View {
        if #available(iOS 18, *) {
            Positioned(content: content, metrics: metrics, restorer: restorer, enabled: enabled, load: load)
        } else { content }
    }

    @available(iOS 18, *)
    private struct Positioned<Content: View>: View {
        let content: Content
        let metrics: ScrollMetrics
        let restorer: ScrollRestorer
        let enabled: Bool
        let load: () -> Void
        @State private var position = ScrollPosition()

        var body: some View {
            content
                .scrollPosition($position)
                .onAppear { restorer.scrollToY = { y in position.scrollTo(y: y) } }
                .onScrollGeometryChange(for: ScrollMetricsSnap.self) {
                    ScrollMetricsSnap(contentH: $0.contentSize.height, offsetY: $0.contentOffset.y + $0.contentInsets.top)
                } action: { _, new in
                    metrics.contentH = new.contentH
                    metrics.offsetY = new.offsetY
                    if enabled, new.offsetY < 500 { load() }
                }
        }
    }
}

struct ScrollMetricsSnap: Equatable { var contentH: CGFloat; var offsetY: CGFloat }
