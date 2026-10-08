import SwiftUI

// MARK: The teachers you know (pure, so it can be tested without a screen)

/// A teacher you already message: someone with an accepted one-to-one chat.
struct KnownTeacher: Identifiable, Equatable, Sendable {
    /// The conversation's id (tapping the row opens that chat).
    let id: String
    let person: Person
}

enum KnownTeachers {
    struct Section: Equatable, Identifiable {
        let letter: String
        let teachers: [KnownTeacher]
        var id: String { letter }
    }

    /// Everyone with an accepted direct chat (requests, groups and blocked people are not teachers you know).
    static func from(_ conversations: [Conversation]) -> [KnownTeacher] {
        conversations.compactMap { c in
            guard !c.isRequest, !c.isGroup, let person = c.members.first else { return nil }
            return KnownTeacher(id: c.id, person: person)
        }
    }

    /// The index letter of a name: its first letter, accents and case ignored; "#" for anything else.
    static func letter(for name: String) -> String {
        guard let first = name.trimmingCharacters(in: .whitespaces).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).uppercased().first,
              first.isASCII, first.isLetter else { return "#" }
        return String(first)
    }

    /// The A–Z sections (with "#" last), names sorted inside each, narrowed to the names the filter matches.
    static func sections(_ teachers: [KnownTeacher], filter: String = "") -> [Section] {
        let wanted = filter.trimmingCharacters(in: .whitespaces)
        let shown = wanted.isEmpty ? teachers : teachers.filter { SearchText.matches($0.person.name, query: wanted) }
        let grouped = Dictionary(grouping: shown) { letter(for: $0.person.name) }
        let order = (grouped.keys.filter { $0 != "#" }.sorted()) + (grouped["#"] == nil ? [] : ["#"])
        return order.map { key in
            Section(letter: key, teachers: grouped[key]!.sorted { $0.person.name.localizedStandardCompare($1.person.name) == .orderedAscending })
        }
    }

    /// The letters down the index rail: A–Z and "#".
    static let rail: [String] = (65...90).map { String(UnicodeScalar($0)!) } + ["#"]
}

/// What a lookup field accepts: the exact thing, nothing partial.
@MainActor
enum LookupKind: Hashable {
    case username, email

    var title: String { self == .username ? "Find by Username" : "Find by Email" }
    var placeholder: String { self == .username ? "Username" : "Email address" }
    var hint: String { self == .username ? "Enter a teacher's exact username." : "Enter a teacher's exact email address." }

    /// True when `text` is a complete username (or email, as asked), so Next can be pressed.
    func accepts(_ text: String) -> Bool {
        switch (self, OnboardingModel.classify(text)) {
        case (.username, .username), (.email, .email): true
        default: false
        }
    }

    /// The text sent to the server: a username without a leading "@".
    func query(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return self == .username ? trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "@")) : trimmed
    }
}

/// One exact lookup on the server, and what it said.
@MainActor
@Observable
final class TeacherLookup {
    enum State: Equatable {
        case idle, searching
        case found(FoundUser)
        case nobody
        case problem(String)
    }

    private(set) var state: State = .idle
    private var generation = 0

    func reset() { generation += 1; state = .idle }

    func run(_ text: String, store: ConversationStore) async {
        generation += 1
        let mine = generation
        state = .searching
        do {
            let person = try await store.find(text)
            guard mine == generation else { return }
            state = person.map { .found($0) } ?? .nobody
        } catch {
            guard mine == generation else { return }
            let problem = ConnectionProblem.from(error)
            store.report(problem)
            state = .problem(problem.message)
        }
    }
}

// MARK: New Message

