import SwiftUI

/// An org's profile, pushed like a person's (LIME-216).
struct OrgRoute: Hashable {
    let page: JamPageInfo
    let isMe: Bool
}

extension ConversationStore {
    func openOrg(_ page: JamPageInfo, isMe: Bool) {
        let route = OrgRoute(page: page, isMe: isMe)
        switch section {
        case .link: path.append(route)
        case .call: callPath.append(route)
        case .jam: jamPath.append(route)
        }
    }

    /// The org's writers: the person who made it, then everyone credited (accepted) on its posts, each once (LIME-216).
    func orgAuthors(_ page: JamPageInfo) -> [Person] {
        let me = meProvider()
        let owner = page.writerId == me.id ? me : teacher(page.writerId)
        var ids: [String] = []
        for post in posts(of: page.jamId) { for id in post.coauthors where id != owner.id && !ids.contains(id) { ids.append(id) } }
        return [owner] + ids.map { $0 == me.id ? me : teacher($0) }
    }

    /// "Shem Rajoon, Jean Chung".
    func orgAuthorNames(_ page: JamPageInfo) -> String { orgAuthors(page).map(\.name).joined(separator: ", ") }
}

/// What an owner (or anyone) can do with an org: the same from a row's swipe, its long-press menu, VoiceOver's actions and the org page's ⋯.
enum OrgAction: Identifiable {
    case edit(JamPageInfo), subscribers(JamPageInfo), end(JamPageInfo)
    var id: String { switch self { case .edit(let p): "edit-\(p.jamId)"; case .subscribers(let p): "subscribers-\(p.jamId)"; case .end(let p): "end-\(p.jamId)" } }
}

/// The sheets and the confirmation behind those actions.
private struct OrgActionHost: ViewModifier {
    @Binding var action: OrgAction?
    @Environment(ConversationStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var closesPageAfterEnd = false

    func body(content: Content) -> some View {
        content
            .sheet(item: Binding(get: { if case .edit = action { action } else { nil } }, set: { if $0 == nil { action = nil } })) { act in
                if case .edit(let page) = act, let mine = store.jamsMine.first(where: { $0.jamId == page.jamId }) { JamDetailsSheet(editing: mine) }
            }
            .sheet(item: Binding(get: { if case .subscribers = action { action } else { nil } }, set: { if $0 == nil { action = nil } })) { act in
                if case .subscribers(let page) = act { NavigationStack { JamSubscribersView(jamID: page.jamId) }.onAppear { store.loadJamSubscribers(page.jamId) } }
            }
            .confirmSheet("End this jam?", isPresented: Binding(get: { if case .end = action { true } else { false } }, set: { if !$0, case .end = action { action = nil } })) {
                Button("End jam", role: .destructive) {
                    if case .end(let page) = action { Task { await store.endJam(page.jamId); if closesPageAfterEnd { dismiss() } } }
                    action = nil
                }.accessibilityIdentifier("jam-end-confirm")
                Button("Cancel", role: .cancel) { action = nil }
            } message: { Text("Subscribers keep what they have.") }
    }
}

extension View {
    fileprivate func orgActions(_ action: Binding<OrgAction?>, closesPageAfterEnd: Bool = false) -> some View {
        modifier(OrgActionHost(action: action, closesPageAfterEnd: closesPageAfterEnd))
    }
}

/// The Orgs tab (LIME-216): rounded-square tile with its writers' circles, title, authors, one line of description and the subscribers; swipe left for Edit,
/// Subscribers and End jam (an owner's), right for Share; the same in the long-press menu and as VoiceOver actions. A tap opens the org's profile.
struct JamOrgsSection: View {
    let orgs: [JamPageInfo]
    let isMe: Bool
    @Environment(ConversationStore.self) private var store
    @ScaledMetric(relativeTo: .body) private var rowHeight: CGFloat = 84
    @State private var action: OrgAction?

