import SwiftUI

/// Opens a person's profile (LIME-122a). `conversationID` is where it was opened from, which decides what "Shared" shows: a DM, or a
/// group (then only what this person shared there). `callIDs` narrows the Calls section to one group of calls (from a call row).
struct ProfileRoute: Hashable {
    let userID: String
    let name: String
    var conversationID: String? = nil
    var callIDs: [String]? = nil

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

struct ProfileView: View {
    let route: ProfileRoute
    @Environment(ConversationStore.self) private var store
    @Environment(NotificationCoordinator.self) private var notifications
    @State private var section: Section = .info
    @State private var copied = false
    @State private var labelling = false
    @State private var labelText = ""

    enum Section: String, CaseIterable { case info = "Info", shared = "Shared", calls = "Calls" }

    private var conversation: Conversation? { store.conversation("dm:\(route.userID)") }
    private var person: Person { conversation?.members.first ?? Person(id: route.userID, name: route.name, tone: AvatarTone.tone(for: route.userID)) }
    private var profile: PublicProfile? { store.publicProfiles[route.userID] }
    private var displayName: String { (profile?.displayName).flatMap { $0.isEmpty ? nil : $0 } ?? route.name }
    private var accepted: Bool { conversation.map { !$0.isRequest } ?? false }
    private var statusLine: String? {
        guard let status = store.status(of: route.userID) else { return nil }
        return StatusPlan.caption(state: status.state, until: status.until)
    }
    private var sharedMedia: [Message] { store.shared(in: route.sharedConversation, from: route.sharedSender, kind: .media) }
    private var sharedFiles: [Message] { store.shared(in: route.sharedConversation, from: route.sharedSender, kind: .files) }
    private var sharedLinks: [Message] { store.shared(in: route.sharedConversation, from: route.sharedSender, kind: .links) }
    private var calls: [CallRecord] {
        if let ids = route.callIDs { return CallLog.shared.records.filter { ids.contains($0.id) } }
        return Array(CallLog.shared.records(with: route.userID).prefix(10))
    }
    private var sections: [Section] {
        var list: [Section] = [.info]
        if !sharedMedia.isEmpty || !sharedFiles.isEmpty || !sharedLinks.isEmpty { list.append(.shared) }
        if !calls.isEmpty { list.append(.calls) }
        return list
    }

    var body: some View {
        let available = sections
        ScrollView {
            VStack(spacing: 18) {
                top
                if accepted { actions }
                if available.count > 1 {
                    Picker("Section", selection: $section) {
                        ForEach(available, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("profile-sections")
                }
                switch section {
                case .info: info
                case .shared: shared
                case .calls: callsList
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 40)
        }
        .background(Theme.canvas.ignoresSafeArea().accessibilityIdentifier("profile-screen"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if let username = profile?.username, let url = URL(string: InviteLink.url(username: username)) {
                    ShareLink(item: url, message: Text("\(displayName) on lime")) { Image(systemName: "square.and.arrow.up") }
                        .accessibilityLabel("Share").accessibilityIdentifier("profile-share")
                }
                if let conversation, accepted { moreMenu(conversation) }
            }
        }
        .task { await store.loadProfile(route.userID) }
        .onAppear { if route.callIDs != nil, available.contains(.calls) { section = .calls } }
        .sheet(isPresented: $labelling) {
            LabelSheet(name: displayName, text: $labelText) { saved in
                labelling = false
                if saved { Task { await store.setLabel(labelText, for: route.userID) } }
            }
        }
        .overlay(alignment: .bottom) {
            if copied {
                Text("Copied").font(.footnote.weight(.medium)).foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8).background(.black.opacity(0.7), in: Capsule())
                    .padding(.bottom, 30).accessibilityIdentifier("profile-copied")
            }
        }
    }

    // MARK: The top

    private var top: some View {
        VStack(spacing: 6) {
            AvatarView(person: person, size: 96, showsStatus: true).padding(.top, 12)
            HStack(spacing: 6) {
                Text(displayName).font(.title2.weight(.semibold)).foregroundStyle(Theme.text)
                    .accessibilityIdentifier("profile-name")
                if conversation?.verified == true {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.text).font(.callout).accessibilityLabel("Verified in person")
                }
            }
            let line = [profile?.username.map { "@\($0)" }, profile?.school].compactMap { $0 }.joined(separator: " \u{00B7} ")
            if !line.isEmpty {
                Text(line).font(Theme.secondary).foregroundStyle(Theme.textSecondary).accessibilityIdentifier("profile-handle")
            }
            if let statusLine {
                Text(statusLine).font(Theme.secondary).foregroundStyle(Theme.textSecondary).accessibilityIdentifier("profile-status")
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 12) {
            card("message", "Message", id: "profile-message") { store.openFromNotification("dm:\(route.userID)", thread: nil) }
            card("phone", "Voice", id: "profile-voice") { Task { _ = await store.calls.start(peerID: route.userID, name: displayName, video: false) } }
            card("video", "Video", id: "profile-video") { Task { _ = await store.calls.start(peerID: route.userID, name: displayName, video: true) } }
        }
    }

    private func card(_ symbol: String, _ title: String, id: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 20))
                Text(title).font(Theme.secondary)
            }
            .foregroundStyle(Theme.text)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    private func moreMenu(_ conversation: Conversation) -> some View {
        let settings = notifications.settings
        return Menu {
            if settings.isMuted(conversation.id) {
                Button { settings.unmute(conversation.id) } label: { Label("Unmute", systemImage: "bell") }
            } else {
                Menu {
                    ForEach(MuteDuration.allCases) { duration in
                        Button(duration.title) { settings.mute(conversation.id, for: duration) }
                    }
                } label: { Label("Notifications: mute", systemImage: "bell.slash") }
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
                    row("At", value: "@\(username)", id: "profile-username") {
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
            Text(title).font(Theme.secondary.weight(.semibold)).foregroundStyle(Theme.textSecondary).padding(.leading, 6)
            content().background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    // MARK: Shared

    @ViewBuilder
    private var shared: some View {
        let context = route.isGroupContext ? "Shared in \(store.conversation(route.sharedConversation)?.title ?? "this group")" : "Shared"
        Text(context).font(Theme.secondary.weight(.semibold)).foregroundStyle(Theme.textSecondary)
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
                NavigationLink(value: SharedListRoute(conversationID: route.sharedConversation, sender: route.sharedSender, kind: key, title: title)) {
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
    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let image = UIImage(data: item.thumb) { Image(uiImage: image).resizable().scaledToFill() } else { Color(white: 0.3) }
                if item.kind == .video { Image(systemName: "play.fill").foregroundStyle(.white).font(.title3) }
            }
            .frame(width: geo.size.width, height: geo.size.width).clipped()
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityLabel(item.kind == .video ? "Video" : "Photo")
    }
}

private struct FileRow: View {
    let message: Message
    var body: some View {
        let file = message.attachments.first { $0.kind != .image && $0.kind != .video }
        HStack(spacing: 12) {
            Image(systemName: "doc").font(.title3).foregroundStyle(Theme.text)
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
            Image(systemName: "link").font(.title3).foregroundStyle(Theme.text)
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
