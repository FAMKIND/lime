import SwiftUI

// MARK: New Group (from New Message) and Add Members (from a group's details)

/// The steps of making a group inside the New Message sheet.
enum NewGroupRoute: Hashable {
    case pick
    case name([String])
}

/// Picks people from the teachers you already message: chips on top, "N Members", a search at the bottom, Next.
/// Used to make a group (Next goes to the name) and to add people to one (the button adds them).
struct GroupPickerScreen: View {
    enum Mode: Equatable {
        case create
        case add(conversationID: String, existing: [String])
    }

    let mode: Mode
    /// Create: Next with the chosen ids. Add: called after the people were added.
    var onNext: ([String]) -> Void = { _ in }
    var onBack: () -> Void
    @Environment(ConversationStore.self) private var store
    @State private var chosen: [String] = []
    @State private var query = ""

    private var existing: [String] { if case .add(_, let ids) = mode { ids } else { [] } }
    private var teachers: [KnownTeacher] { KnownTeachers.from(store.conversations).filter { !existing.contains($0.person.id) } }
    private var sections: [KnownTeachers.Section] { KnownTeachers.sections(teachers, filter: query) }
    private var title: String { mode == .create ? "New Group" : "Add Members" }
    private var countText: String {
        mode == .create ? "\(chosen.count + 1) Member\(chosen.count + 1 == 1 ? "" : "s")" : "\(chosen.count) selected"
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: title, leading: .back { onBack() }) {
                Button { onNext(chosen) } label: {
                    Text(mode == .create ? "Next" : "Add").font(Theme.title).foregroundStyle(Theme.accentInk)
                        .padding(.horizontal, 18).frame(minHeight: 44)
                        .background(Theme.accent.opacity(chosen.isEmpty ? 0.4 : 1), in: Capsule())
                        .opacity(chosen.isEmpty ? 0.6 : 1)
                }
                .disabled(chosen.isEmpty)
                .accessibilityIdentifier("group-next")
            }
            Text(countText).font(Theme.secondary).foregroundStyle(Theme.textSecondary)
                .accessibilityIdentifier("group-count")
                .frame(maxWidth: .infinity)
            if !chosen.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(chosen, id: \.self) { id in
                            if let person = teachers.first(where: { $0.person.id == id })?.person {
                                Button { chosen.removeAll { $0 == id } } label: {
                                    HStack(spacing: 6) {
                                        AvatarView(person: person, size: 26)
                                        Text(person.name.split(separator: " ").first.map(String.init) ?? person.name).font(Theme.secondary).foregroundStyle(Theme.text)
                                        Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.textSecondary)
                                    }
                                    .padding(.leading, 6).padding(.trailing, 10).padding(.vertical, 5)
                                    .background(Theme.surface, in: Capsule())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Remove \(person.name)")
                                .accessibilityIdentifier("group-chip-\(id)")
                            }
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 8)
                }
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if teachers.isEmpty {
                        Text(mode == .create ? "Find teachers by their username or email first; a group is made of people you already message."
                                             : "Everyone you message is already in this group.")
                            .font(Theme.body).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity).padding(.top, 40).padding(.horizontal, 32)
                            .accessibilityIdentifier("group-no-teachers")
                    }
                    ForEach(sections) { section in
                        Text(section.letter).font(Theme.secondary.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                            .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 4).accessibilityAddTraits(.isHeader)
                        ForEach(section.teachers) { teacher in
                            let on = chosen.contains(teacher.person.id)
                            Button { toggle(teacher.person.id) } label: {
                                HStack(spacing: 14) {
                                    AvatarView(person: teacher.person, size: 44)
                                    Text(teacher.person.name).font(Theme.body).foregroundStyle(Theme.text)
                                    Spacer(minLength: 0)
                                    Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 24)).foregroundStyle(on ? Theme.text : Theme.textSecondary.opacity(0.6))
                                }
                                .padding(.horizontal, 20).frame(minHeight: 60).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityElement(children: .combine)
                            .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
                            .accessibilityIdentifier("group-pick-\(teacher.person.id)")
                        }
                    }
                }
                .padding(.bottom, 80)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Theme.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.textSecondary)
                TextField("Search teachers", text: $query)
                    .font(Theme.body).textInputAutocapitalization(.never).autocorrectionDisabled().selectionTint()
                    .accessibilityIdentifier("group-search")
            }
            .padding(.horizontal, 16).frame(minHeight: 52).limeGlass(in: Capsule())
            .padding(.horizontal, 16).padding(.vertical, 8)
        }
        .swipeBackEnabled()
    }

    private func toggle(_ id: String) {
        if let index = chosen.firstIndex(of: id) { chosen.remove(at: index) } else { chosen.append(id) }
    }
}

