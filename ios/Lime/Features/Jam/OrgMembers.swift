import SwiftUI

extension OrgInvite: Identifiable { public var id: String { jamId } }

/// A band's Members tab (LIME-246c): Owners · Writers · Members, only for the band's members ("Only members see who's here."). Owners add people from their
/// contacts, share the invite link, and (per row) make someone an owner, writer or member, or remove them; everyone else can leave.
struct OrgMembersTab: View {
    let jamID: String
    @Environment(ConversationStore.self) private var store
    @State private var adding = false
    @State private var inviting = false
    @State private var removing: OrgMemberInfo?
    @State private var leaving = false

    private var members: [OrgMemberInfo] { store.orgMembersByJam[jamID] ?? [] }
    private var iRun: Bool { store.bandRole(jamID) == "owner" }
    /// Only the band's own owner makes owners.
    private var iOwn: Bool { store.jamsMine.contains { $0.jamId == jamID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Only members see who\u{2019}s here.").font(Theme.secondary).foregroundStyle(Theme.textSecondary).frame(maxWidth: .infinity)
                .multilineTextAlignment(.center).accessibilityIdentifier("org-members-private")
            if iRun {
                HStack(spacing: 10) {
                    pill("person.badge.plus", "Add members", id: "org-add-members") { adding = true }
                    pill("link", "Invite link", id: "org-invite-link") { inviting = true }
                }
            }
            section("Owners", role: "owner")
            section("Writers", role: "writer")
            section("Members", role: "member")
            if !iOwn {
                Button(role: .destructive) { leaving = true } label: {
                    Text("Leave band").font(Theme.body).foregroundStyle(Theme.danger).frame(maxWidth: .infinity, minHeight: 52)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain).accessibilityIdentifier("org-leave")
            }
        }
        .sheet(isPresented: $adding) {
            NavigationStack {
                GroupPickerScreen(mode: .add(conversationID: "", existing: members.map(\.userId)), onNext: { ids in
                    Task { await store.addOrgMembers(jamID, users: ids); adding = false }
                }, onBack: { adding = false })
            }
            .presentationDetents([.large])
        }
        .sheet(isPresented: $inviting) { OrgInviteSheet(jamID: jamID) }
        .confirmSheet("Remove \(removing?.name ?? "")?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            Button("Remove", role: .destructive) { if let removing { Task { await store.removeOrgMember(jamID, user: removing.userId) } }; removing = nil }.accessibilityIdentifier("org-remove-confirm")
            Button("Cancel", role: .cancel) { removing = nil }
        } message: { Text("They leave the band and its groups.") }
        .confirmSheet("Leave this band?", isPresented: $leaving) {
            Button("Leave band", role: .destructive) { Task { await store.leaveOrg(jamID) } }.accessibilityIdentifier("org-leave-confirm")
            Button("Cancel", role: .cancel) {}
        } message: { Text("You leave its members and its groups, and stop following it.") }
    }

