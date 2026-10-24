import SwiftUI

/// Opens a person's profile (LIME-122a). `conversationID` is where it was opened from, which decides what "Shared" shows: a DM, or a
/// group (then only what this person shared there). `callIDs` narrows the Calls section to one group of calls (from a call row).
struct ProfileRoute: Hashable {
    let userID: String
    let name: String
    var conversationID: String? = nil
    var callIDs: [String]? = nil
    /// Your own profile.
    var isMe = false

    /// Whose items the Shared lists show: everyone in a DM, this person in a group.
    var sharedSender: String? { (conversationID ?? "").hasPrefix("grp:") ? userID : nil }
    var sharedConversation: String { conversationID ?? "dm:\(userID)" }
    var isGroupContext: Bool { (conversationID ?? "").hasPrefix("grp:") }
}

/// A full list of one kind of shared thing (the "See all" of the profile's Shared section).
struct SharedListRoute: Hashable {
    let conversationID: String
    let sender: String?
    let kind: SharedKindKey
    let title: String
}

/// `SharedKind` is a generated type; this is its hashable stand-in for navigation.
enum SharedKindKey: String, Hashable { case media, files, links
    var kind: SharedKind { switch self { case .media: .media; case .files: .files; case .links: .links } }
}

struct SettingsLaunch: Identifiable {
    let id = UUID()
    let start: SettingsRoute?
}

struct ProfileView: View {
    let route: ProfileRoute
    @Environment(ConversationStore.self) private var store
    @Environment(NotificationCoordinator.self) private var notifications
    @Environment(AccountSession.self) private var session
    @State private var confirmingMute = false
    @State private var confirmingBlock = false
    @State private var confirmingDelete = false
    @State private var confirmingSignOut = false
    @State private var showStatus = false
    /// Settings as a sheet, opened on the root or straight on a screen (Edit profile).
    @State private var settingsLaunch: SettingsLaunch?
    @State private var verifying = false
    @State private var showStorage = false
    @State private var section: Section = .info
    @State private var copied = false
    @State private var labelling = false
    @State private var labelText = ""

    /// Their jam's page, when they have one (LIME-188d: Posts is a section only then).
    @State private var jamPage: JamPageInfo?

    /// The sections, in order (LIME-188x). Activity waits for LIME-189 and says so calmly; Comments and Replies come back with it if they are needed.
    enum Section: String, CaseIterable { case info = "Info", posts = "Posts", articles = "Articles", podcasts = "Podcasts", orgs = "Orgs", activity = "Activity", shared = "Shared", calls = "Calls" }

    private var conversation: Conversation? { store.conversation("dm:\(route.userID)") }
    private var person: Person {
        if route.isMe { return session.mePerson }
        return conversation?.members.first ?? Person(id: route.userID, name: route.name, tone: AvatarTone.tone(for: route.userID))
    }
    /// Their public profile; for me, what my own account says.
    private var profile: PublicProfile? {
        if route.isMe, let mine = session.profile {
            return PublicProfile(userId: route.userID, displayName: mine.displayName, username: mine.username, school: mine.school, aboutEmoji: mine.aboutEmoji, aboutText: mine.aboutText)
        }
        return store.publicProfiles[route.userID]
    }
    private var displayName: String { (profile?.displayName).flatMap { $0.isEmpty ? nil : $0 } ?? route.name }
    private var accepted: Bool { !route.isMe && (conversation.map { !$0.isRequest } ?? false) }
    private var statusLine: String? {
        guard let status = store.status(of: route.userID) else { return nil }
        return StatusPlan.caption(state: status.state, until: status.until)
    }
    /// Mine, from a group: what I shared there; from the header: nothing.
    private var sharedSender: String? { route.isMe ? "me" : route.sharedSender }
    private var hasSharedContext: Bool { !route.isMe || route.conversationID != nil }
    private var sharedMedia: [Message] { hasSharedContext ? store.shared(in: route.sharedConversation, from: sharedSender, kind: .media) : [] }
    private var sharedFiles: [Message] { hasSharedContext ? store.shared(in: route.sharedConversation, from: sharedSender, kind: .files) : [] }
    private var sharedLinks: [Message] { hasSharedContext ? store.shared(in: route.sharedConversation, from: sharedSender, kind: .links) : [] }
    private var calls: [CallRecord] {
        if route.isMe { return [] }
        if let ids = route.callIDs { return CallLog.shared.records.filter { ids.contains($0.id) } }
        return Array(CallLog.shared.records(with: route.userID).prefix(10))
    }
    /// Their posts shown as themselves (LIME-188x); the ones shown as an org are on the org's page.
    private var ownPosts: [JamPostInfo] { jamPage.map { store.profilePosts(jamID: $0.jamId, isMe: route.isMe) } ?? [] }
    /// Someone else's posts are readable once you subscribe: before that, Posts says so.
    private var postsLocked: Bool { jamPage.map { !route.isMe && !store.isFollowing($0.jamId) } ?? false }
    private var orgs: [JamPageInfo] { store.profileOrgs(page: jamPage, personName: displayName) }
    private var sections: [Section] {
        var list: [Section] = [.info]
        let kinds = Set(ownPosts.map(\.kind))
        if postsLocked || kinds.contains("quick") { list.append(.posts) }
        if !postsLocked && kinds.contains("article") { list.append(.articles) }
        if !postsLocked && kinds.contains("record") { list.append(.podcasts) }
        if !orgs.isEmpty { list.append(.orgs) }
        list.append(.activity)
        if !sharedMedia.isEmpty || !sharedFiles.isEmpty || !sharedLinks.isEmpty { list.append(.shared) }
        if !calls.isEmpty { list.append(.calls) }
        return list
    }