/// The group's name (required, at most 50 characters) and an optional emoji, then Create.
struct GroupNameScreen: View {
    let members: [String]
    var onBack: () -> Void
    var onCreated: () -> Void
    @Environment(ConversationStore.self) private var store
    @State private var name = ""
    @State private var emoji = ""
    @State private var avatarMode: GroupAvatarMode = .emoji
    @State private var photo: UIImage?
    @State private var making = false
    @FocusState private var focused: Bool

    private static let limit = 50
    private var cleaned: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canCreate: Bool { !cleaned.isEmpty && cleaned.count <= Self.limit && !making }
    private var people: [Person] { KnownTeachers.from(store.conversations).map(\.person).filter { members.contains($0.id) } }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "New Group", leading: .back { onBack() }) {
                Button { create() } label: {
                    Text("Create").font(Theme.title).foregroundStyle(Theme.accentInk)
                        .padding(.horizontal, 18).frame(minHeight: 44)
                        .background(Theme.accent.opacity(canCreate ? 1 : 0.4), in: Capsule())
                        .opacity(canCreate ? 1 : 0.6)
                }
                .disabled(!canCreate)
                .accessibilityIdentifier("group-create")
            }
            ScrollView {
                VStack(spacing: 18) {
                    GroupAvatarEditor(mode: $avatarMode, emoji: $emoji, photo: $photo, fallback: initials)
                    VStack(alignment: .leading, spacing: 6) {
                        // The field never holds more than the limit (the extra characters are dropped as they are typed).
                        TextField("Group name", text: Binding(get: { name }, set: { name = String($0.prefix(Self.limit)) }))
                            .font(Theme.body).selectionTint().focused($focused)
                            .padding(.horizontal, 16).frame(minHeight: 52)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .accessibilityIdentifier("group-name-field")
                        Text("\(min(cleaned.count, Self.limit))/\(Self.limit)").font(Theme.caption).foregroundStyle(Theme.textSecondary).padding(.horizontal, 6)
                            .accessibilityIdentifier("group-name-count")
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(members.count + 1) members").font(Theme.secondary.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(people) { person in
                                    VStack(spacing: 4) {
                                        AvatarView(person: person, size: 44)
                                        Text(person.name.split(separator: " ").first.map(String.init) ?? person.name).font(Theme.caption).foregroundStyle(Theme.text).lineLimit(1)
                                    }.frame(width: 56)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(20)
            }
        }
        .background(Theme.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { focused = true }
        .swipeBackEnabled()
    }

    private var initials: String {
        let letters = cleaned.split(separator: " ").prefix(2).compactMap(\.first)
        return letters.isEmpty ? "👥" : String(letters).uppercased()
    }

    private func create() {
        making = true
        Task {
            let chosenEmoji = avatarMode == .emoji && !emoji.isEmpty ? emoji : nil
            let made = await store.createGroup(name: cleaned, emoji: chosenEmoji, members: members)
            // A photo needs the group to exist first: it is set right after (and goes to the members with the next delivery).
            if let made, avatarMode == .photo, let photo, let jpeg = PhotoProcessing.jpeg(photo) { _ = await store.setGroupPhoto(jpeg, in: made) }
            onCreated()
        }
    }
}

// MARK: Group details

/// A group's name and avatar, its people with their roles, and what you may do: rename, add, remove, leave.
struct GroupDetailsView: View {
    let target: GroupTarget
    @Environment(ConversationStore.self) private var store
    @State private var details: GroupDetails?
    @State private var renaming = false
    @State private var newName = ""
    @State private var removing: GroupMemberInfo?
    @State private var leaving = false
    @State private var adding = false
    @State private var editingAvatar = false