/// New Message: the teachers you already message, A to Z, with a search at the bottom. Typing filters
/// them; pressing search looks up one exact username or email on the server. Nothing is listed or
/// matched partly by the server, and a teacher who chose not to be found is not found.
struct NewMessageSheet: View {
    @Environment(ConversationStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var lookup = TeacherLookup()
    @State private var route = NavigationPath()
    @State private var inviting = false
    @FocusState private var focused: Bool
    @Environment(AccountSession.self) private var session

    private var known: [KnownTeacher] { KnownTeachers.from(store.conversations) }
    private var sections: [KnownTeachers.Section] { KnownTeachers.sections(known, filter: query) }
    private var typed: String { query.trimmingCharacters(in: .whitespaces) }

    /// The search field is an exact lookup when it holds a whole username or email.
    private var lookupKind: LookupKind? {
        switch OnboardingModel.classify(query) {
        case .email: .email
        case .username: .username
        default: nil
        }
    }

    var body: some View {
        NavigationStack(path: $route) {
            home
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: LookupKind.self) { kind in FindByScreen(kind: kind, closeSheet: { dismiss() }) }
                .navigationDestination(for: NewGroupRoute.self) { step in
                    switch step {
                    case .pick:
                        GroupPickerScreen(mode: .create, onNext: { route.append(NewGroupRoute.name($0)) }, onBack: { route.removeLast() })
                    case .name(let members):
                        GroupNameScreen(members: members, onBack: { route.removeLast() }, onCreated: { dismiss() })
                    }
                }
        }
        .tint(Theme.text)
        .presentationDetents([.large])
        .presentationBackground(Theme.canvas)
        .inviteFlow(start: $inviting, username: session.profile?.username)
        #if DEBUG
        .task {
            // Screenshots and UI tests: open already at a lookup.
            switch store.demoSheet {
            case "scan": route.append(LookupKind.username)
            case "new-message-found": query = "grace.h"; await lookup.run("grace.h", store: store)
            case "new-message-filter": query = "l"
            case "find-username", "find-username-found": route.append(LookupKind.username)
            case "new-group": route.append(NewGroupRoute.pick)
            case "new-group-name": route.append(NewGroupRoute.pick); route.append(NewGroupRoute.name(["lee", "sam"]))
            default: break
            }
        }
        #endif
    }

    // MARK: Home