    var body: some View {
        List {
            ForEach(orgs, id: \.jamId) { org in
                row(org)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowBackground(Color.clear).listRowSeparator(.hidden)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if isMe {
                            // Red, but not the `.destructive` role: that makes the list remove the row at once, before the confirmation has been answered.
                            Button { action = .end(org) } label: { Label("End jam", systemImage: "xmark.circle") }.tint(.red).accessibilityIdentifier("org-swipe-end-\(org.jamId)")
                            Button { action = .subscribers(org) } label: { Label("Subscribers", systemImage: "person.2") }.tint(.gray).accessibilityIdentifier("org-swipe-subscribers-\(org.jamId)")
                            Button { action = .edit(org) } label: { Label("Edit", systemImage: "pencil") }.tint(.blue).accessibilityIdentifier("org-swipe-edit-\(org.jamId)")
                        }
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        if let share = shareURL(org) { ShareLink(item: share, message: Text("\(org.title) on lime")) { Label("Share", systemImage: "square.and.arrow.up") }.tint(.green) }
                    }
            }
        }
        .listStyle(.plain).scrollDisabled(true).scrollContentBackground(.hidden)
        .frame(height: rowHeight * CGFloat(max(orgs.count, 1)))
        .padding(.horizontal, -16)
        .orgActions($action)
    }

    private func shareURL(_ org: JamPageInfo) -> URL? {
        guard let username = store.publicProfiles[org.writerId]?.username else { return nil }
        return URL(string: InviteLink.url(username: username))
    }

