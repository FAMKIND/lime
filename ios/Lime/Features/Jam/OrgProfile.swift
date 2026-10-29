import SwiftUI

/// An org's profile, pushed like a person's (LIME-216).
struct OrgRoute: Hashable {
    let page: JamPageInfo
    let isMe: Bool
    /// Opens already editing (from a row's Edit).
    var editing = false
}

extension ConversationStore {
    func openOrg(_ page: JamPageInfo, isMe: Bool, editing: Bool = false) {
        let route = OrgRoute(page: page, isMe: isMe, editing: editing)
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
            .onChange(of: action?.id) { _, _ in
                if case .edit(let page) = action { action = nil; store.openOrg(page, isMe: true, editing: true) }
            }
            .sheet(item: Binding(get: { if case .subscribers = action { action } else { nil } }, set: { if $0 == nil { action = nil } })) { act in
                if case .subscribers(let page) = act { NavigationStack { JamSubscribersView(jamID: page.jamId) }.onAppear { store.loadJamSubscribers(page.jamId) } }
            }
            .confirmSheet("Close this org?", isPresented: Binding(get: { if case .end = action { true } else { false } }, set: { if !$0, case .end = action { action = nil } })) {
                Button("Close org", role: .destructive) {
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
/// Subscribers and Close org (an owner's), right for Share; the same in the long-press menu and as VoiceOver actions. A tap opens the org's profile.
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
                            Button { action = .end(org) } label: { Label("Close org", systemImage: "xmark.circle") }.tint(.red).accessibilityIdentifier("org-swipe-end-\(org.jamId)")
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
                    BylineAvatar(people: authors, jam: org.title, jamId: org.jamId, size: 52).frame(width: 60, height: 56, alignment: .leading)
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
                    Button(role: .destructive) { action = .end(org) } label: { Label("Close org", systemImage: "xmark.circle") }
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
                .accessibilityAction(named: "Close org") { action = .end(org) }
        } else { content }
    }
}

/// An org as a profile (LIME-216, 245): the person profile's hero (its default from the org's colour, blurred), a rounded-square avatar with its writers' small
/// circles, the name, its authors, tags and subscribers, Subscribe as a pill under them, the profile's glass tabs Info · Posts · Articles · Podcasts. An owner's
/// Edit turns the page into its own editor: the camera circle on the picture and the fields as rows, each in a small sheet.
struct OrgProfileView: View {
    let route: OrgRoute
    @Environment(ConversationStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var tab: ProfileView.Section = .info
    @State private var reading: JamPostRoute?
    @State private var action: OrgAction?
    @State private var reporting: ReportTarget?
    @State private var confirmingUnsubscribe = false
    @State private var editing: Bool
    @State private var fieldSheet: OrgField?
    @State private var pictureSheet = false
    @State private var topInset: CGFloat = 0
    @State private var windowHeight: CGFloat = 0

    init(route: OrgRoute) {
        self.route = route
        _editing = State(initialValue: route.editing && route.isMe)
    }

    /// What you see: for the owner, what this phone holds now (so an edit shows at once); otherwise what was opened.
    private var page: JamPageInfo {
        if isMe, let mine = store.jamsMine.first(where: { $0.jamId == route.page.jamId }) {
            return JamPageInfo(jamId: mine.jamId, writerId: mine.writer, title: mine.title, about: mine.about, topics: mine.topics, postCount: mine.postCount,
                               subscriberCount: mine.subscriberCount, hasCommunity: mine.community, pictureVersion: route.page.pictureVersion)
        }
        return route.page
    }
    private var isMe: Bool { route.isMe }
    private var editingNow: Bool { isMe && editing }
    private static let sections: [ProfileView.Section] = [.info, .posts, .articles, .podcasts]

    var body: some View {
        let following = store.isFollowing(page.jamId)
        ScrollView {
            VStack(spacing: 18) {
                headBlock
                if editingNow { editRows } else { content(following: following) }
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
        .navigationBarBackButtonHidden(editingNow)
        .toolbar { toolbarItems }
        .sheet(item: $reading) { route in NavigationStack { JamPostView(postID: route.postID).toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { reading = nil } } } } }
        .sheet(item: $fieldSheet) { OrgFieldSheet(page: page, field: $0) }
        .sheet(isPresented: $pictureSheet) { OrgPictureSheet(jamId: page.jamId, title: page.title) }
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

    /// Normal: Edit · ⋯ (an owner's Edit; everyone's ⋯). Editing: ‹ back to the page · Done (LIME-229's pattern; an org has no cover to edit).
    @ToolbarContentBuilder
    private var legacyItems: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            if editingNow { doneButton } else {
                if isMe { editButton }
                moreMenu
            }
        }
        ToolbarItem(placement: .topBarLeading) { if editingNow { backToOrg } }
    }

