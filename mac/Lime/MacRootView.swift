import SwiftUI

/// The Mac window: signed out → the "links to your phone" screen; signed in → the Messages list beside the selected chat.
struct MacRootView: View {
    @Environment(AccountSession.self) private var session

    var body: some View {
        Group {
            switch session.phase {
            case .launching: SplashView()
            case .signedOut, .choosingMove: MacSignedOutView()
            case .signedIn: MacSignedInView()
            }
        }
    }
}

/// Production code, not under `#if DEBUG`: the Mac app has no real sign-in. It says so; in a Debug build only, "Use a test account" signs in as Ada Mac.
struct MacSignedOutView: View {
    @Environment(AccountSession.self) private var session
    @State private var problem: String?

    var body: some View {
        VStack(spacing: 16) {
            Image("LimeLogo").resizable().scaledToFit().frame(width: 64, height: 64).accessibilityHidden(true)
            Text("lime on your Mac links to your phone. Coming soon.")
                .font(Theme.title).foregroundStyle(Theme.text).multilineTextAlignment(.center)
            #if DEBUG
            Button("Use a test account") { Task { problem = await MacTestAccount.signIn(session: session) } }
                .buttonStyle(.borderedProminent).tint(Theme.accent).foregroundStyle(Theme.accentInk)
                .accessibilityIdentifier("use-test-account")
            if let problem { Text(problem).font(Theme.secondary).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center) }
            #endif
        }
        .padding(32)
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .limeBackground()
        .accessibilityElement(children: .contain)
    }
}

/// Messages (sidebar) and the selected chat (detail).
private struct MacSignedInView: View {
    @Environment(ConversationStore.self) private var store
    @Environment(AccountSession.self) private var session
    @Environment(NotificationCoordinator.self) private var notifications
    @Environment(MacNavigation.self) private var nav
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        // A plain side-by-side layout, not NavigationSplitView: on macOS 26 its sidebar floats over the detail, and the chat's full-width bars
        // (the composer, the Accept bar) are then laid out at the window's width but drawn from the sidebar's edge, running off the right side.
        HStack(spacing: 0) {
            if nav.columns != .detailOnly {
                MacSidebar()
                    .frame(width: 320)
                    // The wash and the hairline run the full height of the window, through the title-bar area (the list itself stays below it).
                    .background(Theme.surface.opacity(0.5).ignoresSafeArea())
                Divider().ignoresSafeArea(edges: .vertical)
            }
            MacDetail()
                .frame(maxWidth: .infinity)
                // Views that size themselves from the window (the chat's title) should use this pane's width, not the whole window's.
                .onGeometryChange(for: CGSize.self) { $0.size } action: { WindowMetrics.shared.size = $0 }
        }
        .onChange(of: nav.selection) { _, _ in store.path = NavigationPath() }
        .onChange(of: scenePhase, initial: true) { _, phase in
            notifications.isActive = phase == .active
            Task {
                switch phase {
                case .active:
                    store.refreshStorageState()
                    await notifications.releaseHeld()
                    await session.appBecameActive()
                case .background: await session.appLeftForeground()
                default: break
                }
            }
        }
        .task { await notifications.refreshAuthorization() }
    }
}

/// The Messages list: pinned first and unread numbers (ConversationRow), and a Requests entry when there are requests. ↑/↓ move the selection.
private struct MacSidebar: View {
    @Environment(ConversationStore.self) private var store
    @Environment(MacNavigation.self) private var nav

    var body: some View {
        @Bindable var nav = nav
        VStack(spacing: 0) {
        Text("Messages").font(Theme.title).foregroundStyle(Theme.text)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.vertical, 12)
            .accessibilityAddTraits(.isHeader)
        List(selection: $nav.selection) {
            if !store.requests.isEmpty {
                MacRequestsRow(count: store.requests.count)
                    .tag(MacNavigation.requestsID)
                    .listRowBackground(nav.selection == MacNavigation.requestsID ? Theme.accent.opacity(0.3) : Color.clear)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
            }
            ForEach(store.chats) { conversation in
                ConversationRow(conversation: conversation)
                    .tag(conversation.id)
                    .listRowBackground(nav.selection == conversation.id ? Theme.accent.opacity(0.3) : Color.clear)
                    .accessibilityIdentifier("conversation-row-\(conversation.id)")
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        // The system's selection fill is drawn from the tint, with no text colour change: on dark it put pale text on pale green. lime draws its own
        // (a soft lime wash under the row, readable in light and dark), so the system's is turned clear.
        .tint(.clear)
        .accessibilityIdentifier("messages-list")
        }
        .task { if store.isLoaded { await store.reload() } }
    }
}

/// The Requests entry (iOS's is private to MessagesView): a Mac version from the same pieces. Ask for plot-iOS: make `RequestsRow` internal.
private struct MacRequestsRow: View {
    let count: Int
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "envelope.badge").font(.system(size: 22)).foregroundStyle(Theme.accentInk)
                .frame(width: 44, height: 44).background(Theme.accent, in: Circle()).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("Requests").font(Theme.title).foregroundStyle(Theme.text)
                Text(count == 1 ? "1 person wants to message you" : "\(count) people want to message you")
                    .font(Theme.secondary).foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 4)
        }
        .padding(.horizontal, 8).padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Requests, \(count == 1 ? "1 person wants" : "\(count) people want") to message you")
        .accessibilityIdentifier("requests-row")
    }
}

/// The selected chat, or the Requests list, or "Choose a chat". Screens pushed from a chat (a thread, a group, a profile) go on `store.path`, as on the phone.
private struct MacDetail: View {
    @Environment(ConversationStore.self) private var store
    @Environment(MacNavigation.self) private var nav

    var body: some View {
        @Bindable var store = store
        NavigationStack(path: $store.path) {
            Group {
                if nav.selection == MacNavigation.requestsID {
                    RequestsView()
                } else if let id = nav.selection, store.conversation(id) != nil {
                    ChatView(conversationID: id).id(id)
                } else {
                    Text("Choose a chat").font(Theme.title).foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity).limeBackground()
                }
            }
            // A Mac window has no home-indicator safe area, which is what gives the composer its gap under it on iPhone: 12 pt, as in Messages.
            .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: 12) }
            .navigationDestination(for: Conversation.ID.self) { ChatView(conversationID: $0) }
            .navigationDestination(for: ChatTarget.self) { ChatView(conversationID: $0.conversationID, focusMessageID: $0.messageID, focusWords: $0.words) }
            .navigationDestination(for: ThreadTarget.self) { ThreadView(target: $0).limeBack() }
            .navigationDestination(for: GroupTarget.self) { GroupDetailsView(target: $0) }
            .navigationDestination(for: ProfileRoute.self) { ProfileView(route: $0) }
        }
    }
}
