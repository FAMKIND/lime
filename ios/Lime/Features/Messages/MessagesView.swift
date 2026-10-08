import SwiftUI

struct MessagesView: View {
    @Environment(ConversationStore.self) private var store
    @Environment(AccountSession.self) private var session
    @Environment(NotificationCoordinator.self) private var notifications
    @State private var showAbout = false
    @State private var showNewMessage = false
    @State private var showSettings = false

    var body: some View {
        Group {
            if #available(iOS 26, *) {
                nativeBody
            } else {
                legacyBody
            }
        }
        .sheet(isPresented: $showAbout) { AboutView() }
        .sheet(isPresented: $showNewMessage) { NewMessageSheet() }
        .sheet(isPresented: $showSettings) { SettingsView() }
        #if DEBUG
        .task {
            if store.demoNotification == "banner" {
                try? await Task.sleep(for: .milliseconds(500))
                await notifications.announce([IncomingMessage(
                    id: "demo-banner", conversationID: "dm:lee", conversationTitle: "Lee Wong", senderID: "lee", senderName: "Lee Wong",
                    text: "Can you cover my bus duty on Friday? I have a dentist appointment.", threadRoot: nil, isGroup: false, isRequest: false, date: Date())])
            }
            if store.demoSheet == "settings" { showSettings = true }
            else if store.demoSheet != nil { showNewMessage = true }
        }
        #endif
    }

    // MARK: iOS 26+: the system toolbar and scroll edge effect (as in Apple Messages)

    @available(iOS 26, *)
    private var nativeBody: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()
            list(top: 8, bottom: 24)
                .scrollEdgeEffectStyle(.soft, for: .top)
                .scrollEdgeEffectStyle(.soft, for: .bottom)
        }
        .safeAreaBar(edge: .bottom) { DockBar().padding(.bottom, 8) }
        .overlay(alignment: .bottomTrailing) { newMessageButton.padding(.trailing, 20).padding(.bottom, 92) }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { store.comingSoon() } label: {
                    Image("LimeLogo").renderingMode(.original).resizable().scaledToFit()
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                        #if DEBUG
                        .onLongPressGesture(minimumDuration: 0.6) { showAbout = true }
                        #endif
                }
                .accessibilityLabel("Lime menu")
                .accessibilityHint("Press and hold for About Lime")
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { store.path.append(MessagesRoute.search) } label: { Image(systemName: "magnifyingglass") }
                    .accessibilityLabel("Search")
                    .accessibilityIdentifier("messages-search-button")
                Button { showSettings = true } label: { AvatarView(person: session.mePerson, size: 30) }
                    .accessibilityLabel("Settings")
                    .accessibilityIdentifier("settings-button")
            }
        }
    }

    // MARK: iOS 17-25: custom glass pills and a subtle top veil

    private var legacyBody: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()
            list(top: 76, bottom: 170)
        }
        .overlay(alignment: .top) { TopFade() }
        .overlay(alignment: .top) { TopControls(onAbout: { showAbout = true }, onSettings: { showSettings = true }) }
        .overlay(alignment: .bottomTrailing) { newMessageButton.padding(.trailing, 20).padding(.bottom, 92) }
        .overlay(alignment: .bottom) { DockBar().padding(.bottom, 8) }
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: Shared

    private func list(top: CGFloat, bottom: CGFloat) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if let problem = store.problem { ProblemBanner(problem: problem) }
                if store.showsRecoveryNotice { RecoveryNotice() }
                if !store.requests.isEmpty { RequestsRow(count: store.requests.count) }
                if store.isLoaded && store.chats.isEmpty && store.requests.isEmpty {
                    EmptyChatsView(onNewMessage: { showNewMessage = true })
                }
                ForEach(store.chats) { conversation in
                    NavigationLink(value: conversation.id) {
                        ConversationRow(conversation: conversation)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("conversation-row-\(conversation.id)")
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, top)
            .padding(.bottom, bottom)
        }
        .accessibilityIdentifier("messages-list")
        .refreshable { await store.syncNow() }
    }

    private var newMessageButton: some View {
        Button { showNewMessage = true } label: {
            Image(systemName: "plus")
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(Theme.accentInk)
                .frame(width: 64, height: 64)
                .background(Theme.accent, in: Circle())
                .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        }
        .accessibilityLabel("New message")
        .accessibilityIdentifier("new-message-button")
    }
}

/// Why Lime cannot reach the server right now, in true words. A session that ended asks the person to
/// sign in again (their chats and keys stay on the phone).
private struct ProblemBanner: View {
    @Environment(AccountSession.self) private var session
    let problem: ConnectionProblem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(problem.message)
                .font(Theme.secondary)
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("problem-message")
            if problem.needsSignIn {
                Button { Task { await session.endSession() } } label: {
                    Text("Sign in").font(Theme.secondary.weight(.semibold)).foregroundStyle(Theme.accentInk)
                        .padding(.horizontal, 18).frame(minHeight: 40)
                        .background(Theme.accent, in: Capsule())
                }
                .accessibilityIdentifier("problem-sign-in")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("problem-banner")
    }
}

/// The first row of Messages while strangers' first messages are waiting.
private struct RequestsRow: View {
    let count: Int