    var body: some View {
        let available = sections
        ScrollView {
            VStack(spacing: 18) {
                top
                if route.isMe { myActions } else if accepted { actions }
                ProfileTabs(sections: available, selection: $section, badged: route.isMe && store.jamHasUnseen() ? [.activity] : [])
                switch section {
                case .info: info
                case .posts: JamProfilePosts(posts: ownPosts.filter { $0.kind == "quick" }, locked: postsLocked)
                case .articles: JamProfilePosts(posts: ownPosts.filter { $0.kind == "article" }, locked: false)
                case .podcasts: JamProfilePosts(posts: ownPosts.filter { $0.kind == "record" }, locked: false)
                case .orgs: JamOrgsSection(orgs: orgs, isMe: route.isMe)
                case .activity: JamActivityList(userID: route.userID, isMe: route.isMe)
                case .shared: shared
                case .calls: callsList
                }
                if route.isMe {
                    SettingsCard {
                        Button { confirmingSignOut = true } label: {
                            SettingsRowLabel(symbol: "rectangle.portrait.and.arrow.right", title: "Sign out", showsDivider: false, destructive: true)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("profile-sign-out")
                    }
                    .padding(.top, 12)
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 40)
        }
        .background(Theme.canvas.ignoresSafeArea().accessibilityIdentifier("profile-screen"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar { toolbarItems }
        .task { await store.loadProfile(route.userID) }
        .task(id: route.userID) { await loadJam() }
        .onChange(of: store.jamsMine) { _, _ in if route.isMe { Task { await loadJam() } } }
        .onAppear { if route.callIDs != nil, available.contains(.calls) { section = .calls } }
        .sheet(isPresented: $labelling) {
            LabelSheet(name: displayName, text: $labelText) { saved in
                labelling = false
                if saved { Task { await store.setLabel(labelText, for: route.userID) } }
            }
        }
        .sheet(isPresented: $showStatus) { StatusSheet(openSettings: { showStatus = false; settingsLaunch = SettingsLaunch(start: nil) }) }
        .sheet(item: $settingsLaunch) { SettingsView(startAt: $0.start) }
        .sheet(isPresented: $verifying) { NavigationStack { ScanQRScreen(closeSheet: { verifying = false }) }.presentationDetents([.large]) }
        .sheet(isPresented: $showStorage) { NavigationStack { ChatMediaScreen(conversationID: "dm:\(route.userID)") }.presentationDetents([.large]) }
        .confirmSheet("Mute \(displayName)", isPresented: $confirmingMute) {
            ForEach(MuteDuration.allCases) { duration in
                Button(duration.title) { notifications.settings.mute("dm:\(route.userID)", for: duration) }
                    .accessibilityIdentifier("mute-\(duration.rawValue)")
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmSheet("Block \(displayName)?", isPresented: $confirmingBlock) {
            Button("Block", role: .destructive) {
                Task { await store.block("dm:\(route.userID)"); store.path = NavigationPath(); store.callPath = NavigationPath() }
            }
            .accessibilityIdentifier("profile-block-confirm")
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("They will no longer be able to message or call you.")
        }
        .confirmSheet("Delete chat?", isPresented: $confirmingDelete) {
            Button("Delete chat", role: .destructive) {
                Task { await store.deleteChat("dm:\(route.userID)"); store.path = NavigationPath(); store.callPath = NavigationPath() }
            }
            .accessibilityIdentifier("profile-delete-confirm")
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes it from this phone. The other person keeps their copy.")
        }
        .confirmSheet("Sign out of lime?", isPresented: $confirmingSignOut) {
            Button("Sign out and remove messages from this iPhone", role: .destructive) {
                Task { await session.signOut() }
            }
            .accessibilityIdentifier("profile-sign-out-confirm")
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(SignOutCopy.warning)
        }
        .overlay(alignment: .bottom) {
            if copied {
                Text("Copied").font(Theme.font(.footnote, weight: .medium)).foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8).background(.black.opacity(0.7), in: Capsule())
                    .padding(.bottom, 30).accessibilityIdentifier("profile-copied")
            }
        }
    }

    // MARK: Sections

    /// What a section that waits for LIME-189 shows.
    private func emptySection(_ line: String, id: String) -> some View {
        Text(line).font(Theme.body).foregroundStyle(Theme.textSecondary).frame(maxWidth: .infinity).padding(.top, 24)
            .accessibilityIdentifier("profile-empty-\(id)")
    }

    private func loadJam() async {
        if route.isMe { jamPage = store.jamsMine.first.map { JamPageInfo(jamId: $0.jamId, writerId: $0.writer, title: $0.title, about: $0.about, topics: $0.topics, postCount: $0.postCount, subscriberCount: $0.subscriberCount) } }
        else { jamPage = await store.jamPage(of: route.userID) }
    }

    // MARK: The top

    private var top: some View {
        VStack(spacing: 6) {
            AvatarView(person: person, size: 96, showsStatus: true).padding(.top, 12)
            HStack(spacing: 6) {
                Text(displayName).font(Theme.font(.title2, weight: .semibold)).foregroundStyle(Theme.text)
                    .accessibilityIdentifier("profile-name")
                if conversation?.verified == true {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.text).font(Theme.font(.callout)).accessibilityLabel("Verified in person")
                }
            }
            let line = [profile?.username.map { "@\($0)" }, profile?.school, orgs.first?.title].compactMap { $0 }.joined(separator: " \u{00B7} ")
            // `@handle · org · Subscribe` (LIME-188x): Subscribe is a green link at the end of the line.
            HStack(spacing: 6) {
                if !line.isEmpty {
                    Text(line).font(Theme.secondary).foregroundStyle(Theme.textSecondary).accessibilityIdentifier("profile-handle")
                }
                if let jamPage, !route.isMe {
                    if !line.isEmpty { Text("\u{00B7}").font(Theme.secondary).foregroundStyle(Theme.textSecondary).accessibilityHidden(true) }
                    SubscribeLink(page: jamPage)
                }
            }
            if let statusLine {
                Text(statusLine).font(Theme.secondary).foregroundStyle(Theme.textSecondary).accessibilityIdentifier("profile-status")
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: 12) {
            if accepted {
                card("message", "Message", id: "profile-message") { store.openFromNotification("dm:\(route.userID)", thread: nil) }
                card("phone", "Voice", id: "profile-voice") { Task { _ = await store.calls.start(peerID: route.userID, name: displayName, video: false) } }
                card("video", "Video", id: "profile-video") { Task { _ = await store.calls.start(peerID: route.userID, name: displayName, video: true) } }
            }
        }
    }

    /// Your own profile: Change status, Edit profile, Settings.
    private var myActions: some View {
        HStack(spacing: 12) {
            card("dot.radiowaves.left.and.right", "Status", id: "profile-change-status") { showStatus = true }
            card("pencil", "Edit profile", id: "profile-edit") { settingsLaunch = SettingsLaunch(start: .profile) }
            card("gearshape", "Settings", id: "profile-settings") { settingsLaunch = SettingsLaunch(start: nil) }
        }
    }

    private func card(_ symbol: String, _ title: String, id: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 20)).frame(height: 24)
                Text(title).font(Theme.secondary)
            }
            .foregroundStyle(Theme.text)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    /// Top right: someone's profile has Mute (the bell), Pin and ⋯; your own has ⋯ only.
    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            if !route.isMe, let conversation, accepted {
                let muted = notifications.settings.isMuted(conversation.id)
                Button {
                    if muted { notifications.settings.unmute(conversation.id) } else { confirmingMute = true }
                } label: { Image(systemName: muted ? "bell.slash" : "bell") }
                .accessibilityLabel(muted ? "Unmute" : "Mute").accessibilityIdentifier("profile-mute")
                Button { Task { await store.setPinned(conversation.id, !conversation.isPinned) } } label: {
                    Image(systemName: conversation.isPinned ? "pin.slash" : "pin")
                }
                .accessibilityLabel(conversation.isPinned ? "Unpin" : "Pin").accessibilityIdentifier("profile-pin")
            }
            moreMenu
        }
    }

    @ViewBuilder
    private var moreMenu: some View {
        Menu {
            if let username = profile?.username, let url = URL(string: InviteLink.url(username: username)) {
                ShareLink(item: url, message: Text("\(displayName) on lime")) { Label("Share profile", systemImage: "square.and.arrow.up") }
                    .accessibilityIdentifier("profile-share")
            }
            if route.isMe {
                Button { settingsLaunch = SettingsLaunch(start: .profile) } label: { Label("Edit profile", systemImage: "pencil") }
                Button { settingsLaunch = SettingsLaunch(start: nil) } label: { Label("Settings", systemImage: "gearshape") }
            } else if accepted {
                Button { verifying = true } label: { Label("Verify in person", systemImage: "qrcode.viewfinder") }
                    .accessibilityIdentifier("profile-verify")
                Button { showStorage = true } label: { Label("Storage", systemImage: "internaldrive") }
                    .accessibilityIdentifier("profile-storage")
                Button(role: .destructive) { confirmingBlock = true } label: { Label("Block \(displayName)", systemImage: "hand.raised") }
                    .accessibilityIdentifier("profile-block")
                Button(role: .destructive) { confirmingDelete = true } label: { Label("Delete chat", systemImage: "trash") }
                    .accessibilityIdentifier("profile-delete")
            }
        } label: { Image(systemName: "ellipsis") }
        .accessibilityLabel("More").accessibilityIdentifier("profile-more")
    }

    // MARK: Info

    @ViewBuilder
    private var info: some View {
        let about = [profile?.aboutEmoji, profile?.aboutText].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        if !about.isEmpty {
            titledCard("About") {
                Text(about).font(Theme.body).foregroundStyle(Theme.text).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18).padding(.vertical, 14).accessibilityIdentifier("profile-about")
            }
        }
        titledCard("Details") {
            VStack(spacing: 0) {
                if let username = profile?.username {
                    row("At", value: "@\(username)", id: "profile-handle") {
                        UIPasteboard.general.string = username
                        copied = true
                        Task { try? await Task.sleep(for: .seconds(1.5)); copied = false }
                    }
                }
                if let school = profile?.school { row("School", value: school, id: "profile-school") }
                if accepted {
                    row("My label", value: person.label ?? "Add a label", id: "profile-label") {
                        labelText = person.label ?? ""
                        labelling = true
                    }
                }
                if conversation?.verified == true { row("Verified", value: "Verified in person", id: "profile-verified") }
                if profile == nil && !accepted { Text("Nothing more to show.").font(Theme.secondary).foregroundStyle(Theme.textSecondary).padding(18) }
            }
        }
    }

