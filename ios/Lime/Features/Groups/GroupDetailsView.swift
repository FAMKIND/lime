import SwiftUI

/// A group as a profile (LIME-251): the hero with the group's photo blurred (or its tone), the avatar, the name in white and the member count, the profile's glass
/// tabs Members · Media · Files · Links, Edit (for an owner or admin) and ⋯. Edit turns the page into its own editor: the camera circle on the avatar and the
/// fields as rows, the name in a small sheet.
struct GroupDetailsView: View {
    enum Tab: String { case members = "Members", media = "Media", files = "Files", links = "Links" }

    let target: GroupTarget
    @Environment(ConversationStore.self) private var store
    @Environment(NotificationCoordinator.self) private var notifications
    @Environment(\.colorScheme) private var colorScheme
    @State private var details: GroupDetails?
    @State private var tab: Tab = .members
    @State private var editing = false
    @State private var confirmingMute = false
    @State private var renaming = false
    @State private var newName = ""
    @State private var removing: GroupMemberInfo?
    @State private var leaving = false
    @State private var deletingForEveryone = false
    @State private var clearing = false
    @State private var adding = false
    @State private var editingAvatar = false
    @State private var coverSheet = false
    @State private var reporting: ReportTarget?
    @State private var topInset: CGFloat = 0
    @State private var windowHeight: CGFloat = 0

