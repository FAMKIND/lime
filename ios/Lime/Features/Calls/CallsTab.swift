import SwiftUI

/// A group of calls opened from the list (the details screen finds them again by id).
struct CallGroupRoute: Hashable {
    let ids: [String]
}

/// Words for a call in the details list.
extension CallRecord {
    var outcomeText: String {
        switch outcome {
        case .completed: Self.clock(duration)
        case .missed: outgoing ? "No answer" : "Missed"
        case .declined: "Declined"
        case .noAnswer: "No answer"
        case .busy: "Busy"
        case .failed: "Failed"
        }
    }
}

/// The call tab's search screen is pushed onto the tab's path.
struct CallSearchRoute: Hashable {}

/// One history row: avatar with its status badge, name (red when missed, "(3)" when grouped), kind, time, and the call-back button.
struct CallRowView: View {
    let group: CallGroup
    @Environment(ConversationStore.self) private var store
    @ScaledMetric(relativeTo: .body) private var avatarSize: CGFloat = 52

    /// The person as the chats know them (their colour and label), or a plain one.
    private func person(_ call: CallRecord) -> Person {
        store.conversations.first { !$0.isGroup && $0.members.first?.id == call.peerID }?.members.first ?? Person(id: call.peerID, name: call.peerName, tone: 0)
    }

