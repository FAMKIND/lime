import SwiftUI

struct MessagesView: View {
    @Environment(ConversationStore.self) private var store
    @Environment(AccountSession.self) private var session
    @Environment(NotificationCoordinator.self) private var notifications
    @State private var showAbout = false
    @State private var showNewMessage = false
    @State private var showSettings = false
    /// The chat a swipe asked about: to mute (it asks for how long) or to delete (it asks to confirm).
    @State private var muting: Conversation.ID?
    @State private var deleting: Conversation.ID?

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
        List {
            Group {
                if let problem = store.problem { ProblemBanner(problem: problem) }
                if store.showsRecoveryNotice { RecoveryNotice() }
                if !store.requests.isEmpty { RequestsRow(count: store.requests.count) }
                if store.isLoaded && store.chats.isEmpty && store.requests.isEmpty {
                    EmptyChatsView(onNewMessage: { showNewMessage = true })
                }
            }
            .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            ForEach(store.chats) { conversation in
                Button { store.path.append(conversation.id) } label: { ConversationRow(conversation: conversation) }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("conversation-row-\(conversation.id)")
                    .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12))
                    .listRowSeparator(.hidden)
                    // The swiped chat stays highlighted while its mute choices are open.
                    .listRowBackground(muting == conversation.id ? Theme.surface : Color.clear)
                    // Swipe left: Delete and Mute. Swipe right: Unread/Read and Pin/Unpin.
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button { deleting = conversation.id } label: { Label("Delete", systemImage: "trash") }
                            .tint(.red).accessibilityIdentifier("swipe-delete-\(conversation.id)")
                        if notifications.settings.isMuted(conversation.id) {
                            Button { notifications.settings.unmute(conversation.id) } label: { Label("Unmute", systemImage: "bell") }
                                .tint(.orange).accessibilityIdentifier("swipe-unmute-\(conversation.id)")
                        } else {
                            Button { muting = conversation.id } label: { Label("Mute", systemImage: "bell.slash") }
                                .tint(.orange).accessibilityIdentifier("swipe-mute-\(conversation.id)")
                        }
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button { Task { await store.setMarkedUnread(conversation.id, !conversation.isUnread) } } label: {
                            Label(conversation.isUnread ? "Read" : "Unread", systemImage: conversation.isUnread ? "envelope.open" : "envelope.badge")
                        }
                        .tint(.blue).accessibilityIdentifier("swipe-unread-\(conversation.id)")
                        Button { pinChanged(conversation) } label: {
                            Label(conversation.isPinned ? "Unpin" : "Pin", systemImage: conversation.isPinned ? "pin.slash" : "pin")
                        }
                        .tint(.gray).accessibilityIdentifier("swipe-pin-\(conversation.id)")
                    }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, top, for: .scrollContent)
        .contentMargins(.bottom, bottom, for: .scrollContent)
        .accessibilityIdentifier("messages-list")
        .refreshable { await store.pullToRefresh() }
        .animation(.snappy, value: store.chats.map(\.id))
        .confirmationDialog(muteTitle, isPresented: Binding(get: { muting != nil }, set: { if !$0 { muting = nil } }), titleVisibility: .visible) {
            ForEach(MuteDuration.allCases) { duration in
                Button(duration.title) {
                    if let id = muting { notifications.settings.mute(id, for: duration) }
                    muting = nil
                }
                .accessibilityIdentifier("mute-\(duration.rawValue)")
            }
            Button("Cancel", role: .cancel) { muting = nil }
        }
        .confirmationDialog(deleteTitle, isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button(deleteButton, role: .destructive) {
                if let id = deleting { Task { await store.deleteChat(id) } }
                deleting = nil
            }
            .accessibilityIdentifier("delete-chat-confirm")
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: {
            Text(deleteMessage)
        }
    }

    private var muteTitle: String { "Mute \(muting.flatMap { id in store.chats.first { $0.id == id }?.title } ?? "chat")" }

    /// Pin or unpin: let the swipe close first, then the row slides to its place (the list animates the move; ids are stable).
    private func pinChanged(_ conversation: Conversation) {
        let id = conversation.id, pin = !conversation.isPinned
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            await store.setPinned(id, pin)
        }
    }

    private var deletingGroup: Bool { deleting.map { $0.hasPrefix("grp:") } ?? false }
    private var deleteTitle: String { deletingGroup ? "Leave and delete this group?" : "Delete chat?" }
    private var deleteButton: String { deletingGroup ? "Leave and delete" : "Delete chat" }
    private var deleteMessage: String {
        deletingGroup ? "You'll leave the group, and its messages will be removed from this phone."
                      : "This removes it from this phone. The other person keeps their copy."
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

/// What a row of the Messages list says about the newest thing in a conversation (a reply included), in parts so it can be drawn
/// with a small symbol and tested without a screen.
struct ListPreview: Equatable {
    /// "↩ Jean: " (a reply), "Jean: " (a group message), or nothing.
    var prefix = ""
    /// A symbol for pictures, video, voice messages and files.
    var symbol: String?
    var text = ""

    var plain: String { prefix + text }

    static func make(_ conversation: Conversation) -> ListPreview {
        guard let last = conversation.lastMessage else { return ListPreview() }
        if last.isSystem { return ListPreview(text: last.text) }
        if last.deleted { return ListPreview(text: "This message was deleted") }
        var line = ListPreview()
        // Who wrote it: always named for a reply ("↩ Jean: ..."), and in a group.
        let sender = last.isOwn ? "You" : conversation.members.first(where: { $0.id == last.senderID }).map { String($0.name.split(separator: " ").first ?? "") }
        if conversation.latestIsReply, let sender {
            line.prefix = "↩ \(sender): "
        } else if conversation.isGroup, !last.isOwn, let sender {
            line.prefix = "\(sender): "
        }
        // The words, without the markup (a list reads as its items).
        let words = messagePlainText(text: last.text).replacingOccurrences(of: "\n", with: " ")
        if let summary = AttachmentFormat.summary(last.attachments) {
            line.symbol = AttachmentFormat.symbol(last.attachments)
            line.text = words.isEmpty ? summary : "\(summary) · \(words)"
        } else {
            line.text = words
        }
        return line
    }
}

struct ConversationRow: View {
    let conversation: Conversation
    @Environment(NotificationCoordinator.self) private var notifications
    @ScaledMetric(relativeTo: .body) private var avatarSize: CGFloat = 52

    /// The photo or video thumbnail in the preview line (32-36 pt).
    static let thumbnailSize: CGFloat = 34

    private var line: ListPreview { ListPreview.make(conversation) }
    private var preview: String { line.plain }
    private var time: String { MessageFormat.listTime(conversation.lastMessage?.date) }
    /// My private label for the person (a one-to-one chat).
    private var label: String? { conversation.isGroup ? nil : conversation.members.first?.label }
    /// A picture or video in the newest message: its tiny thumbnail goes at the trailing edge.
    private var thumbnail: UIImage? {
        guard let item = conversation.lastMessage?.attachments.first(where: { $0.kind == .image || $0.kind == .video }), !item.thumb.isEmpty else { return nil }
        return UIImage(data: item.thumb).map(Self.squareCrop)
    }

    /// The middle square of a picture, so the thumbnail is exactly square (an image that is cropped by a frame still reports its full width).
    private static func squareCrop(_ image: UIImage) -> UIImage {
        let side = min(image.size.width, image.size.height)
        guard side > 0, image.size.width != image.size.height else { return image }
        let format = UIGraphicsImageRendererFormat(); format.scale = image.scale
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            image.draw(at: CGPoint(x: (side - image.size.width) / 2, y: (side - image.size.height) / 2))
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ConversationAvatar(conversation: conversation, size: avatarSize)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(conversation.title)
                        .font(Theme.title)
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                        .layoutPriority(2)
                        .accessibilityIdentifier("row-title-\(conversation.id)")
                    if let label {
                        LabelCapsule(text: label, id: "row-label-\(conversation.id)")
                    }
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
                            .accessibilityIdentifier("pinned-\(conversation.id)")
                    }
                    Spacer(minLength: 4)
                    Text(time)
                        .font(Theme.secondary)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize()
                }
                HStack(alignment: .center, spacing: 8) {
                    previewText
                        .font(Theme.secondary)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("row-preview-\(conversation.id)")
                    if let thumbnail {
                        Image(uiImage: thumbnail).resizable().scaledToFit()
                            .frame(width: Self.thumbnailSize, height: Self.thumbnailSize)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .accessibilityElement(children: .ignore)
                            .accessibilityIdentifier("row-thumb-\(conversation.id)")
                    }
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
        // The marked-unread dot sits to the left of the avatar, like Mail and Messages.
        .overlay(alignment: .topLeading) {
            if conversation.markedUnread && conversation.unread == 0 {
                Circle().fill(Theme.accent).frame(width: 9, height: 9)
                    .offset(x: -3, y: 12 + avatarSize / 2 - 4.5)
                    .accessibilityIdentifier("unread-dot-\(conversation.id)")
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(conversation.title)\(label.map { " (\($0))" } ?? "")\(conversation.isPinned ? ", pinned" : "")\(notifications.settings.isMuted(conversation.id) ? ", muted" : ""), \(preview), \(time)\(conversation.unread > 0 ? ", \(conversation.unread) unread" : (conversation.markedUnread ? ", unread" : ""))")
        .accessibilityAddTraits(.isButton)
    }

    /// The preview with its symbol (a camera for a picture, a microphone for a voice message...).
    private var previewText: Text {
        if let symbol = line.symbol { return Text("\(line.prefix)\(Image(systemName: symbol)) \(line.text)") }
        return Text(line.plain)
    }
}