    @available(iOS 26, *)
    @ToolbarContentBuilder
    private var modernItems: some ToolbarContent {
        if editingNow {
            ToolbarItem(placement: .topBarLeading) { backToOrg }
            ToolbarItem(placement: .topBarTrailing) { doneButton }
        } else {
            if isMe {
                ToolbarItem(placement: .topBarTrailing) { editButton }
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
            }
            ToolbarItem(placement: .topBarTrailing) { moreMenu }
        }
    }

    private var editButton: some View {
        Button("Edit") { editing = true }.accessibilityLabel("Edit org").accessibilityIdentifier("jam-edit-page")
    }

    private var doneButton: some View {
        Button("Done") { editing = false }.fontWeight(.semibold).accessibilityLabel("Done editing").accessibilityIdentifier("org-done")
    }

    /// While editing, ‹ goes back to the org's page, not out of it.
    private var backToOrg: some View {
        Button { editing = false } label: { Image(systemName: "chevron.left") }.accessibilityLabel("Back to the org").accessibilityIdentifier("org-edit-back")
    }

    private var moreMenu: some View {
        Menu {
            if isMe {
                Button { action = .subscribers(page) } label: { Label("Subscribers", systemImage: "person.2") }.accessibilityIdentifier("jam-subscribers")
                Button(role: .destructive) { action = .end(page) } label: { Label("Close org", systemImage: "xmark.circle") }.accessibilityIdentifier("jam-end")
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
                BylineAvatar(people: authors, jam: page.title, jamId: page.jamId, size: 104).frame(width: 104, height: 104)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(authors.count > 1 ? "\(page.title), with \(authors.dropFirst().map(\.name).joined(separator: ", "))" : page.title)
                    // In edit mode the picture gets a camera circle, as a person's photo does (LIME-225).
                    .overlay(alignment: .topTrailing) {
                        if editingNow {
                            Button { pictureSheet = true } label: {
                                Image(systemName: "camera.fill").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text)
                                    .frame(width: 34, height: 34).background(Theme.surface.opacity(0.92), in: Circle()).frame(width: 44, height: 44).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain).offset(x: 12, y: -12)
                            .accessibilityLabel("Change org picture").accessibilityIdentifier("org-edit-picture")
                        }
                    }
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
            if editingNow { Color.clear.frame(height: HeroShape.pillsRow) } else {
                ProfileTabs(sections: Self.sections, selection: $tab)
            }
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

    // MARK: Edit in place

    /// Under the hero, the tabs give way to the fields as grouped rows with a pencil; each opens its own small sheet.
    @ViewBuilder
    private var editRows: some View {
        VStack(spacing: 16) {
            SettingsCard {
                editRow("person", page.title, id: "org-edit-name", label: "Edit name, \(page.title)") { fieldSheet = .name }
                editRow("text.alignleft", page.about.isEmpty ? "About" : page.about, id: "org-edit-about", dim: page.about.isEmpty, divider: false,
                        label: "Edit about, \(page.about.isEmpty ? "none" : page.about)") { fieldSheet = .about }
            }
            SettingsFootnote(text: "Your org\u{2019}s name, about and picture are public.")
            SettingsCard {
                editRow("tag", page.topics.isEmpty ? "Tags" : page.topics.joined(separator: " \u{00B7} "), id: "org-edit-tags", dim: page.topics.isEmpty, divider: false,
                        label: "Edit tags, \(page.topics.isEmpty ? "none" : page.topics.joined(separator: ", "))") { fieldSheet = .tags }
            }
            SettingsFootnote(text: "Up to 8. Teachers find your org by these.")
            SettingsCard {
                HStack(spacing: 14) {
                    Image(systemName: "person.2").font(.system(size: 20)).frame(width: 28).foregroundStyle(Theme.text).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Owners").font(Theme.body).foregroundStyle(Theme.text)
                        Text(store.orgAuthorNames(page)).font(Theme.secondary).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 18).frame(minHeight: 58)
                .accessibilityElement(children: .combine).accessibilityIdentifier("org-edit-owners")
            }
            SettingsFootnote(text: "Everyone you credit on a post as \(page.title) shows here.")
            SettingsCard {
                Toggle(isOn: Binding(get: { page.hasCommunity }, set: { on in Task { _ = await store.setCommunity(page.jamId, on: on) } })) {
                    Text("Community chat").font(Theme.body).foregroundStyle(Theme.text)
                }
                .tint(Theme.accent).padding(.horizontal, 18).frame(minHeight: 58)
                .accessibilityIdentifier("jam-community-toggle")
            }
            SettingsFootnote(text: "Subscribers can join a group chat with you. Up to 100 people.")
            SettingsCard {
                Button { action = .end(page) } label: {
                    HStack { Text("Close org").font(Theme.body).foregroundStyle(Color.red); Spacer(minLength: 0) }
                        .padding(.horizontal, 18).frame(minHeight: 58).contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityIdentifier("jam-end")
            }
            SettingsFootnote(text: "Subscribers keep what they have.")
        }
    }

    private func editRow(_ symbol: String, _ title: String, id: String, dim: Bool = false, divider: Bool = true, label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    Image(systemName: symbol).font(.system(size: 20)).frame(width: 28).foregroundStyle(Theme.text).accessibilityHidden(true)
                    Text(title).font(Theme.body).foregroundStyle(dim ? Theme.textSecondary : Theme.text).lineLimit(2).multilineTextAlignment(.leading)
                    Spacer(minLength: 8)
                    Image(systemName: "pencil").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.textSecondary).accessibilityHidden(true)
                }
                .padding(.horizontal, 18).frame(minHeight: 58)
                if divider { Divider().overlay(Theme.hairline).padding(.leading, 60) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }

    // MARK: Content

    @ViewBuilder
    private func content(following: Bool) -> some View {
        if tab == .info { info } else if isMe || following {
            let segment: JamSegment = tab == .articles ? .articles : tab == .podcasts ? .podcasts : .posts
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

    /// Info (everyone): what it is about, its tags, its owners, the community chat, how many subscribe and since when.
    @ViewBuilder
    private var info: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !page.about.isEmpty { infoCard("About") { Text(page.about).font(Theme.body).foregroundStyle(Theme.text).frame(maxWidth: .infinity, alignment: .leading).padding(18) } }
            if !page.topics.isEmpty { infoCard("Tags") { Text(page.topics.joined(separator: " \u{00B7} ")).font(Theme.body).foregroundStyle(Theme.text).frame(maxWidth: .infinity, alignment: .leading).padding(18) } }
            infoCard("Owners") {
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
            if !isMe && page.hasCommunity { CommunityJoinRow(jamID: page.jamId) }
            let count = page.subscriberCount == 1 ? "1 subscriber" : "\(page.subscriberCount) subscribers"
            let started = store.posts(of: page.jamId).map(\.created).min().map { " \u{00B7} Started \(Date(timeIntervalSince1970: Double($0) / 1000).formatted(.dateTime.month(.abbreviated).year()))" } ?? ""
            Text(count + started).font(Theme.secondary).foregroundStyle(Theme.textSecondary).frame(maxWidth: .infinity).accessibilityIdentifier("org-since")
        }
    }

    private func infoCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(Theme.font(.subheadline, weight: .semibold)).foregroundStyle(Theme.textSecondary).padding(.leading, 6)
            content().background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }
}