    @ViewBuilder
    private func section(_ title: String, role: String) -> some View {
        let rows = members.filter { $0.role == role }
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(Theme.font(.subheadline, weight: .semibold)).foregroundStyle(Theme.textSecondary).accessibilityAddTraits(.isHeader)
                SettingsCard {
                    ForEach(Array(rows.enumerated()), id: \.element.userId) { index, member in
                        row(member)
                        if index < rows.count - 1 { Divider().overlay(Theme.hairline).padding(.leading, 66) }
                    }
                }
            }
        }
    }

    private func row(_ member: OrgMemberInfo) -> some View {
        let person = Person(id: member.userId, name: member.name, tone: Int(member.tone))
        return HStack(spacing: 12) {
            Button {
                store.openProfile(ProfileRoute(userID: member.userId, name: member.name, isMe: member.isMe))
            } label: {
                HStack(spacing: 12) {
                    AvatarView(person: person, size: 36).accessibilityHidden(true)
                    Text(member.name).font(Theme.body).foregroundStyle(Theme.text).lineLimit(1)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 56).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(member.name), \(member.role)").accessibilityHint("Opens their profile")
            .accessibilityIdentifier("org-member-\(member.userId)")
            if iRun && member.canManage {
                Menu {
                    if iOwn && member.role != "owner" { Button("Make owner") { Task { await store.setOrgRole(jamID, user: member.userId, role: "owner") } }.accessibilityIdentifier("org-role-owner") }
                    if member.role != "writer" { Button("Make writer") { Task { await store.setOrgRole(jamID, user: member.userId, role: "writer") } }.accessibilityIdentifier("org-role-writer") }
                    if member.role != "member" { Button("Make member") { Task { await store.setOrgRole(jamID, user: member.userId, role: "member") } }.accessibilityIdentifier("org-role-member") }
                    Button("Remove", role: .destructive) { removing = member }.accessibilityIdentifier("org-role-remove")
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.textSecondary).frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .accessibilityLabel("Options for \(member.name)").accessibilityIdentifier("org-member-menu-\(member.userId)")
            }
        }
        .padding(.horizontal, 18)
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Make owner") { if iOwn && iRun && member.canManage && member.role != "owner" { Task { await store.setOrgRole(jamID, user: member.userId, role: "owner") } } }
        .accessibilityAction(named: "Make writer") { if iRun && member.canManage { Task { await store.setOrgRole(jamID, user: member.userId, role: "writer") } } }
        .accessibilityAction(named: "Remove") { if iRun && member.canManage { removing = member } }
    }

    private func pill(_ symbol: String, _ title: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol).font(Theme.font(.subheadline, weight: .semibold)).foregroundStyle(Theme.text)
                .padding(.horizontal, 14).frame(minHeight: 44).background(Theme.surface, in: Capsule())
        }
        .buttonStyle(.plain).accessibilityIdentifier(id)
    }
}

/// The band's invite link: share it, show it as a QR code, turn it off, or make a new one (which replaces the old).
struct OrgInviteSheet: View {
    let jamID: String
    @Environment(ConversationStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var inviteLink: String?
    @State private var loaded = false

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Invite link", leading: .close { dismiss() })
            ScrollView {
                VStack(spacing: 18) {
                    if let link = inviteLink {
                        if let image = QRImage.make(link, size: 200) {
                            Image(uiImage: image).interpolation(.none).resizable().scaledToFit().frame(width: 200, height: 200).padding(12).background(Color.white, in: RoundedRectangle(cornerRadius: 12))
                                .accessibilityLabel("QR code for the invite link").accessibilityIdentifier("org-invite-qr")
                        }
                        Text(link).font(Theme.caption).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center).textSelection(.enabled).accessibilityIdentifier("org-invite-text")
                        if let url = URL(string: link) {
                            ShareLink(item: url) {
                                Text("Share").font(Theme.title).foregroundStyle(Theme.accentInk).padding(.horizontal, 24).frame(minHeight: 48).background(Theme.accent, in: Capsule())
                            }
                            .accessibilityIdentifier("org-invite-share")
                        }
                        HStack(spacing: 10) {
                            Button("New link") { Task { inviteLink = await store.resetOrgInvite(jamID, on: true); Announce.say("New invite link. The old link stopped working") } }.accessibilityIdentifier("org-invite-new")
                            Button("Turn off", role: .destructive) { Task { inviteLink = await store.resetOrgInvite(jamID, on: false); Announce.say("Invite link turned off") } }.accessibilityIdentifier("org-invite-off")
                        }
                        .font(Theme.secondary).frame(minHeight: 44)
                    } else if loaded {
                        Text("The link is off.").font(Theme.body).foregroundStyle(Theme.textSecondary).accessibilityIdentifier("org-invite-is-off")
                        Button("Turn on") { Task { inviteLink = await store.resetOrgInvite(jamID, on: true) } }.font(Theme.secondary).frame(minHeight: 44).accessibilityIdentifier("org-invite-on")
                    } else { ProgressView().padding(.top, 40) }
                    Text("Anyone with the link can ask to join. An owner\u{2019}s phone adds them the next time it is online.").font(Theme.caption).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
                }
                .padding(20)
            }
        }
        .limeBackground()
        .presentationDetents([.medium, .large])
        .task { inviteLink = await store.orgInviteLink(jamID); loaded = true }
    }
}

/// A band's Groups tab: its groups with who may join; Join on an open one ("You'll be added when an owner's phone is next online"); owners make a New group.
struct OrgGroupsTab: View {
    let jamID: String
    let title: String
    @Environment(ConversationStore.self) private var store
    @State private var making = false