    private var home: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "New Message", leading: .close { dismiss() })
            ScrollViewReader { proxy in
                ZStack(alignment: .trailing) {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            result
                            if typed.isEmpty { actions }
                            ForEach(sections) { section in
                                Text(section.letter)
                                    .font(Theme.secondary.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                                    .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 4)
                                    .id("section-\(section.letter)")
                                    .accessibilityAddTraits(.isHeader)
                                ForEach(section.teachers) { teacher in
                                    Button { open(teacher) } label: { TeacherRow(person: teacher.person) }
                                        .buttonStyle(.plain)
                                        .accessibilityIdentifier("known-\(teacher.id)")
                                }
                            }
                            if typed.isEmpty && !known.isEmpty {
                                Text("More")
                                    .font(Theme.secondary.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                                    .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 4)
                                    .accessibilityAddTraits(.isHeader)
                                actionRow("person.crop.circle.badge.plus", "Invite teachers to Lime", id: "action-invite") { inviting = true }
                                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                                    .padding(.horizontal, 16).padding(.bottom, 12)
                            }
                            if typed.isEmpty && known.isEmpty {
                                Text("Find teachers by their username or email.")
                                    .font(Theme.body).foregroundStyle(Theme.textSecondary)
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: .infinity).padding(.top, 28).padding(.horizontal, 32)
                                    .accessibilityIdentifier("new-message-empty")
                                InviteCard { inviting = true }
                            } else if !typed.isEmpty && sections.isEmpty && lookup.state == .idle {
                                Text(lookupKind == nil ? "No one you message matches. Search for a whole username or email to find someone new."
                                                       : "No one you message matches. Press search to look up “\(typed)”.")
                                    .font(Theme.secondary).foregroundStyle(Theme.textSecondary)
                                    .padding(.horizontal, 24).padding(.top, 20)
                                    .accessibilityIdentifier("new-message-no-local")
                            }
                        }
                        .padding(.trailing, typed.isEmpty && !known.isEmpty ? 24 : 0)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .accessibilityIdentifier("new-message-list")
                    if typed.isEmpty, !known.isEmpty {
                        IndexRail(available: Set(sections.map(\.letter))) { letter in
                            proxy.scrollTo("section-\(letter)", anchor: .top)
                        }
                    }
                }
            }
        }
        .background(Theme.canvas.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) { searchBar }
    }

    private var actions: some View {
        VStack(spacing: 0) {
            actionRow("at", "Find by Username", id: "action-username") { route.append(LookupKind.username) }
            Divider().padding(.leading, 56)
            actionRow("envelope", "Find by Email", id: "action-email") { route.append(LookupKind.email) }
            Divider().padding(.leading, 56)
            actionRow("person.2", "New Group", id: "action-new-group") { route.append(NewGroupRoute.pick) }
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 6)
    }

    private func actionRow(_ symbol: String, _ title: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol).font(.system(size: 18)).frame(width: 28)
                Text(title).font(Theme.body)
                Spacer()
            }
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 18).frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    /// The exact lookup's answer, above the list.
    @ViewBuilder
    private var result: some View {
        switch lookup.state {
        case .idle: EmptyView()
        case .searching:
            HStack(spacing: 10) { ProgressView(); Text("Searching…").font(Theme.secondary).foregroundStyle(Theme.textSecondary) }
                .padding(.horizontal, 20).padding(.vertical, 14)
                .accessibilityIdentifier("lookup-searching")
        case .found(let person): LookupResult(person: person) { start(person) }
        case .nobody: LookupNobody()
        case .problem(let text): LookupProblem(text: text)
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.textSecondary)
            TextField("Name, username or email", text: $query)
                .font(Theme.body)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.emailAddress)
                .submitLabel(.search)
                .focused($focused)
                .selectionTint()
                .accessibilityIdentifier("new-message-field")
                .onSubmit { search() }
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.textSecondary)
                }
                .accessibilityLabel("Clear").accessibilityIdentifier("new-message-clear")
            }
        }
        .foregroundStyle(Theme.text)
        .padding(.horizontal, 16).frame(minHeight: 52)
        .limeGlass(in: Capsule())
        .padding(.horizontal, 16).padding(.vertical, 8)
        .onChange(of: query) { _, _ in
            if lookup.state != .searching { lookup.reset() }
        }
    }

    // MARK: Actions

    private func search() {
        guard let kind = lookupKind else { return }
        Task { await lookup.run(kind.query(query), store: store) }
    }

    private func open(_ teacher: KnownTeacher) {
        store.path.append(teacher.id)
        dismiss()
    }

    private func start(_ person: FoundUser) {
        Task {
            await store.startChat(with: person)
            dismiss()
        }
    }

    nonisolated static func detail(_ person: FoundUser) -> String? {
        let parts = [person.username.map { "@\($0)" }, person.school].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The About line, when they wrote one ("👋 Happy to help").
    nonisolated static func about(_ person: FoundUser) -> String? {
        let parts = [person.aboutEmoji, person.aboutText].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}

// MARK: Pieces

/// A sheet's top row: a glass ✕ or ‹ at the left, a centred title, and something optional at the right.
struct SheetHeader<Trailing: View>: View {
    enum Leading { case close(() -> Void), back(() -> Void) }

    let title: String
    let leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        ZStack {
            Text(title).font(.system(.headline, design: .default, weight: .semibold)).foregroundStyle(Theme.text)
                .accessibilityAddTraits(.isHeader)
            HStack {
                switch leading {
                case .close(let action):
                    Button(action: action) {
                        Image(systemName: "xmark").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
                            .frame(width: 44, height: 44).limeGlass(in: Circle())
                    }
                    .accessibilityLabel("Close").accessibilityIdentifier("new-message-cancel")
                case .back(let action):
                    Button(action: action) {
                        Image(systemName: "chevron.left").font(.system(size: 17, weight: .medium)).foregroundStyle(Theme.text)
                            .frame(width: 44, height: 44).limeGlass(in: Circle())
                    }
                    .accessibilityLabel("Back").accessibilityIdentifier("find-back")
                }
                Spacer()
                trailing
            }
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)
    }
}