    private func row(_ title: String, value: String, id: String, action: (() -> Void)? = nil) -> some View {
        Group {
            if let action {
                Button(action: action) { rowBody(title, value) }.buttonStyle(.plain)
            } else {
                rowBody(title, value)
            }
        }
        .accessibilityIdentifier(id)
    }

    private func rowBody(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title == "At" ? "Username" : title).font(Theme.body).foregroundStyle(Theme.text)
            Spacer(minLength: 12)
            Text(value).font(Theme.body).foregroundStyle(Theme.textSecondary).lineLimit(1)
        }
        .padding(.horizontal, 18).frame(minHeight: 50)
        .contentShape(Rectangle())
    }

    private func titledCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(Theme.font(.subheadline, weight: .semibold)).foregroundStyle(Theme.textSecondary).padding(.leading, 6)
            content().background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    // MARK: Shared

    @ViewBuilder
    private var shared: some View {
        let context = route.isGroupContext ? "Shared in \(store.conversation(route.sharedConversation)?.title ?? "this group")" : "Shared"
        Text(context).font(Theme.font(.subheadline, weight: .semibold)).foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 6).accessibilityIdentifier("profile-shared-title")
        let media = sharedMedia, files = sharedFiles, links = sharedLinks
        if !media.isEmpty {
            sharedHeader("Media", count: media.count, key: .media)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3), spacing: 4) {
                ForEach(Array(media.flatMap { m in m.attachments.filter { $0.kind == .image || $0.kind == .video }.map { (m, $0) } }.prefix(9)), id: \.1.id) { message, item in
                    MediaCell(item: item)
                        .onTapGesture { store.attachmentViewer = AttachmentViewerRequest(items: [item], index: 0, messageID: message.id, conversationID: route.sharedConversation) }
                }
            }
            .accessibilityIdentifier("profile-media")
        }
        if !files.isEmpty {
            sharedHeader("Files", count: files.count, key: .files)
            VStack(spacing: 0) { ForEach(files.prefix(5)) { FileRow(message: $0) } }
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .accessibilityIdentifier("profile-files")
        }
        if !links.isEmpty {
            sharedHeader("Links", count: links.count, key: .links)
            VStack(spacing: 0) { ForEach(links.prefix(5)) { LinkRow(message: $0) } }
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .accessibilityIdentifier("profile-links")
        }
    }

    private func sharedHeader(_ title: String, count: Int, key: SharedKindKey) -> some View {
        HStack {
            Text(title).font(Theme.title)
            Spacer()
            if count > (key == .media ? 9 : 5) {
                NavigationLink(value: SharedListRoute(conversationID: route.sharedConversation, sender: sharedSender, kind: key, title: title)) {
                    Text("See all").font(Theme.secondary).foregroundStyle(Theme.textSecondary)
                }
                .accessibilityIdentifier("profile-see-all-\(key.rawValue)")
            }
        }
        .foregroundStyle(Theme.text).padding(.top, 6)
    }

    // MARK: Calls

    private var callsList: some View {
        VStack(spacing: 0) {
            ForEach(calls) { call in CallLine(call: call) }
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

/// One call on one line: direction glyph, Voice or Video, the short date, and how it ended. At large type sizes the outcome moves under.
struct CallLine: View {
    let call: CallRecord

    var body: some View {
        let glyph = Image(systemName: call.outgoing ? "arrow.up.right" : "arrow.down.left").font(Theme.caption).foregroundStyle(Theme.textSecondary)
        let outcome = Text(call.outcomeText).font(Theme.caption).foregroundStyle(call.isMissedIncoming ? Color.red : Theme.textSecondary)
        let date = Text(CallGrouping.shortDate(call.date)).font(Theme.caption).foregroundStyle(Theme.textSecondary)
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                glyph
                Text(call.video ? "Video" : "Voice").font(Theme.body).foregroundStyle(Theme.text)
                date.lineLimit(1).fixedSize()
                Spacer(minLength: 8)
                outcome.lineLimit(1).fixedSize()
            }
            HStack(alignment: .top, spacing: 8) {
                glyph.padding(.top, 4)
                VStack(alignment: .leading, spacing: 2) {
                    Text(call.video ? "Video" : "Voice").font(Theme.body).foregroundStyle(Theme.text)
                    date
                    outcome
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("profile-call-line")
    }
}

private struct MediaCell: View {
    let item: AttachmentItem
    @Environment(ConversationStore.self) private var store
    /// The picture itself when this phone already has it (never fetched just to fill the grid).
    @State private var full: UIImage?

    /// Downloaded picture, else a video's sharp poster, else the tiny thumbnail.
    private var best: UIImage? {
        switch AttachmentCover.pick(kind: item.kind, hasFull: full != nil, hasPoster: !item.poster.isEmpty, hasThumb: !item.thumb.isEmpty) {
        case .full: return full
        case .poster: return UIImage(data: item.poster)
        case .thumb: return UIImage(data: item.thumb)
        case .none: return nil
        }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let image = best { Image(uiImage: image).resizable().scaledToFill() } else { Color(white: 0.3) }
                if item.kind == .video { Image(systemName: "play.fill").foregroundStyle(.white).font(Theme.font(.title3)) }
            }
            .frame(width: geo.size.width, height: geo.size.width).clipped()
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityLabel(item.kind == .video ? "Video" : "Photo")
        .task(id: item.id) {
            // Only what is already on the phone: a picture that was never downloaded stays the thumbnail.
            if item.kind == .image, item.downloaded, !item.removed { full = await store.image(for: item) }
        }
    }
}

private struct FileRow: View {
    let message: Message
    var body: some View {
        let file = message.attachments.first { $0.kind != .image && $0.kind != .video }
        HStack(spacing: 12) {
            Image(systemName: "doc").font(Theme.font(.title3)).foregroundStyle(Theme.text)
            VStack(alignment: .leading, spacing: 1) {
                Text(file?.name ?? "File").font(Theme.body).foregroundStyle(Theme.text).lineLimit(1)
                Text(message.date.formatted(date: .abbreviated, time: .omitted)).font(Theme.caption).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            if let size = file?.size { Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)).font(Theme.caption).foregroundStyle(Theme.textSecondary) }
        }
        .padding(.horizontal, 18).frame(minHeight: 56)
    }
}

private struct LinkRow: View {
    let message: Message
    private var url: String {
        message.linkPreview?.url ?? message.text.split(whereSeparator: \.isWhitespace).map(String.init).first { $0.lowercased().hasPrefix("http") } ?? ""
    }
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "link").font(Theme.font(.title3)).foregroundStyle(Theme.text)
            VStack(alignment: .leading, spacing: 1) {
                Text(message.linkPreview?.title ?? url).font(Theme.body).foregroundStyle(Theme.text).lineLimit(1)
                Text(message.date.formatted(date: .abbreviated, time: .omitted)).font(Theme.caption).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
        }
        .padding(.horizontal, 18).frame(minHeight: 56)
        .contentShape(Rectangle())
        .onTapGesture { if let link = URL(string: url) { UIApplication.shared.open(link) } }
    }
}