    private func row(_ org: JamPageInfo) -> some View {
        let authors = store.orgAuthors(org)
        let names = authors.map(\.name).joined(separator: ", ")
        return HStack(spacing: 12) {
            Button { store.openOrg(org, isMe: isMe) } label: {
                HStack(spacing: 12) {
                    BylineAvatar(people: authors, jam: org.title, size: 52).frame(width: 60, height: 56, alignment: .leading)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(org.title).font(Theme.font(.body, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                        Text(names).font(Theme.secondary).foregroundStyle(Theme.textSecondary).lineLimit(1)
                        if !org.about.isEmpty { Text(org.about).font(Theme.caption).foregroundStyle(Theme.textSecondary).lineLimit(1) }
                        Text(org.subscriberCount == 1 ? "1 subscriber" : "\(org.subscriberCount) subscribers").font(Theme.caption).foregroundStyle(Theme.textSecondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16).frame(minHeight: rowHeight - 8).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(org.title), by \(names), \(org.subscriberCount) subscribers").accessibilityHint("Opens its page")
            .accessibilityIdentifier("profile-org-\(org.jamId)")
            .modifier(OrgAccessibilityActions(org: org, isMe: isMe, action: $action))
            .contextMenu {
                if isMe {
                    Button { action = .edit(org) } label: { Label("Edit", systemImage: "pencil") }
                    Button { action = .subscribers(org) } label: { Label("Subscribers", systemImage: "person.2") }
                    Button(role: .destructive) { action = .end(org) } label: { Label("End jam", systemImage: "xmark.circle") }
                }
                if let share = shareURL(org) { ShareLink(item: share, message: Text("\(org.title) on lime")) { Label("Share", systemImage: "square.and.arrow.up") } }
            }
            if !isMe { SubscribeLink(page: org, id: "profile-org-subscribe-\(org.jamId)").padding(.trailing, 16) }
        }
    }
}

/// VoiceOver's own path to the swipe actions.
private struct OrgAccessibilityActions: ViewModifier {
    let org: JamPageInfo
    let isMe: Bool
    @Binding var action: OrgAction?

    func body(content: Content) -> some View {
        if isMe {
            content
                .accessibilityAction(named: "Edit") { action = .edit(org) }
                .accessibilityAction(named: "Subscribers") { action = .subscribers(org) }
                .accessibilityAction(named: "End jam") { action = .end(org) }
        } else { content }
    }
}

/// The tabs of an org's profile.
private enum OrgTab: String, CaseIterable { case all = "All", posts = "Posts", articles = "Articles", podcasts = "Podcasts", info = "Info"
    var segment: JamSegment? { switch self { case .all: .all; case .posts: .posts; case .articles: .articles; case .podcasts: .podcasts; case .info: nil } }
}

/// An org as a profile (LIME-216): the person profile's hero (its default from the org's colour, blurred), a rounded-square avatar with its writers' small
/// circles, the name, its authors, topics and subscribers, Subscribe as a pill under them, the tabs All · Posts · Articles · Podcasts · Info.
struct OrgProfileView: View {
    let route: OrgRoute
    @Environment(ConversationStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var tab: OrgTab = .all
    @State private var reading: JamPostRoute?
    @State private var action: OrgAction?
    @State private var reporting: ReportTarget?
    @State private var confirmingUnsubscribe = false
    @State private var topInset: CGFloat = 0
    @State private var windowHeight: CGFloat = 0

    private var page: JamPageInfo { route.page }
    private var isMe: Bool { route.isMe }

    var body: some View {
        let following = store.isFollowing(page.jamId)
        ScrollView {
            VStack(spacing: 18) {
                headBlock
                content(following: following)
            }
            .padding(.horizontal, 16).padding(.bottom, 40)
        }
        .background(Theme.canvas.ignoresSafeArea().accessibilityIdentifier("org-profile-screen"))
        .background { GeometryReader { geo in
            Color.clear.preference(key: HeroInsetKey.self, value: geo.safeAreaInsets.top)
                .preference(key: HeroWindowKey.self, value: geo.size.height + geo.safeAreaInsets.top + geo.safeAreaInsets.bottom)
        } }
        .onPreferenceChange(HeroInsetKey.self) { topInset = $0 }
        .onPreferenceChange(HeroWindowKey.self) { windowHeight = $0 }
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.light, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar { toolbarItems }
        .sheet(item: $reading) { route in NavigationStack { JamPostView(postID: route.postID).toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { reading = nil } } } } }
        .orgActions($action, closesPageAfterEnd: true)
        .reportSheet($reporting)
        .confirmSheet("Unsubscribe from \(page.title)?", isPresented: $confirmingUnsubscribe) {
            Button("Unsubscribe", role: .destructive) { Task { await store.unsubscribe(page.jamId) } }.accessibilityIdentifier("profile-org-page-subscribe-confirm")
            Button("Cancel", role: .cancel) {}
        } message: { Text("What you have stays on this phone.") }
        .accessibilityIdentifier("jam-org-page")
    }

    // MARK: Header

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        if #available(iOS 26, *) { modernItems } else { legacyItems }
    }

    @ToolbarContentBuilder
    private var legacyItems: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            if isMe { editButton }
            moreMenu
        }
    }

    @available(iOS 26, *)
    @ToolbarContentBuilder
    private var modernItems: some ToolbarContent {
        if isMe {
            ToolbarItem(placement: .topBarTrailing) { editButton }
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
        }
        ToolbarItem(placement: .topBarTrailing) { moreMenu }
    }

    private var editButton: some View {
        Button { action = .edit(page) } label: { Image(systemName: "pencil") }
            .accessibilityLabel("Edit jam page").accessibilityIdentifier("jam-edit-page")
    }

    private var moreMenu: some View {
        Menu {
            if isMe {
                Button { action = .subscribers(page) } label: { Label("Subscribers", systemImage: "person.2") }.accessibilityIdentifier("jam-subscribers")
                Button(role: .destructive) { action = .end(page) } label: { Label("End jam", systemImage: "xmark.circle") }.accessibilityIdentifier("jam-end")
            }
            if let username = store.publicProfiles[page.writerId]?.username, let url = URL(string: InviteLink.url(username: username)) {
                ShareLink(item: url, message: Text("\(page.title) on lime")) { Label("Share", systemImage: "square.and.arrow.up") }.accessibilityIdentifier("org-share")
            }
            if !isMe {
                Button(role: .destructive) { reporting = store.reportTarget(page: page) } label: { Label("Report", systemImage: "flag") }.accessibilityIdentifier("org-report")
            }
        } label: { Image(systemName: "ellipsis") }
            .accessibilityLabel("More").accessibilityIdentifier("profile-org-more")
    }