    var body: some View {
        let call = group.first
        let missed = group.isMissedIncoming
        HStack(spacing: 12) {
            Button { store.callPath.append(CallGroupRoute(ids: group.records.map(\.id))) } label: {
                HStack(spacing: 12) {
                    AvatarView(person: person(call), size: avatarSize, showsStatus: true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(call.peerName + (group.count > 1 ? " (\(group.count))" : ""))
                            .font(Theme.title.weight(.semibold))
                            .foregroundStyle(missed ? Color.red : Theme.text)
                            .lineLimit(1)
                            .accessibilityIdentifier("call-row-name")
                        HStack(spacing: 5) {
                            Image(systemName: call.outgoing ? "arrow.up.right" : "arrow.down.left").font(.caption)
                            Text(call.video ? "Video" : "Voice")
                        }
                        .font(Theme.secondary).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer(minLength: 8)
                    Text(CallGrouping.timeLabel(call.date)).font(Theme.secondary).foregroundStyle(Theme.textSecondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("call-history-row")
            Button { Task { _ = await store.calls.start(peerID: call.peerID, name: call.peerName, video: call.video) } } label: {
                Image(systemName: call.video ? "video" : "phone").font(.system(size: 17))
                    .foregroundStyle(Theme.text).frame(width: 40, height: 40)
                    .background(Theme.surface, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(call.video ? "Video call \(call.peerName)" : "Call \(call.peerName)")
            .accessibilityIdentifier("call-row-callback")
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
    }
}

/// The call tab's root (LIME-116b/c): the history fills the screen and scrolls under the header and the tab bar (faded like Messages);
/// All | Missed floats under the header as a glass segmented control; grouped rows with a call-back button; swipe to delete; "+" for New Call.
struct CallHistoryView: View {
    @Environment(ConversationStore.self) private var store
    @State private var showNewCall = false
    private let log = CallLog.shared

    private var shown: [CallRecord] {
        store.callMissedOnly ? log.records.filter(\.isMissedIncoming) : log.records
    }

    /// The room left at the end of the list for the "+" above the tab bar.
    private let bottomMargin: CGFloat = FloatingPlus.size + 32

    var body: some View {
        let groups = CallGrouping.groups(shown)
        Group {
            if #available(iOS 26, *) {
                // Exactly as Messages: top margin 8 and the system's soft edge effect at both ends, nothing else.
                content(groups, topMargin: 8)
                    .scrollEdgeEffectStyle(.soft, for: .top)
                    .scrollEdgeEffectStyle(.soft, for: .bottom)
            } else {
                // Exactly as Messages: top margin 76 under the same veil and header controls (see `rootHeader(overlays:)`).
                content(groups, topMargin: 76)
            }
        }
        .background(Theme.canvas.ignoresSafeArea().accessibilityIdentifier("calls-screen"))
        .navigationBarTitleDisplayMode(.inline)
        .rootHeader(searchID: "calls-search-button", overlays: true) { store.callPath.append(CallSearchRoute()) }
        .overlay { FloatingPlus(label: "New call", id: "new-call-button") { showNewCall = true } }
        .sheet(isPresented: $showNewCall) { NewCallSheet() }
    }

    // MARK: All | Missed

    /// The system's segmented control (on iOS 26 it is the Liquid Glass one with the sliding selection). It is the first row of the list
    /// (it scrolls away with the rows), centred.
    private var filter: some View {
        Picker("Calls", selection: Binding(get: { store.callMissedOnly }, set: { store.callMissedOnly = $0 })) {
            Text("All").tag(false)
            Text("Missed").tag(true)
        }
        .pickerStyle(.segmented)
        .frame(width: 240)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .accessibilityIdentifier("calls-filter")
    }

    // MARK: List

    private func content(_ groups: [CallGroup], topMargin: CGFloat) -> some View {
        List {
            filter
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            if groups.isEmpty {
                empty
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            ForEach(groups) { group in
                CallRowView(group: group)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) { log.delete(ids: group.records.map(\.id)) } label: { Label("Delete", systemImage: "trash") }
                            .tint(.red).accessibilityIdentifier("call-swipe-delete")
                    }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, topMargin, for: .scrollContent)
        .contentMargins(.bottom, bottomMargin, for: .scrollContent)
        .accessibilityIdentifier("calls-list")
    }

    // MARK: Empty

    private var empty: some View {
        VStack(spacing: 14) {
            if store.callMissedOnly {
                Text("No missed calls").font(Theme.body).foregroundStyle(Theme.textSecondary).accessibilityIdentifier("calls-empty-missed")
            } else {
                Text("No calls yet").font(Theme.body).foregroundStyle(Theme.textSecondary).accessibilityIdentifier("calls-empty")
                Button { showNewCall = true } label: {
                    Text("New call").font(Theme.title).foregroundStyle(Theme.accentInk)
                        .padding(.horizontal, 22).frame(minHeight: 44).background(Theme.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("calls-empty-new-call")
            }
        }
        .frame(maxWidth: .infinity).padding(.top, 80)
    }
}

/// The call tab's search (pushed, like Messages' search): people you can call, and matching calls.
struct CallSearchScreen: View {
    @Environment(ConversationStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @FocusState private var focused: Bool
    private let log = CallLog.shared

    private var typed: String { query.trimmingCharacters(in: .whitespaces) }
    private var people: [KnownTeacher] {
        KnownTeachers.sections(KnownTeachers.from(store.conversations).filter { $0.id != store.selfChatID }, filter: typed).flatMap(\.teachers)
    }
    private var groups: [CallGroup] {
        CallGrouping.groups(log.records.filter { $0.peerName.localizedCaseInsensitiveContains(typed) })
    }

    var body: some View {
        VStack(spacing: 0) {
            SearchHeader(placeholder: "Search people and calls", query: $query, focused: $focused) { dismiss() }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if typed.isEmpty {
                        Text("Search for someone to call, or a call you made or missed.")
                            .font(Theme.body).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity).padding(.top, 60).padding(.horizontal, 24)
                            .accessibilityIdentifier("calls-search-hint")
                    } else if people.isEmpty && groups.isEmpty {
                        Text("No results for “\(typed)”")
                            .font(Theme.body).foregroundStyle(Theme.textSecondary)
                            .frame(maxWidth: .infinity).padding(.top, 60)
                            .accessibilityIdentifier("calls-search-none")
                    } else {
                        if !people.isEmpty {
                            title("People")
                            ForEach(people) { teacher in
                                HStack(spacing: 8) {
                                    TeacherRow(person: teacher.person)
                                    circle("phone", "Voice call \(teacher.person.name)", id: "calls-search-voice-\(teacher.person.id)") { start(teacher, video: false) }
                                    circle("video", "Video call \(teacher.person.name)", id: "calls-search-video-\(teacher.person.id)") { start(teacher, video: true) }
                                }
                                .padding(.trailing, 16)
                            }
                        }
                        if !groups.isEmpty {
                            title("Calls")
                            ForEach(groups) { group in CallRowView(group: group) }
                        }
                    }
                }
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.immediately)
            .accessibilityIdentifier("calls-search-results")
        }
        .background(Theme.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .swipeBackEnabled()
        .onAppear { focused = true }
    }

    private func title(_ text: String) -> some View {
        Text(text).font(Theme.secondary.weight(.semibold)).foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 4).accessibilityAddTraits(.isHeader)
    }

    private func circle(_ symbol: String, _ label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 16)).foregroundStyle(Theme.text)
                .frame(width: 40, height: 40).overlay(Circle().stroke(Theme.textSecondary.opacity(0.5), lineWidth: 1))
        }
        .buttonStyle(.plain).accessibilityLabel(label).accessibilityIdentifier(id)
    }

    private func start(_ teacher: KnownTeacher, video: Bool) {
        Task { _ = await store.calls.start(peerID: teacher.person.id, name: teacher.person.name, video: video) }
    }
}

/// One person's calls (a group from the list): who, Message · Voice · Video, and each call with its time, direction and outcome.
struct CallDetailsView: View {
    let route: CallGroupRoute
    @Environment(ConversationStore.self) private var store
    private let log = CallLog.shared

    private var records: [CallRecord] { log.records.filter { route.ids.contains($0.id) } }

    var body: some View {
        ScrollView {
            if let first = records.first {
                VStack(spacing: 18) {
                    AvatarView(person: Person(id: first.peerID, name: first.peerName, tone: 0), size: 96, showsStatus: true).padding(.top, 20)
                    Text(first.peerName).font(.title2.weight(.semibold)).foregroundStyle(Theme.text)
                    HStack(spacing: 12) {
                        action("message", "Message", id: "call-details-message") { store.openFromNotification("dm:\(first.peerID)", thread: nil) }
                        action("phone", "Voice", id: "call-details-voice") { Task { _ = await store.calls.start(peerID: first.peerID, name: first.peerName, video: false) } }
                        action("video", "Video", id: "call-details-video") { Task { _ = await store.calls.start(peerID: first.peerID, name: first.peerName, video: true) } }
                    }
                    .padding(.horizontal, 16)
                    VStack(spacing: 0) {
                        ForEach(records) { record in
                            HStack(spacing: 10) {
                                Image(systemName: record.outgoing ? "arrow.up.right" : "arrow.down.left").font(.caption).foregroundStyle(Theme.textSecondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(record.date.formatted(date: .abbreviated, time: .shortened)).font(Theme.body).foregroundStyle(Theme.text)
                                    Text(record.video ? "Video" : "Voice").font(Theme.caption).foregroundStyle(Theme.textSecondary)
                                }
                                Spacer()
                                Text(record.outcomeText)
                                    .font(Theme.secondary)
                                    .foregroundStyle(record.isMissedIncoming ? Color.red : Theme.textSecondary)
                                    .accessibilityIdentifier("call-detail-outcome")
                            }
                            .padding(.horizontal, 18).frame(minHeight: 58)
                        }
                    }
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .padding(.horizontal, 16)
                }
            }
        }
        .background(Theme.canvas.accessibilityIdentifier("call-details"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func action(_ symbol: String, _ title: String, id: String, perform: @escaping () -> Void) -> some View {
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
}

/// New Call (modelled on Signal's): find someone by username, or pick an accepted contact, A to Z, and call by voice or video. The search
/// field sits at the bottom.
struct NewCallSheet: View {
    @Environment(ConversationStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var route = NavigationPath()

    private var people: [KnownTeacher] { KnownTeachers.from(store.conversations).filter { $0.id != store.selfChatID } }
    private var sections: [KnownTeachers.Section] { KnownTeachers.sections(people, filter: query) }
    private var typed: String { query.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        NavigationStack(path: $route) {
            home
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: LookupKind.self) { kind in FindByScreen(kind: kind, closeSheet: { dismiss() }) }
        }
        .tint(Theme.text)
        .presentationDetents([.large])
        .presentationBackground(Theme.canvas)
    }

    private var home: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "New Call", leading: .close { dismiss() })
            ScrollViewReader { proxy in
                ZStack(alignment: .trailing) {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            if typed.isEmpty {
                                Button { route.append(LookupKind.username) } label: {
                                    HStack(spacing: 14) {
                                        Image(systemName: "at").font(.system(size: 18)).frame(width: 28)
                                        Text("Find by Username").font(Theme.body)
                                        Spacer()
                                    }
                                    .foregroundStyle(Theme.text).padding(.horizontal, 18).frame(minHeight: 56).contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                                .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 6)
                                .accessibilityIdentifier("new-call-find-username")
                            }
                            ForEach(sections) { section in
                                Text(section.letter)
                                    .font(Theme.secondary.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                                    .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 4)
                                    .id("section-\(section.letter)")
                                    .accessibilityAddTraits(.isHeader)
                                ForEach(section.teachers) { teacher in
                                    HStack(spacing: 8) {
                                        TeacherRow(person: teacher.person)
                                        circle("phone", "Voice call \(teacher.person.name)", id: "new-call-voice-\(teacher.person.id)") { call(teacher, video: false) }
                                        circle("video", "Video call \(teacher.person.name)", id: "new-call-video-\(teacher.person.id)") { call(teacher, video: true) }
                                    }
                                    .padding(.trailing, 28)
                                }
                            }
                            if sections.isEmpty {
                                Text(typed.isEmpty ? "People you message will appear here. Find someone by their username." : "No one you message matches.")
                                    .font(Theme.secondary).foregroundStyle(Theme.textSecondary)
                                    .padding(.horizontal, 24).padding(.top, 20)
                                    .accessibilityIdentifier("new-call-empty")
                            }
                        }
                    }
                    .scrollDismissesKeyboard(.interactively)
                    if typed.isEmpty, !people.isEmpty {
                        IndexRail(available: Set(sections.map(\.letter))) { letter in proxy.scrollTo("section-\(letter)", anchor: .top) }
                    }
                }
            }
        }
        .background(Theme.canvas.ignoresSafeArea().accessibilityIdentifier("new-call-sheet"))
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.textSecondary)
                TextField("Name or username", text: $query)
                    .font(Theme.body)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("new-call-field")
            }
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 16).frame(minHeight: 52)
            .limeGlass(in: Capsule())
            .padding(.horizontal, 16).padding(.vertical, 8)
        }
    }

    private func circle(_ symbol: String, _ label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 16)).foregroundStyle(Theme.text)
                .frame(width: 40, height: 40)
                .overlay(Circle().stroke(Theme.textSecondary.opacity(0.5), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }

    private func call(_ teacher: KnownTeacher, video: Bool) {
        dismiss()
        Task { _ = await store.calls.start(peerID: teacher.person.id, name: teacher.person.name, video: video) }
    }
}