/// "See all": one kind of shared thing in full.
struct SharedListView: View {
    let route: SharedListRoute
    @Environment(ConversationStore.self) private var store

    var body: some View {
        let items = store.shared(in: route.conversationID, from: route.sender, kind: route.kind.kind)
        ScrollView {
            VStack(spacing: 0) {
                switch route.kind {
                case .media:
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3), spacing: 4) {
                        ForEach(Array(items.flatMap { m in m.attachments.filter { $0.kind == .image || $0.kind == .video }.map { (m, $0) } }), id: \.1.id) { message, item in
                            MediaCell(item: item)
                                .onTapGesture { store.attachmentViewer = AttachmentViewerRequest(items: [item], index: 0, messageID: message.id, conversationID: route.conversationID) }
                        }
                    }.padding(.horizontal, 16)
                case .files: ForEach(items) { FileRow(message: $0) }
                case .links: ForEach(items) { LinkRow(message: $0) }
                }
            }
        }
        .background(Theme.canvas.ignoresSafeArea())
        .navigationTitle(route.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .accessibilityIdentifier("shared-list")
    }
}


/// The sections of a profile as one row of tabs (LIME-188d): it scrolls sideways when it is wider than the screen, and the chosen tab sits in a
/// Liquid Glass capsule. For VoiceOver each reads "Posts, tab, 3 of 7".
struct ProfileTabs: View {
    let sections: [ProfileView.Section]
    @Binding var selection: ProfileView.Section
    /// Tabs with something new (a quiet dot), LIME-189c.
    var badged: Set<ProfileView.Section> = []
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(Array(sections.enumerated()), id: \.element) { index, section in
                        let on = selection == section
                        Button { selection = section } label: {
                            Text(section.rawValue).font(Theme.font(.subheadline, weight: on ? .semibold : .regular)).foregroundStyle(on ? Theme.text : Theme.textSecondary)
                                .padding(.horizontal, 14).frame(minHeight: 44)
                                .background { if on { Capsule().fill(.clear).limeGlass(in: Capsule()) } }
                                .overlay(alignment: .topTrailing) { if badged.contains(section) { Circle().fill(Theme.accent).frame(width: 8, height: 8).padding(.top, 8).padding(.trailing, 6).accessibilityIdentifier("profile-tab-dot-\(section.rawValue)") } }
                        }
                        .buttonStyle(.plain).id(section)
                        .accessibilityLabel("\(section.rawValue)\(badged.contains(section) ? ", new" : ""), tab, \(index + 1) of \(sections.count)")
                        .accessibilityAddTraits(on ? [.isSelected] : [])
                        .accessibilityIdentifier("profile-tab-\(section.rawValue)")
                    }
                }
                .padding(4)
            }
            .onChange(of: selection) { _, now in withAnimation { proxy.scrollTo(now, anchor: .center) } }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("profile-sections")
    }
}