    private static let tabs: [Tab] = [.members, .media, .files, .links]
    private var conversation: Conversation? { store.conversation(target.conversationID) }
    private var name: String { details?.name ?? conversation?.title ?? "Group" }
    /// The living default hero's palette (LIME-261): from the group's photo, else its colour.
    private var ambientSpec: AmbientSpec? {
        let id = target.conversationID
        let photo = AvatarCache.shared.image(for: id)
        return Hero.ambient(photo: photo, chosen: store.groupTones[id], tone: store.groupTone(id), key: "group-hero-\(id)-\(photo.map { ObjectIdentifier($0).hashValue } ?? 0)", id: "group-hero-\(id)")
    }
    private var editingNow: Bool { editing && details?.canRename == true }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                headBlock
                if let details {
                    if editingNow { editRows(details) } else { content(details) }
                } else {
                    ProgressView().padding(.top, 60)
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 40)
        }
        .background((AvatarCache.shared.image(for: ConversationStore.groupCoverKey(target.conversationID)) == nil ? (ambientSpec?.paper(dark: colorScheme == .dark) ?? Theme.canvas) : Theme.canvas).ignoresSafeArea())
        .background { GeometryReader { geo in
            Color.clear.preference(key: HeroInsetKey.self, value: geo.safeAreaInsets.top)
                .preference(key: HeroWindowKey.self, value: geo.size.height + geo.safeAreaInsets.top + geo.safeAreaInsets.bottom)
        } }
        .onPreferenceChange(HeroInsetKey.self) { topInset = $0 }
        .onPreferenceChange(HeroWindowKey.self) { windowHeight = $0 }
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.light, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .limeBack(showsBack: !editingNow)
        .toolbar { toolbarItems }
        .task { await refresh() }
        .accessibilityIdentifier("group-details-page")
        .confirmSheet("Mute \(name)", isPresented: $confirmingMute) {
            ForEach(MuteDuration.allCases) { duration in
                Button(duration.title) { notifications.settings.mute(target.conversationID, for: duration) }
                    .accessibilityIdentifier("mute-\(duration.rawValue)")
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $editingAvatar) {
            GroupAvatarSheet(conversationID: target.conversationID, currentEmoji: details?.emoji, hasPhoto: details?.hasPhoto ?? false) { changed in
                editingAvatar = false
                if changed { Task { await refresh() } }
            }
        }
        .reportSheet($reporting)
        .sheet(isPresented: $coverSheet) {
            let id = target.conversationID
            CoverColourSheet(
                cover: AvatarCache.shared.image(for: ConversationStore.groupCoverKey(id)), chosen: store.groupTones[id], current: store.groupTone(id),
                note: "Only people in the group see the cover and colour.",
                setTone: { await store.setGroupTone(id, tone: $0) }, setCover: { await store.setGroupCover(id, jpeg: $0) }, removeCover: { await store.removeGroupCover(id) })
        }
        .task { await store.loadGroupStyle(target.conversationID) }
        .sheet(isPresented: $renaming) {
            RenameGroupSheet(name: $newName) { saved in
                renaming = false
                if saved { Task { _ = await store.renameGroup(target.conversationID, to: newName); await refresh() } }
            }
        }
        .confirmSheet("Remove \(removing?.name ?? "")?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            Button("Remove", role: .destructive) {
                if let member = removing { Task { await store.removeFromGroup(target.conversationID, user: member.userId); await refresh() } }
            }
            .accessibilityIdentifier("group-remove-confirm")
            Button("Cancel", role: .cancel) {}
        } message: { Text("They will not get new messages from this group.") }
        .confirmSheet("Leave \(name)?", isPresented: $leaving) {
            Button("Leave group", role: .destructive) {
                Task {
                    await store.leaveGroup(target.conversationID)
                    store.path = NavigationPath()
                }
            }
            .accessibilityIdentifier("group-leave-confirm")
            Button("Cancel", role: .cancel) {}
        } message: { Text("You won't get new messages from this group. Someone can add you back.") }
        .confirmSheet("Delete \(name) for everyone?", isPresented: $deletingForEveryone) {
            Button("Delete for everyone", role: .destructive) {
                Task { await store.deleteGroup(target.conversationID); store.path = NavigationPath() }
            }
            .accessibilityIdentifier("group-delete-confirm")
            Button("Cancel", role: .cancel) {}
        } message: { Text(GroupRowAction.Kind.deleteForEveryone.message) }
        .confirmSheet("Clear messages in \(name)?", isPresented: $clearing) {
            Button("Clear messages", role: .destructive) {
                Task { await store.clearMessages(target.conversationID); store.path = NavigationPath() }
            }
            .accessibilityIdentifier("group-clear-confirm")
            Button("Cancel", role: .cancel) {}
        } message: { Text(GroupRowAction.Kind.clear.message) }
        .sheet(isPresented: $adding) {
            NavigationStack {
                GroupPickerScreen(mode: .add(conversationID: target.conversationID, existing: details?.members.map(\.userId) ?? []),
                                  onNext: { ids in
                                      Task { await store.addToGroup(target.conversationID, users: ids); adding = false; await refresh() }
                                  },
                                  onBack: { adding = false })
            }
            .presentationDetents([.large])
        }
    }

    private func refresh() async { details = await store.groupDetails(target.conversationID) }

    // MARK: Header

    /// Top right: Edit (the word, for an owner or admin) and ⋯; editing: ‹ back to the page and Done. Mute, Pin and the rest live in ⋯ so the bar never crowds.
    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        if #available(iOS 26, *) {
            if editingNow {
                CircleToolbarItem(placement: .topBarLeading) { backToGroup }
                ToolbarItem(placement: .topBarTrailing) { editCoverButton }
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
                ToolbarItem(placement: .topBarTrailing) { doneButton }
            } else {
                if details?.canRename == true {
                    ToolbarItem(placement: .topBarTrailing) { editButton }
                    ToolbarSpacer(.fixed, placement: .topBarTrailing)
                }
                CircleToolbarItem { moreMenu }
            }
        } else {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if editingNow { editCoverButton; doneButton } else {
                    if details?.canRename == true { editButton }
                    moreMenu
                }
            }
            ToolbarItem(placement: .topBarLeading) { if editingNow { backToGroup } }
        }
    }

    private var editButton: some View {
        Button("Edit") { editing = true }.accessibilityLabel("Edit group").accessibilityIdentifier("group-edit")
    }

    /// The group's cover and colour, in a small sheet (LIME-257).
    private var editCoverButton: some View {
        Button("Edit Cover") { coverSheet = true }.accessibilityLabel("Edit cover").accessibilityIdentifier("group-edit-cover")
    }

    private var doneButton: some View {
        Button("Done") { editing = false }.fontWeight(.semibold).accessibilityLabel("Done editing").accessibilityIdentifier("group-done")
    }

    /// While editing, ‹ goes back to the group's page, not out of it.
    private var backToGroup: some View {
        Button { editing = false } label: { ToolIconLabel(symbol: "chevron.left") }.accessibilityLabel("Back to the group").accessibilityIdentifier("group-edit-back")
    }

    @ViewBuilder
    private var moreMenu: some View {
        Menu {
            if let conversation, !conversation.isRequest {
                let muted = notifications.settings.isMuted(conversation.id)
                Button {
                    if muted { notifications.settings.unmute(conversation.id) } else { confirmingMute = true }
                } label: { Label(muted ? "Unmute" : "Mute", systemImage: muted ? "bell.slash" : "bell") }
                    .accessibilityIdentifier("group-mute")
                Button { Task { await store.setPinned(conversation.id, !conversation.isPinned) } } label: {
                    Label(conversation.isPinned ? "Unpin" : "Pin", systemImage: conversation.isPinned ? "pin.slash" : "pin")
                }
                .accessibilityIdentifier("group-pin")
            }
            if let details {
                if details.canAdd {
                    Button { adding = true } label: { Label("Add members", systemImage: "person.badge.plus") }
                        .accessibilityIdentifier("group-more-add")
                }
                Divider()
                if details.myRole == "owner" {
                    Button(role: .destructive) { deletingForEveryone = true } label: { Label("Delete group", systemImage: "trash") }
                        .accessibilityIdentifier("group-more-delete")
                } else {
                    Button(role: .destructive) { clearing = true } label: { Label("Clear messages", systemImage: "eraser") }
                        .accessibilityIdentifier("group-more-clear")
                }
                Button(role: .destructive) { leaving = true } label: { Label("Leave group", systemImage: "rectangle.portrait.and.arrow.right") }
                    .accessibilityIdentifier("group-more-leave")
                Button(role: .destructive) {
                    reporting = store.reportTarget(group: target.conversationID, name: name, hasPhoto: details.hasPhoto, members: details.members)
                } label: { Label("Report group", systemImage: "flag") }
                    .accessibilityIdentifier("group-more-report")
            }
        } label: { ToolIconLabel(symbol: "ellipsis") }
            .accessibilityLabel("More").accessibilityIdentifier("group-more")
    }

    /// The hero: the group's photo blurred (or its tone), the avatar, the name in white, the count, and the glass tabs.
    private var headBlock: some View {
        let screen = windowHeight > 0 ? windowHeight : UIScreen.main.bounds.height
        let inset = topInset > 0 ? topInset : 100
        let id = target.conversationID
        // The cover when it has one, else its photo blurred, else a gradient of its colour (LIME-257).
        let cover = AvatarCache.shared.image(for: ConversationStore.groupCoverKey(id))
        let shown = HeroDefault.band(tone: store.groupTone(id), picture: AvatarCache.shared.image(for: id), id: id, dark: colorScheme == .dark)
        let sides = windowSideInsets
        let count = details?.members.count ?? 0
        return VStack(spacing: 0) {
            VStack(spacing: 6) {
                avatar
                    .accessibilityElement(children: .ignore).accessibilityLabel("Group picture").accessibilityIdentifier("group-details-avatar")
                    .overlay(alignment: .topTrailing) {
                        if editingNow {
                            Button { editingAvatar = true } label: {
                                Image(systemName: "camera.fill").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text)
                                    .frame(width: 34, height: 34).background(Theme.surface.opacity(0.92), in: Circle()).frame(width: 44, height: 44).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain).offset(x: 12, y: -12)
                            .accessibilityLabel("Change group photo").accessibilityIdentifier("group-edit-picture")
                        }
                    }
                    .padding(.top, 12).padding(.bottom, 6)
                Text(name).font(Theme.font(.title2, weight: .semibold)).foregroundStyle(.white).multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader).accessibilityIdentifier("group-details-name")
                Text(count == 1 ? "1 member" : "\(count) members").font(Theme.secondary).foregroundStyle(.white.opacity(0.92))
                    .accessibilityIdentifier("group-details-count")
            }
            .padding(.top, HeroShape.avatarTopPadding(screen: screen, inset: inset, avatar: 104) - 12)
            Spacer(minLength: HeroShape.textToPills(screen: screen))
            if editingNow { Color.clear.frame(height: HeroShape.pillsRow) } else {
                ProfileTabs(sections: Self.tabs, selection: $tab)
            }
        }
        .frame(maxWidth: .infinity, minHeight: HeroShape.blockHeight(screen: screen, inset: inset))
        .overlay { if store.isDemo { Color.clear.accessibilityIdentifier("group-tone-\(store.groupTone(id))") } }
        .background(alignment: .top) {
            ProfileHeroBackground(image: cover ?? shown.image, cacheKey: cover.map { "group-cover-\(id)-\(ObjectIdentifier($0).hashValue)" } ?? shown.key, isDefault: cover == nil, screenHeight: screen, ambient: cover == nil ? ambientSpec : nil, exposedForTests: store.isDemo)
                .padding(.top, -inset).padding(.bottom, -8).padding(.leading, -(16 + sides.leading)).padding(.trailing, -(16 + sides.trailing))
        }
    }

    /// The group's photo, its emoji, or its members' circles (as in Messages and the chat's top bar, LIME-231).
    @ViewBuilder
    private var avatar: some View {
        let id = target.conversationID
        if let photo = AvatarCache.shared.image(for: id) {
            Image(uiImage: photo).resizable().scaledToFill().frame(width: 104, height: 104).clipShape(Circle())
        } else if let emoji = details?.emoji {
            Circle().fill(Theme.avatar(store.groupTone(id))).frame(width: 104, height: 104).overlay(Text(emoji).font(.system(size: 52)))
        } else if let conversation {
            ConversationAvatar(conversation: conversation, size: 104).overlay(alignment: .topLeading) {
                Color.clear.frame(width: 1, height: 1).accessibilityElement().accessibilityIdentifier("group-details-members-avatar")
            }
        } else {
            Circle().fill(Theme.surface).frame(width: 104, height: 104)
        }
    }

    private var windowSideInsets: EdgeInsets {
        _ = windowHeight
        let window = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow)
        let insets = window?.safeAreaInsets ?? .zero
        return EdgeInsets(top: 0, leading: insets.left, bottom: 0, trailing: insets.right)
    }

    // MARK: Edit in place

    /// Under the hero, the tabs give way to rows with a pencil: the name in its own small sheet, the members, and what leaving or deleting does.
    @ViewBuilder
    private func editRows(_ details: GroupDetails) -> some View {
        VStack(spacing: 16) {
            SettingsCard {
                editRow("person.2", details.name, id: "group-edit-name", label: "Edit name, \(details.name)") { newName = details.name; renaming = true }
                editRow("person.crop.circle.badge.plus", "Members, \(details.members.count)", id: "group-edit-members", divider: false,
                        label: "Members, \(details.members.count). Opens the list") { editing = false; tab = .members }
            }
            SettingsFootnote(text: "The name is up to 50 characters. Only people in the group see it.")
            SettingsCard {
                Button { leaving = true } label: {
                    HStack { Text("Leave group").font(Theme.body).foregroundStyle(Color.red); Spacer(minLength: 0) }
                        .padding(.horizontal, 18).frame(minHeight: 58).contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityIdentifier("group-leave")
                if details.myRole == "owner" {
                    Button { deletingForEveryone = true } label: {
                        HStack { Text("Delete group").font(Theme.body).foregroundStyle(Color.red); Spacer(minLength: 0) }
                            .padding(.horizontal, 18).frame(minHeight: 58).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).accessibilityIdentifier("group-delete")
                } else {
                    Button { clearing = true } label: {
                        HStack { Text("Clear messages").font(Theme.body).foregroundStyle(Color.red); Spacer(minLength: 0) }
                            .padding(.horizontal, 18).frame(minHeight: 58).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).accessibilityIdentifier("group-clear")
                }
            }
        }
    }

    private func editRow(_ symbol: String, _ title: String, id: String, divider: Bool = true, label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    Image(systemName: symbol).font(.system(size: 20)).frame(width: 28).foregroundStyle(Theme.text).accessibilityHidden(true)
                    Text(title).font(Theme.body).foregroundStyle(Theme.text).lineLimit(2).multilineTextAlignment(.leading)
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
    private func content(_ details: GroupDetails) -> some View {
        switch tab {
        case .members: members(details)
        case .media: shared(.media)
        case .files: shared(.files)
        case .links: shared(.links)
        }
    }

    private func members(_ details: GroupDetails) -> some View {
        VStack(spacing: 12) {
            SettingsCard {
                if details.canAdd {
                    Button { adding = true } label: {
                        SettingsRowLabel(symbol: "person.badge.plus", title: "Add members", showsDivider: !details.members.isEmpty)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("group-add")
                }
                ForEach(details.members, id: \.userId) { member in memberRow(member, details: details) }
            }
            // LIME-270: a member whose new key you have not accepted gets no messages from this group until you do.
            ForEach(details.members.filter { !$0.isMe && keyChangePending($0) }, id: \.userId) { member in
                let first = member.name.split(separator: " ").first.map(String.init) ?? member.name
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(first)\u{2019}s key changed: accept it in your chat with \(first) to keep them in this group.")
                        .font(Theme.secondary).foregroundStyle(Theme.textSecondary)
                    Button("Open chat with \(first)") { store.openFromNotification("dm:\(member.userId)", thread: nil) }
                        .font(Theme.secondary.weight(.semibold)).foregroundStyle(Theme.text).frame(minHeight: 44, alignment: .leading)
                        .accessibilityIdentifier("group-key-open-\(member.userId)")
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 18)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("group-key-note-\(member.userId)")
            }
            SettingsFootnote(text: "Up to \(details.maxMembers) people. End-to-end encrypted: the server doesn't know this group, its name or who is in it.")
        }
    }

    /// Photos and videos, files or links shared in the whole group.
    @ViewBuilder
    private func shared(_ key: SharedKindKey) -> some View {
        let items = store.shared(in: target.conversationID, from: nil, kind: key.kind)
        switch key {
        case .media:
            let cells = Array(items.flatMap { m in m.attachments.filter { $0.kind == .image || $0.kind == .video }.map { (m, $0) } })
            if cells.isEmpty { empty("No photos or videos yet.") } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3), spacing: 4) {
                    ForEach(cells, id: \.1.id) { message, item in
                        MediaCell(item: item)
                            .onTapGesture { store.attachmentViewer = AttachmentViewerRequest(items: [item], index: 0, messageID: message.id, conversationID: target.conversationID) }
                    }
                }
                .accessibilityIdentifier("group-shared-media")
            }
        case .files:
            if items.isEmpty { empty("No files yet.") } else { SettingsCard { ForEach(items) { FileRow(message: $0) } }.accessibilityIdentifier("group-shared-files") }
        case .links:
            if items.isEmpty { empty("No links yet.") } else { SettingsCard { ForEach(items) { LinkRow(message: $0) } }.accessibilityIdentifier("group-shared-links") }
        }
    }

    private func empty(_ text: String) -> some View {
        Text(text).font(Theme.body).foregroundStyle(Theme.textSecondary).frame(maxWidth: .infinity).padding(.top, 12).accessibilityIdentifier("group-shared-empty")
    }

    private func keyChangePending(_ member: GroupMemberInfo) -> Bool {
        store.conversation("dm:\(member.userId)")?.keyChangePending == true
    }

    private func memberRow(_ member: GroupMemberInfo, details: GroupDetails) -> some View {
        let roleWord = member.role == "owner" ? "owner" : member.role == "admin" ? "admin" : nil
        let canMakeAdmin = details.myRole == "owner" && !member.isMe && member.role != "owner"
        return HStack(spacing: 14) {
            Button { store.openProfile(ProfileRoute(userID: member.userId, name: member.name, conversationID: target.conversationID, isMe: member.isMe)) } label: {
                HStack(spacing: 14) {
                    AvatarView(person: Person(id: member.userId, name: member.isMe ? "You" : member.name, tone: Int(member.tone)), size: 44, showsStatus: !member.isMe)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Text(member.name).font(Theme.body).foregroundStyle(Theme.text).lineLimit(1).layoutPriority(2)
                            if let label = member.label { LabelCapsule(text: label, id: "member-label-\(member.userId)") }
                            if !member.isMe && keyChangePending(member) {
                                Image(systemName: "exclamationmark.triangle").font(.system(size: 14)).foregroundStyle(Theme.textSecondary)
                                    .accessibilityLabel("New key not accepted")
                            }
                        }
                        if let roleWord { Text(roleWord.capitalized).font(Theme.caption).foregroundStyle(Theme.textSecondary) }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel([member.name, roleWord].compactMap { $0 }.joined(separator: ", "))
            .accessibilityIdentifier("group-member-open-\(member.userId)")
            if member.canRemove || canMakeAdmin {
                Menu {
                    if canMakeAdmin {
                        Button { Task { await store.setGroupAdmin(target.conversationID, user: member.userId, admin: member.role != "admin"); await refresh() } } label: {
                            Label(member.role == "admin" ? "Remove admin" : "Make admin", systemImage: "person.badge.key")
                        }
                        .accessibilityIdentifier("group-admin-\(member.userId)")
                    }
                    if member.canRemove {
                        Button(role: .destructive) { removing = member } label: { Label("Remove from group", systemImage: "person.badge.minus") }
                            .accessibilityIdentifier("group-remove-\(member.userId)")
                    }
                } label: { ToolIconLabel(symbol: "ellipsis") }
                    .accessibilityLabel("More for \(member.name)").accessibilityIdentifier("group-member-menu-\(member.userId)")
            }
        }
        .padding(.leading, 18).padding(.trailing, 6).frame(minHeight: 62)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("group-member-\(member.userId)")
    }
}