extension SheetHeader where Trailing == EmptyView {
    init(title: String, leading: Leading) {
        self.init(title: title, leading: leading, trailing: { EmptyView() })
    }
}

/// A teacher in the list: avatar and name.
struct TeacherRow: View {
    let person: Person

    var body: some View {
        HStack(spacing: 14) {
            AvatarView(person: person, size: 44)
            Text(person.name).font(Theme.body).foregroundStyle(Theme.text)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20).frame(minHeight: 60)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// The A–Z strip down the right edge: touch or drag to jump to a letter. Letters nobody has are dimmed.
struct IndexRail: View {
    let available: Set<String>
    let jump: (String) -> Void
    @State private var last: String?

    var body: some View {
        GeometryReader { geometry in
            let letters = KnownTeachers.rail
            let step = geometry.size.height / CGFloat(letters.count)
            VStack(spacing: 0) {
                ForEach(letters, id: \.self) { letter in
                    Text(letter)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(available.contains(letter) ? Theme.text : Theme.textSecondary.opacity(0.5))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityLabel("Jump to \(letter)")
                        .accessibilityIdentifier("index-\(letter)")
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { if available.contains(letter) { jump(letter) } }
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                let index = min(max(Int(drag.location.y / step), 0), letters.count - 1)
                // The nearest letter that has someone in it, so a drag never lands on nothing.
                let target = (index..<letters.count).lazy.map { letters[$0] }.first(where: available.contains)
                    ?? (0..<index).reversed().lazy.map { letters[$0] }.first(where: available.contains)
                guard let target, target != last else { return }
                last = target
                jump(target)
            }.onEnded { _ in last = nil })
        }
        .frame(width: 22)
        .frame(maxHeight: 520)
        .padding(.trailing, 2)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("index-rail")
    }
}

/// A found teacher as one row: tap it to message them.
struct LookupResult: View {
    let person: FoundUser
    let start: () -> Void

    var body: some View {
        if person.isSelf {
            Text("That's you. Try another teacher.")
                .font(Theme.body).foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 20).padding(.vertical, 14)
                .accessibilityIdentifier("find-result-self")
        } else {
            Button(action: start) {
                HStack(spacing: 14) {
                    AvatarView(person: Person(id: person.userId, name: person.displayName), size: 48)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(person.displayName).font(Theme.title).foregroundStyle(Theme.text)
                            .accessibilityIdentifier("find-result-name")
                        if let detail = NewMessageSheet.detail(person) {
                            Text(detail).font(Theme.secondary).foregroundStyle(Theme.textSecondary)
                        }
                        if let about = NewMessageSheet.about(person) {
                            Text(about).font(Theme.secondary).foregroundStyle(Theme.textSecondary).lineLimit(2)
                                .accessibilityIdentifier("find-result-about")
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .padding(.horizontal, 16).padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("find-result-row")
        }
    }
}

struct LookupNobody: View {
    var body: some View {
        Text("No teacher found with that username or email.")
            .font(Theme.body).foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 20).padding(.vertical, 14)
            .accessibilityIdentifier("find-result-none")
    }
}

struct LookupProblem: View {
    let text: String

    var body: some View {
        Text(text).font(Theme.body).foregroundStyle(Color.red)
            .padding(.horizontal, 20).padding(.vertical, 14)
            .accessibilityIdentifier("find-result-problem")
    }
}

/// Find by Username / Find by Email: one field, then Next looks that exact person up.
struct FindByScreen: View {
    let kind: LookupKind
    /// Leaves New Message altogether (Back only leaves this screen).
    let closeSheet: () -> Void
    @Environment(ConversationStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var lookup = TeacherLookup()
    @State private var scanning = false
    @FocusState private var focused: Bool

    private var canNext: Bool { kind.accepts(text) && lookup.state != .searching }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(title: kind.title, leading: .back { dismiss() }) {
                Button { next() } label: {
                    Text("Next").font(Theme.title).foregroundStyle(Theme.accentInk)
                        .padding(.horizontal, 18).frame(minHeight: 44)
                        .background(Theme.accent.opacity(canNext ? 1 : 0.4), in: Capsule())
                        .opacity(canNext ? 1 : 0.6)
                }
                .disabled(!canNext)
                .accessibilityIdentifier("find-next")
            }
            Text(kind.hint).font(Theme.secondary).foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 20).padding(.bottom, 10)
            TextField(kind.placeholder, text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(kind == .email ? .emailAddress : .asciiCapable)
                .submitLabel(.next)
                .focused($focused)
                .selectionTint()
                .font(Theme.body)
                .padding(.horizontal, 16).frame(minHeight: 52)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal, 16)
                .accessibilityIdentifier("find-by-field")
                .onSubmit { if canNext { next() } }
                .onChange(of: text) { _, _ in if lookup.state != .searching { lookup.reset() } }
            if kind == .username {
                Button { focused = false; scanning = true } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "qrcode.viewfinder").font(.system(size: 18)).frame(width: 28)
                        Text("Scan QR Code").font(Theme.body)
                        Spacer()
                    }
                    .foregroundStyle(Theme.text).padding(.horizontal, 18).frame(minHeight: 56).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal, 16).padding(.top, 12)
                .accessibilityIdentifier("find-scan-qr")
            }
            switch lookup.state {
            case .idle: EmptyView()
            case .searching:
                HStack(spacing: 10) { ProgressView(); Text("Searching…").font(Theme.secondary).foregroundStyle(Theme.textSecondary) }
                    .padding(20)
            case .found(let person): LookupResult(person: person) { start(person) }.padding(.top, 8)
            case .nobody: LookupNobody().padding(.top, 8)
            case .problem(let message): LookupProblem(text: message).padding(.top, 8)
            }
            Spacer(minLength: 0)
        }
        .background(Theme.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .swipeBackEnabled()
        .onAppear { focused = !scanning }
        .navigationDestination(isPresented: $scanning) { ScanQRScreen(closeSheet: closeSheet) }
        #if DEBUG
        .task {
            if store.demoSheet == "scan", kind == .username { scanning = true }
            if store.demoSheet == "find-username-found", kind == .username { text = "grace.h"; await lookup.run("grace.h", store: store) }
            if store.demoSheet == "find-username", kind == .username { text = "gr" }
        }
        #endif
    }

    private func next() {
        focused = false
        Task { await lookup.run(kind.query(text), store: store) }
    }

    private func start(_ person: FoundUser) {
        Task {
            await store.startChat(with: person)
            closeSheet()
        }
    }
}

/// Strangers' first messages. Open one to read it, then Accept or Block.
struct RequestsView: View {
    @Environment(ConversationStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                Text("People who aren't in your chats yet. Nothing is shared with them until you accept.")
                    .font(Theme.secondary).foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20).padding(.bottom, 8)
                ForEach(store.requests) { conversation in
                    NavigationLink(value: conversation.id) {
                        ConversationRow(conversation: conversation)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("request-row-\(conversation.id)")
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
        }
        .refreshable { await store.syncNow() }
        .background(Theme.canvas.ignoresSafeArea())
        .navigationTitle("Requests")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .accessibilityIdentifier("requests-list")
        // Nothing left to answer: go back to Messages.
        .onChange(of: store.requests.isEmpty) { _, empty in if empty { dismiss() } }
    }
}