    // MARK: The hero

    private var headBlock: some View {
        let screen = windowHeight > 0 ? windowHeight : UIScreen.main.bounds.height
        let inset = topInset > 0 ? topInset : 100
        let authors = store.orgAuthors(page)
        let shown = HeroDefault.org(dark: colorScheme == .dark)
        let sides = windowSideInsets
        return VStack(spacing: 0) {
            VStack(spacing: 6) {
                BylineAvatar(people: authors, jam: page.title, size: 104).frame(width: 104, height: 104)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(authors.count > 1 ? "\(page.title), with \(authors.dropFirst().map(\.name).joined(separator: ", "))" : page.title)
                    .padding(.top, 12).padding(.bottom, 14)   // room for the writers' circles that hang below the tile
                Text(page.title).font(Theme.font(.title2, weight: .semibold)).foregroundStyle(.white).multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader).accessibilityIdentifier("profile-jam-row")
                Text(authors.map(\.name).joined(separator: ", ")).font(Theme.secondary).foregroundStyle(.white.opacity(0.92)).multilineTextAlignment(.center)
                    .accessibilityIdentifier("org-authors")
                if !page.topics.isEmpty {
                    Text(page.topics.joined(separator: " \u{00B7} ")).font(Theme.secondary).foregroundStyle(.white.opacity(0.92)).multilineTextAlignment(.center)
                }
                subscribersLine
                if !isMe { subscribePill.padding(.top, 4) }
            }
            .padding(.top, HeroShape.avatarTopPadding(screen: screen, inset: inset, avatar: 104) - 12)
            Spacer(minLength: HeroShape.textToPills(screen: screen))
            OrgTabs(selection: $tab)
        }
        .frame(maxWidth: .infinity, minHeight: HeroShape.blockHeight(screen: screen, inset: inset))
        .background(alignment: .top) {
            ProfileHeroBackground(image: shown.image, cacheKey: shown.key, isDefault: true, screenHeight: screen, exposedForTests: store.isDemo)
                .padding(.top, -inset).padding(.bottom, -8).padding(.leading, -(16 + sides.leading)).padding(.trailing, -(16 + sides.trailing))
        }
    }

    private var windowSideInsets: EdgeInsets {
        _ = windowHeight
        let window = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow)
        let insets = window?.safeAreaInsets ?? .zero
        return EdgeInsets(top: 0, leading: insets.left, bottom: 0, trailing: insets.right)
    }

    /// "n subscribers": the owner taps it for the list.
    @ViewBuilder
    private var subscribersLine: some View {
        let text = page.subscriberCount == 1 ? "1 subscriber" : "\(page.subscriberCount) subscribers"
        if isMe {
            Button { action = .subscribers(page) } label: {
                Text(text).font(Theme.secondary).foregroundStyle(.white.opacity(0.92)).frame(minHeight: 44)
            }
            .buttonStyle(.plain).accessibilityLabel(text).accessibilityHint("Opens the list").accessibilityIdentifier("profile-jam-subscribers")
        } else {
            Text(text).font(Theme.secondary).foregroundStyle(.white.opacity(0.92)).accessibilityIdentifier("profile-jam-subscribers")
        }
    }

    /// Subscribe as a pill under the name and authors (as a person's profile has it); lime, then neutral "Subscribed ✓" (a tap asks before it unsubscribes).
    private var subscribePill: some View {
        let following = store.isFollowing(page.jamId)
        return Button { if following { confirmingUnsubscribe = true } else { Task { await store.subscribe(to: page) } } } label: {
            Text(following ? "Subscribed \u{2713}" : "Subscribe").font(Theme.font(.subheadline, weight: .semibold))
                .foregroundStyle(following ? Theme.text : Theme.accentInk).padding(.horizontal, 20).frame(minHeight: 44)
                .background(following ? Theme.surface : Theme.accent, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(following ? "Subscribed to \(page.title). Tap to unsubscribe." : "Subscribe to \(page.title)")
        .accessibilityIdentifier("profile-org-page-subscribe")
    }

    // MARK: Content

    @ViewBuilder
    private func content(following: Bool) -> some View {
        if tab == .info { info } else if isMe || following {
            let segment = tab.segment ?? .all
            let posts = store.posts(of: page.jamId).filter { $0.displayAs == "jam" && segment.includes(kind: $0.kind) }
            if posts.isEmpty {
                Text("Posts shared as \(page.title) show here. Choose \(page.title) in Post as when you post.").font(Theme.body).foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.top, 12).accessibilityIdentifier("org-empty")
            }
            VStack(spacing: 0) {
                ForEach(posts, id: \.postId) { post in
                    JamPostCard(post: post, open: { reading = JamPostRoute(postID: $0) }, place: .orgPage(segment))
                    Divider().overlay(Theme.hairline)
                }
            }
            .padding(.horizontal, -16)
        } else {
            Text("Subscribe to read their posts.").font(Theme.body).foregroundStyle(Theme.textSecondary).frame(maxWidth: .infinity).padding(.top, 12)
                .accessibilityIdentifier("profile-jam-locked")
        }
    }

    /// Info: what it is about, its topics, its authors, since when.
    @ViewBuilder
    private var info: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !page.about.isEmpty { infoCard("About") { Text(page.about).font(Theme.body).foregroundStyle(Theme.text).frame(maxWidth: .infinity, alignment: .leading).padding(18) } }
            if !page.topics.isEmpty { infoCard("Topics") { Text(page.topics.joined(separator: " \u{00B7} ")).font(Theme.body).foregroundStyle(Theme.text).frame(maxWidth: .infinity, alignment: .leading).padding(18) } }
            infoCard("Authors") {
                VStack(spacing: 0) {
                    let authors = store.orgAuthors(page)
                    ForEach(Array(authors.enumerated()), id: \.element.id) { index, person in
                        Button { store.openProfile(ProfileRoute(userID: person.id, name: person.name, isMe: person.id == store.meProvider().id)) } label: {
                            HStack(spacing: 12) {
                                AvatarView(person: person, size: 36).accessibilityHidden(true)
                                Text(person.name).font(Theme.body).foregroundStyle(Theme.text)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 18).frame(minHeight: 56).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).accessibilityIdentifier("org-author-\(person.id)")
                        if index < authors.count - 1 { Divider().overlay(Theme.hairline).padding(.leading, 66) }
                    }
                }
            }
            if let first = store.posts(of: page.jamId).map(\.created).min() {
                Text("Since \(Date(timeIntervalSince1970: Double(first) / 1000).formatted(.dateTime.month(.wide).year()))").font(Theme.secondary).foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity).accessibilityIdentifier("org-since")
            }
        }
    }

    private func infoCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(Theme.font(.subheadline, weight: .semibold)).foregroundStyle(Theme.textSecondary).padding(.leading, 6)
            content().background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }
}

/// All · Posts · Articles · Podcasts · Info, as the person profile's tab pills (no shadow).
private struct OrgTabs: View {
    @Binding var selection: OrgTab
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(OrgTab.allCases.enumerated()), id: \.element) { index, tab in
                    let on = selection == tab
                    Button { selection = tab } label: {
                        Text(tab.rawValue).font(Theme.font(.subheadline, weight: on ? .semibold : .regular)).foregroundStyle(on ? Theme.text : Theme.textSecondary)
                            .padding(.horizontal, 14).frame(minHeight: 44)
                            .background { if on { Capsule().fill(Theme.surface.opacity(0.92)) } }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(tab.rawValue), tab, \(index + 1) of \(OrgTab.allCases.count)")
                    .accessibilityAddTraits(on ? [.isSelected] : [])
                    .accessibilityIdentifier("org-tab-\(tab.rawValue)")
                }
            }
            .padding(4)
        }
        .accessibilityIdentifier("profile-org-segments")
    }
}