/// Rename: the new name (at most 50 characters) in a small sheet: ✕ at the left, the title centred, a round ✓ (dimmed until there is a valid change).
struct RenameGroupSheet: View {
    @Binding var name: String
    var finish: (_ saved: Bool) -> Void
    @FocusState private var focused: Bool

    private var cleaned: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSave: Bool { !cleaned.isEmpty && cleaned.count <= 50 }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Name", leading: .close { finish(false) }) {
                Button { finish(true) } label: {
                    Image(systemName: "checkmark").font(.system(size: 17, weight: .bold))
                        .foregroundStyle(canSave ? Theme.accentInk : Theme.textSecondary.opacity(0.6))
                        .frame(width: 44, height: 44)
                        .background { if canSave { Circle().fill(Theme.accent) } else { Color.clear.limeGlass() } }
                }
                .disabled(!canSave).accessibilityLabel("Save").accessibilityIdentifier("group-rename-save")
            }
            VStack(alignment: .leading, spacing: 12) {
                TextField("Group name", text: $name)
                    .font(Theme.body).selectionTint().focused($focused)
                    .padding(.horizontal, 16).frame(minHeight: 52)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .onChange(of: name) { _, value in if value.count > 50 { name = String(value.prefix(50)) } }
                    .onSubmit { if canSave { finish(true) } }
                    .accessibilityIdentifier("group-rename-field")
                Text("Up to 50 characters.").font(Theme.secondary).foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 16).padding(.top, 4)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .limeBackground()
        .presentationDetents([.medium])
        .onAppear { focused = true }
    }
}