    private var groups: [OrgGroupInfo] { store.orgGroupsByJam[jamID] ?? [] }
    private var iRun: Bool { store.bandRole(jamID) == "owner" }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if iRun {
                Button { making = true } label: {
                    Label("New group", systemImage: "plus").font(Theme.font(.subheadline, weight: .semibold)).foregroundStyle(Theme.text)
                        .padding(.horizontal, 14).frame(minHeight: 44).background(Theme.surface, in: Capsule())
                }
                .buttonStyle(.plain).accessibilityIdentifier("org-new-group")
            }
            if groups.isEmpty {
                Text("No groups yet.").font(Theme.body).foregroundStyle(Theme.textSecondary).frame(maxWidth: .infinity).padding(.top, 12).accessibilityIdentifier("org-no-groups")
            } else {
                SettingsCard {
                    ForEach(Array(groups.enumerated()), id: \.element.conversationId) { index, group in
                        row(group)
                        if index < groups.count - 1 { Divider().overlay(Theme.hairline).padding(.leading, 66) }
                    }
                }
            }
        }
        .sheet(isPresented: $making) { NewBandGroupSheet(jamID: jamID) }
    }

    private func row(_ group: OrgGroupInfo) -> some View {
        let state = store.orgJoinStates[group.conversationId]
        return HStack(spacing: 12) {
            ZStack {
                Circle().fill(Theme.avatar(AvatarTone.tone(for: group.conversationId)))
                Text(String(group.name.prefix(1)).uppercased()).font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.text)
            }
            .frame(width: 40, height: 40).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(group.name).font(Theme.body).foregroundStyle(Theme.text).lineLimit(1)
                Text(group.open ? "Open" : "Invite only").font(Theme.caption).foregroundStyle(Theme.textSecondary)
                if state == "asked" { Text("You\u{2019}ll be added when an owner\u{2019}s phone is next online.").font(Theme.caption).foregroundStyle(Theme.textSecondary).accessibilityIdentifier("org-group-waiting-\(group.conversationId)") }
            }
            Spacer(minLength: 0)
            if group.joined || state == "joined" {
                Button("Open") { store.openFromNotification(group.conversationId, thread: nil) }.font(Theme.secondary).frame(minHeight: 44).accessibilityIdentifier("org-group-open-\(group.conversationId)")
            } else if group.open && state != "asked" {
                Button("Join") { Task { await store.joinOrgGroup(jamID, group: group.conversationId) } }
                    .font(Theme.font(.subheadline, weight: .semibold)).foregroundStyle(Theme.accentInk).padding(.horizontal, 16).frame(minHeight: 44).background(Theme.accent, in: Capsule())
                    .accessibilityIdentifier("org-group-join-\(group.conversationId)")
            }
        }
        .padding(.horizontal, 18).frame(minHeight: 60)
        .accessibilityElement(children: .contain)
        .task(id: state) { if state == "asked" { await store.refreshOrgGroupJoin(jamID, group: group.conversationId) } }
        // The state replaces the button in place: say it, and leave focus on the row (LIME-130-6c).
        .onChange(of: state) { _, new in if let words = JoinSpeech.words(state: new, name: group.name) { Announce.say(words) } }
    }
}

