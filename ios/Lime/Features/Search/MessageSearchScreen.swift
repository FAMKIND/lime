import SwiftUI

/// Search from Messages: one field, then Chats (name or title matches) and Messages (the words in
/// context, matched words in bold). It runs on this iPhone only; the screen says so. Tapping a message
/// opens its chat scrolled to it.
struct MessageSearchScreen: View {
    @Environment(ConversationStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(AccountSession.self) private var session
    /// People (LIME-205): the exact lookup runs only when the person presses it, never on a keystroke.
    /// Opened from jam, its posts come first (LIME-223).
    var jamFirst = false
    /// Opened from the call tab: a Calls section comes first (people to call, then matching recent calls) (LIME-224).
    var callsFirst = false
    @State private var lookup = TeacherLookup()
    @State private var inviting = false
    @State private var query = ""
    @State private var results = SearchResults()
    @State private var searched = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    content
                }
                .padding(.horizontal, 12).padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.immediately)
            .accessibilityIdentifier("search-results")
        }
        .background(Theme.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .swipeBackEnabled()
        .inviteFlow(start: $inviting, username: session.profile?.username)
        .onChange(of: query) { _, _ in if lookup.state != .searching { lookup.reset() } }
        .onAppear {
            focused = true
            #if DEBUG
            if let typed = store.demoQuery, query.isEmpty { query = typed }
            #endif
        }
        .task(id: query) {
            let wanted = query
            if wanted.trimmingCharacters(in: .whitespaces).isEmpty {
                results = SearchResults(); searched = ""
                return
            }
            try? await Task.sleep(for: .milliseconds(120)) // wait for a pause in typing
            guard !Task.isCancelled else { return }
            let found = await store.search(wanted)
            guard !Task.isCancelled else { return }
            results = found
            searched = wanted
        }
    }

    private var header: some View {
        SearchHeader(placeholder: "Search people, chats, messages and jam", query: $query, focused: $focused, onSubmit: { findOnLime() }) { dismiss() }
    }

    // MARK: People (LIME-205)

    /// Contacts and the members of your groups whose name or username match: from what this phone already has.
    private var people: [Person] {
        let wanted = query.trimmingCharacters(in: .whitespaces)
        guard !wanted.isEmpty else { return [] }
        let me = store.meProvider().id
        var seen = Set<String>(), out: [Person] = []
        for conversation in store.conversations where !conversation.isRequest && conversation.id != store.selfChatID {
            for person in conversation.members where person.id != me && !seen.contains(person.id) {
                seen.insert(person.id)
                if SearchText.matches(person.name + " " + (person.label ?? ""), query: wanted) { out.append(person) }
            }
        }
        return out.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The text as an exact lookup: one whole username (with or without @) or an email.
    private var lookupKind: LookupKind? {
        let text = query.trimmingCharacters(in: .whitespaces)
        if LookupKind.email.accepts(text) { return .email }
        if LookupKind.username.accepts(text) { return .username }
        return nil
    }

    private func findOnLime() {
        guard let kind = lookupKind, lookup.state != .searching else { return }
        Task { await lookup.run(kind.query(query), store: store) }
    }

    @ViewBuilder
    private var peopleSection: some View {
        let typed = !query.trimmingCharacters(in: .whitespaces).isEmpty
        if typed {
            sectionTitle("People")
            ForEach(callsFirst ? [] : people, id: \.id) { person in
                Button { store.openProfile(ProfileRoute(userID: person.id, name: person.name, isMe: false)) } label: {
                    HStack(spacing: 12) {
                        AvatarView(person: person, size: 44).accessibilityHidden(true)
                        Text(person.name).font(Theme.title).foregroundStyle(Theme.text).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 10).frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityIdentifier("search-person-\(person.id)")
            }
            if let kind = lookupKind {
                let label = kind == .email ? "Find \(kind.query(query)) on lime" : "Find @\(kind.query(query)) on lime"
                Button { findOnLime() } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "magnifyingglass").frame(width: 44, height: 44).background(Theme.surface, in: Circle()).accessibilityHidden(true)
                        Text(label).font(Theme.title).foregroundStyle(Theme.text).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 6).frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityLabel("\(label), button").accessibilityIdentifier("search-find-on-lime")
                lookupResult
            }
            Button { inviting = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "person.badge.plus").frame(width: 44, height: 44).background(Theme.surface, in: Circle()).accessibilityHidden(true)
                    Text("Invite a teacher").font(Theme.title).foregroundStyle(Theme.text)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8).padding(.vertical, 6).frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityIdentifier("search-invite")
        }
    }

    /// The exact lookup's answer (the same views New Message uses).
    @ViewBuilder
    private var lookupResult: some View {
        switch lookup.state {
        case .idle: EmptyView()
        case .searching:
            HStack(spacing: 10) { ProgressView(); Text("Searching\u{2026}").font(Theme.secondary).foregroundStyle(Theme.textSecondary) }
                .padding(.horizontal, 8).padding(.vertical, 12).accessibilityIdentifier("lookup-searching")
        case .found(let person): LookupResult(person: person) { Task { await store.startChat(with: person) } }
        case .nobody: LookupNobody()
        case .problem(let text): LookupProblem(text: text)
        }
    }

    @ViewBuilder
    private var content: some View {
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "lock.shield").font(.system(size: 28)).foregroundStyle(Theme.textSecondary)
                Text("Search your chats, messages and jam.").font(Theme.body).foregroundStyle(Theme.text).accessibilityIdentifier("search-hint")
                Text("Search happens on this iPhone only. Nothing you type is sent anywhere.")
                    .font(Theme.secondary).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
                Text("Find a teacher by their username or email.").font(Theme.secondary).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
                Button { inviting = true } label: { Text("Invite a teacher").font(Theme.secondary.weight(.semibold)).foregroundStyle(Theme.text).frame(minHeight: 44) }
                    .accessibilityIdentifier("search-invite")
            }
            .frame(maxWidth: .infinity).padding(.top, 60).padding(.horizontal, 24)
        } else if results.isEmpty && searched == query && callPeople.isEmpty && callGroups.isEmpty {
            callsSection
            peopleSection
            Text("No results for “\(query.trimmingCharacters(in: .whitespaces))”")
                .font(Theme.body).foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity).padding(.top, 30)
                .accessibilityIdentifier("search-none")
        } else {
            callsSection
            if jamFirst { jamSection }
            peopleSection
            if !results.chats.isEmpty {
                sectionTitle("Chats")
                ForEach(results.chats) { conversation in
                    NavigationLink(value: conversation.id) {
                        HStack(spacing: 12) {
                            ConversationAvatar(conversation: conversation, size: 44)
                            Text(conversation.title).font(Theme.title).foregroundStyle(Theme.text).lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 10).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("search-chat-\(conversation.id)")
                }
            }
            if !results.messages.isEmpty {
                sectionTitle("Messages")
                ForEach(results.messages) { hit in
                    if let root = hit.threadRoot {
                        NavigationLink(value: ThreadTarget(conversationID: hit.conversationID, rootID: root, focusMessageID: hit.messageID, words: SearchText.words(query))) { messageRow(hit) }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("search-message-\(hit.messageID)")
                            .accessibilityLabel("\(hit.conversationTitle), in Replies: \(SearchText.plain(hit.marked))")
                    } else {
                        NavigationLink(value: ChatTarget(conversationID: hit.conversationID, messageID: hit.messageID, words: SearchText.words(query))) { messageRow(hit) }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("search-message-\(hit.messageID)")
                            .accessibilityLabel("\(hit.conversationTitle): \(SearchText.plain(hit.marked))")
                    }
                }
            }
            if !jamFirst { jamSection }
        }
    }

    // MARK: Calls (LIME-224)

    private var callPeople: [Person] { callsFirst ? people : [] }
    private var callGroups: [CallGroup] {
        let typed = query.trimmingCharacters(in: .whitespaces)
        guard callsFirst, !typed.isEmpty else { return [] }
        return CallGrouping.groups(CallLog.shared.records.filter { $0.peerName.localizedCaseInsensitiveContains(typed) })
    }

    /// From the call tab: the people you can call, each with the one call control, then the calls that match.
    @ViewBuilder
    private var callsSection: some View {
        if !callPeople.isEmpty || !callGroups.isEmpty {
            sectionTitle("Calls")
            ForEach(callPeople, id: \.id) { person in
                HStack(spacing: 8) {
                    Button { store.openProfile(ProfileRoute(userID: person.id, name: person.name, isMe: false)) } label: {
                        HStack(spacing: 12) {
                            AvatarView(person: person, size: 44).accessibilityHidden(true)
                            Text(person.name).font(Theme.title).foregroundStyle(Theme.text).lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .frame(minHeight: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).accessibilityIdentifier("search-person-\(person.id)")
                    CallMenuButton(name: person.name, id: "calls-search-\(person.id)",
                                   voice: { Task { _ = await store.calls.start(peerID: person.id, name: person.name, video: false) } },
                                   video: { Task { _ = await store.calls.start(peerID: person.id, name: person.name, video: true) } })
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
            }
            ForEach(callGroups) { group in CallRowView(group: group) }
        }
    }

    /// Jam posts, articles and podcasts you can read; each opens its post in the jam tab.
    @ViewBuilder
    private var jamSection: some View {
        if !results.jam.isEmpty {
            sectionTitle("jam")
            ForEach(results.jam) { hit in
                Button { open(hit) } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(hit.title).font(Theme.title).foregroundStyle(Theme.text).lineLimit(1)
                            Spacer(minLength: 4)
                            Text(JamDates.short(Int64(hit.date.timeIntervalSince1970 * 1000))).font(Theme.secondary).foregroundStyle(Theme.textSecondary)
                        }
                        Text(hit.from).font(Theme.secondary).foregroundStyle(Theme.textSecondary).lineLimit(1)
                        Text(SearchText.attributed(hit.marked)).font(Theme.secondary).foregroundStyle(Theme.textSecondary).lineLimit(2).multilineTextAlignment(.leading)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 10).contentShape(Rectangle())
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(hit.title), \(hit.from)").accessibilityHint("Opens the post")
                .accessibilityIdentifier("search-jam-\(hit.postID)")
            }
        }
    }

    private func open(_ hit: JamHit) {
        store.section = .jam
        dismiss()
        Task { try? await Task.sleep(for: .milliseconds(350)); store.jamPath.append(JamPostRoute(postID: hit.postID)) }
    }

    private func messageRow(_ hit: MessageHit) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(hit.conversationTitle).font(Theme.title).foregroundStyle(Theme.text).lineLimit(1)
                if hit.threadRoot != nil {
                    Label("in Replies", systemImage: "arrowshape.turn.up.left").labelStyle(.titleAndIcon)
                        .font(Theme.caption).foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 4)
                Text(MessageFormat.listTime(hit.date)).font(Theme.secondary).foregroundStyle(Theme.textSecondary)
            }
            Text(hit.snippet).font(Theme.secondary).foregroundStyle(Theme.textSecondary).lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 8).padding(.vertical, 10).contentShape(Rectangle())
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text).font(Theme.font(.subheadline, weight: .semibold)).foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 8).padding(.top, 14).padding(.bottom, 2)
            .accessibilityAddTraits(.isHeader)
    }
}

/// The search screens' top row: a glass back button and a glass field (shared by Messages and Calls).
struct SearchHeader: View {
    let placeholder: String
    @Binding var query: String
    var focused: FocusState<Bool>.Binding
    /// Pressing Search on the keyboard (LIME-205: Messages' search runs the exact lookup then).
    var onSubmit: (() -> Void)? = nil
    let back: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: back) {
                Image(systemName: "chevron.left").font(.system(size: 18, weight: .medium)).foregroundStyle(Theme.text)
                    .frame(width: 48, height: 48).limeGlass()
            }
            .accessibilityLabel("Back").accessibilityIdentifier("search-back")
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.textSecondary)
                TextField(placeholder, text: $query)
                    .font(Theme.body)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .focused(focused)
                    .selectionTint()
                    .accessibilityIdentifier("search-field")
                    .onSubmit { onSubmit?() }
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.textSecondary)
                    }
                    .accessibilityLabel("Clear").accessibilityIdentifier("search-clear")
                }
            }
            .padding(.horizontal, 14).frame(minHeight: 48)
            .limeGlass(in: Capsule())
        }
        .padding(.horizontal, 12).padding(.top, 4).padding(.bottom, 8)
    }
}