    var body: some View {
        NavigationLink(value: MessagesRoute.requests) {
            HStack(spacing: 12) {
                Image(systemName: "envelope.badge")
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.accentInk)
                    .frame(width: 52, height: 52)
                    .background(Theme.accent, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Requests").font(Theme.title).foregroundStyle(Theme.text)
                    Text(count == 1 ? "1 person wants to message you" : "\(count) people want to message you")
                        .font(Theme.secondary).foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 4)
                Text("\(count)")
                    .font(Theme.caption.weight(.semibold))
                    .foregroundStyle(Theme.accentInk)
                    .frame(minWidth: 22)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Theme.accent, in: Capsule())
            }
            .padding(.horizontal, 8).padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Requests, \(count == 1 ? "1 person wants" : "\(count) people want") to message you")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("requests-row")
    }
}

/// A new account's Messages: nothing yet, and two ways to start (both come next).
private struct EmptyChatsView: View {
    @Environment(ConversationStore.self) private var store
    let onNewMessage: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 6) {
                Text("No chats yet")
                    .font(.system(.title2, design: .default, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .accessibilityIdentifier("empty-title")
                Text("Get started")
                    .font(Theme.body)
                    .foregroundStyle(Theme.textSecondary)
            }
            VStack(spacing: 12) {
                card("New message", detail: "Message a teacher you know", symbol: "square.and.pencil", id: "card-new-message", action: onNewMessage)
                card("Invite a teacher", detail: "Bring a colleague to Lime", symbol: "person.badge.plus", id: "card-invite") { store.comingNext("Invite a teacher") }
            }
        }
        .padding(.top, 48)
        .padding(.horizontal, 12)
    }

    private func card(_ title: String, detail: String, symbol: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.accentInk)
                    .frame(width: 48, height: 48)
                    .background(Theme.accent, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Theme.title).foregroundStyle(Theme.text)
                    Text(detail).font(Theme.secondary).foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}

/// A non-blocking card shown once when the previous data on this phone could not be opened.
private struct RecoveryNotice: View {
    @Environment(ConversationStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Lime couldn't open the data saved on this phone, so it started fresh. Your chats will come back when you restore from your recovery key.")
                .font(Theme.secondary)
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("recovery-notice")
            Button("OK") { store.dismissRecoveryNotice() }
                .font(Theme.secondary.weight(.semibold))
                .foregroundStyle(Theme.text)
                .accessibilityIdentifier("recovery-notice-dismiss")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
        .onAppear { store.recoveryNoticeAppeared() }
    }
}

private struct TopControls: View {
    @Environment(ConversationStore.self) private var store
    @Environment(AccountSession.self) private var session
    let onAbout: () -> Void
    let onSettings: () -> Void

    var body: some View {
        HStack {
            Button { store.comingSoon() } label: {
                Image("LimeLogo")
                    .resizable().scaledToFit()
                    .frame(width: 34, height: 34)
                    .frame(width: 48, height: 48)
                    .limeGlass()
            }
            .accessibilityLabel("Lime menu")
            .accessibilityHint("Press and hold for About Lime")
            #if DEBUG
            .simultaneousGesture(LongPressGesture(minimumDuration: 0.6).onEnded { _ in onAbout() })
            #endif
            Spacer()
            HStack(spacing: 12) {
                Button { store.path.append(MessagesRoute.search) } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(Theme.text)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Search")
                .accessibilityIdentifier("messages-search-button")
                Button(action: onSettings) {
                    AvatarView(person: session.mePerson, size: 36)
                }
                .accessibilityLabel("Settings")
                .accessibilityIdentifier("settings-button")
            }
            .padding(.horizontal, 8).padding(.vertical, 2)
            .limeGlass()
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }
}

struct ConversationRow: View {
    let conversation: Conversation
    @Environment(NotificationCoordinator.self) private var notifications
    @ScaledMetric(relativeTo: .body) private var avatarSize: CGFloat = 52

    private var preview: String {
        guard let last = conversation.lastMessage else { return "" }
        if last.isSystem { return last.text }
        // The words, without the markup (a list reads as its items).
        let words = messagePlainText(text: last.text).replacingOccurrences(of: "\n", with: " ")
        if conversation.isGroup, let sender = conversation.members.first(where: { $0.id == last.senderID }) {
            return "\(sender.name.split(separator: " ").first ?? ""): \(words)"
        }
        return words
    }

    private var time: String { MessageFormat.listTime(conversation.lastMessage?.date) }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ConversationAvatar(conversation: conversation, size: avatarSize)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(conversation.title)
                        .font(Theme.title)
                        .foregroundStyle(Theme.text)
                        .lineLimit(2)
                    if notifications.settings.isMuted(conversation.id) {
                        Image(systemName: "bell.slash.fill")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .accessibilityIdentifier("muted-\(conversation.id)")
                    }
                    if conversation.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .accessibilityHidden(true)
                    }
                    Spacer(minLength: 4)
                    Text(time)
                        .font(Theme.secondary)
                        .foregroundStyle(Theme.textSecondary)
                }
                HStack(alignment: .top, spacing: 8) {
                    Text(preview)
                        .font(Theme.secondary)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if conversation.unread > 0 {
                        Text("\(conversation.unread)")
                            .font(Theme.caption.weight(.semibold))
                            .foregroundStyle(Theme.accentInk)
                            .frame(minWidth: 22)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Theme.accent, in: Capsule())
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(conversation.title)\(conversation.isPinned ? ", pinned" : "")\(notifications.settings.isMuted(conversation.id) ? ", muted" : ""), \(preview), \(time)\(conversation.unread > 0 ? ", \(conversation.unread) unread" : "")")
        .accessibilityAddTraits(.isButton)
    }
}