/// An owner makes a group inside the band: a name, Open (any member may join) or Invite only, and the people to start with, from the band.
struct NewBandGroupSheet: View {
    let jamID: String
    @Environment(ConversationStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var open = true
    @State private var chosen: Set<String> = []
    @State private var making = false
    @FocusState private var focused: Bool

    private var cleaned: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canCreate: Bool { !cleaned.isEmpty && cleaned.count <= 50 && !making }
    private var others: [OrgMemberInfo] { (store.orgMembersByJam[jamID] ?? []).filter { !$0.isMe } }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "New group", leading: .close { dismiss() }) {
                Button { create() } label: {
                    Text(making ? "Creating\u{2026}" : "Create").font(Theme.title).foregroundStyle(Theme.accentInk).padding(.horizontal, 18).frame(minHeight: 44)
                        .background(Theme.accent.opacity(canCreate ? 1 : 0.4), in: Capsule())
                }
                .disabled(!canCreate).accessibilityIdentifier("org-group-create")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    TextField("Group name", text: Binding(get: { name }, set: { name = String($0.prefix(50)) })).font(Theme.body).selectionTint().focused($focused)
                        .padding(.horizontal, 16).frame(minHeight: 52).background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .accessibilityHint("Up to 50 characters").accessibilityIdentifier("org-group-name")
                    Picker("Who can join", selection: $open) {
                        Text("Open").tag(true)
                        Text("Invite only").tag(false)
                    }
                    .pickerStyle(.segmented).accessibilityIdentifier("org-group-open")
                    Text(open ? "Any member of the band can join." : "Only people you add are in it.").font(Theme.caption).foregroundStyle(Theme.textSecondary)
                    Text("Start with").font(Theme.font(.subheadline, weight: .semibold)).foregroundStyle(Theme.textSecondary).accessibilityAddTraits(.isHeader)
                    SettingsCard {
                        ForEach(Array(others.enumerated()), id: \.element.userId) { index, member in
                            Button {
                                if chosen.contains(member.userId) { chosen.remove(member.userId) } else { chosen.insert(member.userId) }
                            } label: {
                                HStack(spacing: 12) {
                                    AvatarView(person: Person(id: member.userId, name: member.name, tone: Int(member.tone)), size: 36).accessibilityHidden(true)
                                    Text(member.name).font(Theme.body).foregroundStyle(Theme.text)
                                    Spacer(minLength: 0)
                                    Image(systemName: chosen.contains(member.userId) ? "checkmark.circle.fill" : "circle").foregroundStyle(chosen.contains(member.userId) ? Theme.accent : Theme.textSecondary)
                                }
                                .padding(.horizontal, 18).frame(minHeight: 56).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(member.name)").accessibilityAddTraits(chosen.contains(member.userId) ? [.isSelected] : [])
                            .accessibilityIdentifier("org-group-pick-\(member.userId)")
                            if index < others.count - 1 { Divider().overlay(Theme.hairline).padding(.leading, 66) }
                        }
                    }
                }
                .padding(20)
            }
        }
        .limeBackground()
        .presentationDetents([.large])
        .onAppear { focused = true }
    }

    private func create() {
        making = true
        Task {
            let made = await store.createOrgGroup(jamID, name: cleaned, emoji: nil, open: open, members: Array(chosen))
            making = false
            if made == nil { store.showBanner("Couldn\u{2019}t make the group. Try again.") }   // spoken, and the sheet stays
            else { dismiss() }
        }
    }
}

/// "Join <band>?" from an invite link: Join, then the waiting state, then in.
struct JoinBandSheet: View {
    let invite: OrgInvite
    @Environment(ConversationStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private var state: String? { store.orgJoinStates[invite.jamId] }
    private var name: String { store.jamSubscriptions.first { $0.jamId == invite.jamId }?.title ?? store.publicProfiles[invite.writerId].map { "\($0.displayName)\u{2019}s band" } ?? "this band" }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Join \(name)?", leading: .close { dismiss() })
            VStack(spacing: 16) {
                switch state {
                case "asked":
                    Text("You\u{2019}ll be added when an owner\u{2019}s phone is next online.").font(Theme.body).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center).accessibilityIdentifier("org-join-waiting")
                case "joined":
                    Text("You\u{2019}re in.").font(Theme.body).foregroundStyle(Theme.text).accessibilityIdentifier("org-join-done")
                case "full":
                    Text("The band is full.").font(Theme.body).foregroundStyle(Theme.textSecondary).accessibilityIdentifier("org-join-full")
                case "refused":
                    Text("This link no longer works. Ask an owner for a new one.").font(Theme.body).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center).accessibilityIdentifier("org-join-refused")
                default:
                    Text("Members see each other and what the band shares with its members. Only members see who\u{2019}s here.").font(Theme.body).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
                    Button { Task { await store.joinOrg(invite) } } label: {
                        Text("Join").font(Theme.title).foregroundStyle(Theme.accentInk).padding(.horizontal, 32).frame(minHeight: 48).background(Theme.accent, in: Capsule())
                    }
                    .accessibilityIdentifier("org-join")
                }
            }
            .padding(24)
            Spacer(minLength: 0)
        }
        .limeBackground()
        .presentationDetents([.medium])
        .task(id: state) { if state == "asked" { await store.refreshOrgJoinState(invite.jamId) } }
        .onChange(of: state) { _, new in if let words = JoinSpeech.words(state: new, name: name) { Announce.say(words) } }
    }
}
