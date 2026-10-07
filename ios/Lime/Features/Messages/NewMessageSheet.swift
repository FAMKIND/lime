import SwiftUI

/// New message: one field (an exact username or email), Find, the person's name and school, Message.
/// Nothing is listed or matched partly; the server only answers an exact match, and not at all for a
/// teacher who chose not to be found.
struct NewMessageSheet: View {
    @Environment(ConversationStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var state: SearchState = .idle
    @FocusState private var focused: Bool

    enum SearchState: Equatable {
        case idle, searching
        case found(FoundUser)
        case nobody
        case problem(String)
    }

    private var kind: IdentifierKind { OnboardingModel.classify(query) }

    /// What the field says about itself, before anything is searched.
    private var note: String? {
        switch kind {
        case .phone: "Phone search is coming later. Use a username or email for now."
        case .invalid(let problem): problem
        default: nil
        }
    }

    private var canFind: Bool {
        guard state != .searching else { return false }
        switch kind {
        case .email, .username: return true
        default: return false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("New message").font(.system(.title2, design: .default, weight: .bold)).foregroundStyle(Theme.text)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Cancel") { dismiss() }
                    .font(Theme.body.weight(.medium)).foregroundStyle(Theme.text)
                    .accessibilityIdentifier("new-message-cancel")
            }
            Text("Find a teacher by their exact username or email.")
                .font(Theme.body).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField("Username or email", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.emailAddress)
                .submitLabel(.search)
                .focused($focused)
                .font(Theme.body)
                .padding(.horizontal, 16).frame(minHeight: 52)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityIdentifier("new-message-field")
                .onSubmit { if canFind { find() } }
                .onChange(of: query) { _, _ in
                    if state != .searching { state = .idle }
                }
            if let note, !query.isEmpty {
                Text(note).font(Theme.secondary).foregroundStyle(Theme.textSecondary)
                    .accessibilityIdentifier("new-message-note")
            }

            Button(action: find) {
                HStack {
                    if state == .searching { ProgressView().tint(Theme.accentInk) }
                    Text("Find").font(Theme.title)
                }
                .foregroundStyle(Theme.accentInk.opacity(canFind ? 1 : 0.5))
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Theme.accent.opacity(canFind ? 1 : 0.4), in: Capsule())
            }
            .disabled(!canFind)
            .accessibilityIdentifier("find-button")

            result
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.canvas.ignoresSafeArea())
        .presentationDetents([.large])
        .onAppear { focused = true }
        #if DEBUG
        .task {
            // Screenshots: open already searched for a made-up teacher.
            if store.demoSheet == "new-message-found" { query = "grace.h"; find() }
        }
        #endif
    }

    @ViewBuilder
    private var result: some View {
        switch state {
        case .found(let person) where person.isSelf:
            Text("That's you. Try another teacher.")
                .font(Theme.body).foregroundStyle(Theme.textSecondary)
                .accessibilityIdentifier("find-result-self")
        case .found(let person):
            VStack(spacing: 16) {
                HStack(spacing: 14) {
                    AvatarView(person: Person(id: person.userId, name: person.displayName), size: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(person.displayName).font(Theme.title).foregroundStyle(Theme.text)
                            .accessibilityIdentifier("find-result-name")
                        if let detail = Self.detail(person) {
                            Text(detail).font(Theme.secondary).foregroundStyle(Theme.textSecondary)
                        }
                        if let about = Self.about(person) {
                            Text(about).font(Theme.secondary).foregroundStyle(Theme.textSecondary).lineLimit(2)
                                .accessibilityIdentifier("find-result-about")
                        }
                    }
                    Spacer(minLength: 0)
                }
                Button {
                    Task {
                        await store.startChat(with: person)
                        dismiss()
                    }
                } label: {
                    Text("Message").font(Theme.title).foregroundStyle(Theme.primaryInk)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Theme.primary, in: Capsule())
                }
                .accessibilityIdentifier("message-button")
            }
            .padding(16)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        case .nobody:
            Text("No teacher found with that username or email.")
                .font(Theme.body).foregroundStyle(Theme.textSecondary)
                .accessibilityIdentifier("find-result-none")
        case .problem(let text):
            Text(text).font(Theme.body).foregroundStyle(Color.red)
                .accessibilityIdentifier("find-result-problem")
        case .idle, .searching:
            EmptyView()
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

    private func find() {
        let text = query.trimmingCharacters(in: .whitespaces)
        state = .searching
        Task {
            do {
                if let person = try await store.find(text) { state = .found(person) } else { state = .nobody }
            } catch {
                let problem = ConnectionProblem.from(error)
                store.report(problem)
                state = .problem(problem.message)
            }
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