    var body: some View {
        SettingsPage(title: "Group details") {
            if let details {
                header(details)
                SettingsCard {
                    ForEach(Array(details.members.enumerated()), id: \.element.userId) { index, member in
                        memberRow(member, last: index == details.members.count - 1 && !details.canAdd)
                    }
                    if details.canAdd {
                        Button { adding = true } label: {
                            SettingsRowLabel(symbol: "person.badge.plus", title: "Add members", showsDivider: false)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("group-add")
                    }
                }
                SettingsFootnote(text: "Up to \(details.maxMembers) people. Messages are end-to-end encrypted: the server does not know this group, its name or who is in it.")
                SettingsCard {
                    Button { leaving = true } label: {
                        SettingsRowLabel(symbol: "rectangle.portrait.and.arrow.right", title: "Leave group", showsDivider: false, destructive: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("group-leave")
                }
            } else {
                ProgressView().padding(.top, 60)
            }
        }
        .task { await refresh() }
        .sheet(isPresented: $editingAvatar) {
            GroupAvatarSheet(conversationID: target.conversationID, currentEmoji: details?.emoji, hasPhoto: details?.hasPhoto ?? false) { changed in
                editingAvatar = false
                if changed { Task { await refresh() } }
            }
        }
        .sheet(isPresented: $renaming) {
            RenameGroupSheet(name: $newName) { saved in
                renaming = false
                if saved { Task { _ = await store.renameGroup(target.conversationID, to: newName); await refresh() } }
            }
        }
        .confirmationDialog("Remove \(removing?.name ?? "")?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                if let member = removing { Task { await store.removeFromGroup(target.conversationID, user: member.userId); await refresh() } }
            }
            .accessibilityIdentifier("group-remove-confirm")
            Button("Cancel", role: .cancel) {}
        } message: { Text("They will not get new messages from this group.") }
        .confirmationDialog("Leave \(details?.name ?? "this group")?", isPresented: $leaving, titleVisibility: .visible) {
            Button("Leave group", role: .destructive) {
                Task {
                    await store.leaveGroup(target.conversationID)
                    store.path = NavigationPath()
                }
            }
            .accessibilityIdentifier("group-leave-confirm")
            Button("Cancel", role: .cancel) {}
        } message: { Text("You won't get new messages from this group. Someone can add you back.") }
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

    private func header(_ details: GroupDetails) -> some View {
        VStack(spacing: 10) {
            Button { editingAvatar = true } label: {
                ZStack(alignment: .bottomTrailing) {
                    Group {
                        if let photo = AvatarCache.shared.image(for: target.conversationID) {
                            Image(uiImage: photo).resizable().scaledToFill().frame(width: 88, height: 88).clipShape(Circle())
                        } else {
                            Circle().fill(Theme.surface).frame(width: 88, height: 88).overlay(Text(details.emoji ?? "👥").font(.system(size: 44)))
                        }
                    }
                    if details.canRename {
                        Image(systemName: "pencil").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.accentInk)
                            .frame(width: 26, height: 26).background(Theme.accent, in: Circle())
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(!details.canRename)
            .accessibilityLabel("Group picture")
            .accessibilityIdentifier("group-details-avatar")
            Button {
                newName = details.name
                renaming = true
            } label: {
                HStack(spacing: 6) {
                    Text(details.name).font(.system(.title2, design: .default, weight: .bold)).foregroundStyle(Theme.text)
                    if details.canRename { Image(systemName: "pencil").font(.system(size: 15)).foregroundStyle(Theme.textSecondary) }
                }
            }
            .buttonStyle(.plain)
            .disabled(!details.canRename)
            .accessibilityIdentifier("group-details-name")
            Text("\(details.members.count) members").font(Theme.secondary).foregroundStyle(Theme.textSecondary)
                .accessibilityIdentifier("group-details-count")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private func memberRow(_ member: GroupMemberInfo, last: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                AvatarView(person: Person(id: member.userId, name: member.isMe ? "You" : member.name, tone: Int(member.tone)), size: 44)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(member.name).font(Theme.body).foregroundStyle(Theme.text)
                        if let label = member.label { Text(label).font(Theme.caption).foregroundStyle(Theme.textSecondary).lineLimit(1) }
                    }
                    if member.role != "member" {
                        Text(member.role == "owner" ? "Owner" : "Admin").font(Theme.caption).foregroundStyle(Theme.textSecondary)
                    }
                }
                Spacer(minLength: 0)
                if member.canRemove {
                    Button { removing = member } label: {
                        Text("Remove").font(Theme.secondary.weight(.semibold)).foregroundStyle(Color.red)
                            .padding(.horizontal, 10).frame(minHeight: 36)
                    }
                    .accessibilityIdentifier("group-remove-\(member.userId)")
                }
            }
            .padding(.horizontal, 18).frame(minHeight: 62)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("group-member-\(member.userId)")
            if !last { Divider().overlay(Theme.hairline).padding(.leading, 76) }
        }
    }
}

/// Rename: the new name (at most 50 characters), Save and Cancel.
struct RenameGroupSheet: View {
    @Binding var name: String
    var finish: (_ saved: Bool) -> Void
    @FocusState private var focused: Bool

    private var cleaned: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSave: Bool { !cleaned.isEmpty && cleaned.count <= 50 }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Button("Cancel") { finish(false) }.foregroundStyle(Theme.text).accessibilityIdentifier("group-rename-cancel")
                Spacer()
                Text("Rename group").font(Theme.title).foregroundStyle(Theme.text)
                Spacer()
                Button("Save") { finish(true) }.font(Theme.title).foregroundStyle(Theme.text).disabled(!canSave)
                    .accessibilityIdentifier("group-rename-save")
            }
            TextField("Group name", text: $name)
                .font(Theme.body).selectionTint().focused($focused)
                .padding(.horizontal, 16).frame(minHeight: 52)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .onChange(of: name) { _, value in if value.count > 50 { name = String(value.prefix(50)) } }
                .onSubmit { if canSave { finish(true) } }
                .accessibilityIdentifier("group-rename-field")
            Text("Up to 50 characters.").font(Theme.secondary).foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(20)
        .background(Theme.canvas.ignoresSafeArea())
        .presentationDetents([.medium])
        .onAppear { focused = true }
    }
}
