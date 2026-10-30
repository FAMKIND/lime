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
    @Environment(\.dismiss) private var dismiss
    @State private var chosen: [String] = []
    @State private var query = ""

    private var existing: [String] { if case .add(_, let ids) = mode { ids } else { [] } }
    private var teachers: [KnownTeacher] { KnownTeachers.from(store.conversations, includingKeyChanges: true).filter { !existing.contains($0.person.id) } }
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
                        Text(section.letter).font(Theme.font(.subheadline, weight: .semibold)).foregroundStyle(Theme.textSecondary)
                            .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 4).accessibilityAddTraits(.isHeader)
                        ForEach(section.teachers) { teacher in
                            let on = chosen.contains(teacher.person.id)
                            Button {
                                // A new key must be accepted in the one-to-one chat first (LIME-270).
                                if teacher.needsKey { dismiss(); store.openFromNotification(teacher.id, thread: nil) } else { toggle(teacher.person.id) }
                            } label: {
                                HStack(spacing: 14) {
                                    AvatarView(person: teacher.person, size: 44)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(teacher.person.name).font(Theme.body).foregroundStyle(Theme.text)
                                        if teacher.needsKey { Text("New key: accept first").font(Theme.caption).foregroundStyle(Theme.textSecondary) }
                                    }
                                    Spacer(minLength: 0)
                                    if teacher.needsKey {
                                        Image(systemName: "exclamationmark.triangle").font(.system(size: 20)).foregroundStyle(Theme.textSecondary)
                                    } else {
                                        Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                            .font(.system(size: 24)).foregroundStyle(on ? Theme.text : Theme.textSecondary.opacity(0.6))
                                    }
                                }
                                .padding(.horizontal, 20).frame(minHeight: 60).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityElement(children: .combine)
                            .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
                            .accessibilityHint(teacher.needsKey ? "Opens your chat to accept their new key" : "")
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
/// The name a new group starts with, from the first names of the people picked (the person making it is not counted).
enum GroupNames {
    static let limit = 50

    /// The rule lives in the core (so Android shows the same names, and the core can tell a chosen name from the default).
    static func defaultName(firstNames: [String]) -> String { defaultGroupName(firstNames: firstNames) }
}

struct GroupNameScreen: View {
    let members: [String]
    var onBack: () -> Void
    var onCreated: () -> Void
    @Environment(ConversationStore.self) private var store
    @State private var name = ""
    /// The name was typed by the person: stop following the members.
    @State private var edited = false
    @State private var emoji = ""
    @State private var avatarMode: GroupAvatarMode = .emoji
    @State private var photo: UIImage?
    @State private var making = false
    @FocusState private var focused: Bool

    private static let limit = 50
    private var cleaned: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canCreate: Bool { !cleaned.isEmpty && cleaned.count <= Self.limit && !making }
    private var people: [Person] { KnownTeachers.from(store.conversations).map(\.person).filter { members.contains($0.id) } }

    /// The first names of the picked people, in the order they were picked.
    private var defaultName: String {
        let byID = Dictionary(uniqueKeysWithValues: people.map { ($0.id, $0) })
        return GroupNames.defaultName(firstNames: members.compactMap { byID[$0] }.map { $0.name.split(separator: " ").first.map(String.init) ?? $0.name })
    }

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
                        TextField("Group name", text: Binding(get: { name }, set: { name = String($0.prefix(Self.limit)); edited = true }))
                            .font(Theme.body).selectionTint().focused($focused)
                            .padding(.horizontal, 16).frame(minHeight: 52)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .accessibilityIdentifier("group-name-field")
                        Text("\(min(cleaned.count, Self.limit))/\(Self.limit)").font(Theme.caption).foregroundStyle(Theme.textSecondary).padding(.horizontal, 6)
                            .accessibilityIdentifier("group-name-count")
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(members.count + 1) members").font(Theme.font(.subheadline, weight: .semibold)).foregroundStyle(Theme.textSecondary)
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
        .onAppear { if name.isEmpty && !edited { name = defaultName } }
        .onChange(of: members) { _, _ in if !edited { name = defaultName } }
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
