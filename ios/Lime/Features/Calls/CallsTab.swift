import SwiftUI

/// Words for a call in the details list.
extension CallRecord {
    var outcomeText: String {
        switch outcome {
        case .completed: Self.clock(duration)
        case .missed: outgoing ? "No answer" : "Missed"
        case .missedDnd, .missedHours: outgoing ? "No answer" : (outcome.silencedNote ?? "Missed")
        case .unavailable: "Unavailable"
        case .declined: "Declined"
        case .noAnswer: "No answer"
        case .busy: "Busy"
        case .failed: "Failed"
        }
    }
}

/// The call tab's search screen is pushed onto the tab's path.
struct CallSearchRoute: Hashable {}

/// What tapping a call in the history does (LIME-170): a person is called again the same way; a group is joined if its call is on now, else a new
/// one is started.
enum CallBackAction: Equatable {
    case callPerson
    case joinGroup(callID: String)
    case startGroup

    static func decide(isGroup: Bool, liveCallID: String?) -> CallBackAction {
        guard isGroup else { return .callPerson }
        return liveCallID.map { .joinGroup(callID: $0) } ?? .startGroup
    }
}

/// One history row: avatar with its status badge, name (red when missed, "(3)" when grouped), kind, time, and the call-back button.
struct CallRowView: View {
    let group: CallGroup
    @Environment(ConversationStore.self) private var store
    @ScaledMetric(relativeTo: .body) private var scaledAvatar: CGFloat = 52
    private var avatarSize: CGFloat { min(scaledAvatar, 64) }

    /// A group's call: its history row carries the group's conversation id (LIME-112b).
    private func isGroupCall(_ call: CallRecord) -> Bool { call.peerID.hasPrefix("grp:") }

    /// Calls them again the way the call was made, as the iPhone's Phone app does (LIME-170): a person, the same kind; a group, joining its call
    /// if one is on now, else starting a new one. The row and the round button on its right do the same thing.
    private func callBack(_ call: CallRecord) {
        let live = isGroupCall(call) ? store.groupCalls.core.activeCall(conversationID: call.peerID) : nil
        switch CallBackAction.decide(isGroup: isGroupCall(call), liveCallID: live?.callId) {
        case .callPerson:
            Task { _ = await store.calls.start(peerID: call.peerID, name: call.peerName, video: call.video) }
        case .joinGroup(let callID):
            Task { _ = await store.groupCalls.join(callID: callID, conversationID: call.peerID, title: call.peerName, video: live?.video ?? call.video) }
        case .startGroup:
            Task { _ = await store.groupCalls.start(conversationID: call.peerID, title: call.peerName, video: call.video) }
        }
    }

    /// The details a tap on a call used to open: the person's profile with these calls listed, or the group's details.
    private func openDetails(_ call: CallRecord) {
        if isGroupCall(call) {
            if store.conversation(call.peerID) != nil { store.callPath.append(GroupTarget(conversationID: call.peerID)) }
        } else {
            store.callPath.append(ProfileRoute(userID: call.peerID, name: call.peerName, callIDs: group.records.map(\.id)))
        }
    }

    /// What VoiceOver reads for the row: "Sam Park, Video call, 8:29 PM, missed".
    private func rowLabel(_ call: CallRecord, missed: Bool) -> String {
        let name = call.peerName + (group.count > 1 ? " (\(group.count))" : "")
        let note = call.outcome.silencedNote ?? (call.outcome == .unavailable ? "Unavailable" : nil)
        return "\(name), \(call.video ? "Video" : "Voice") call, \(CallGrouping.timeLabel(call.date))" + (missed ? ", missed" : "") + (note.map { ", \($0)" } ?? "")
    }

    /// The person as the chats know them (their colour and label), or a plain one.
    private func person(_ call: CallRecord) -> Person {
        if isGroupCall(call) { return Person(id: call.peerID, name: call.peerName, tone: abs(call.peerID.hashValue) % 8) }
        return store.conversations.first { !$0.isGroup && $0.members.first?.id == call.peerID }?.members.first ?? Person(id: call.peerID, name: call.peerName, tone: 0)
    }

    var body: some View {
        let call = group.first
        let missed = group.isMissedIncoming
        HStack(spacing: 12) {
            // The picture opens the details (nothing looks different); the rest of the row calls back.
            Button { openDetails(call) } label: {
                if isGroupCall(call), let chat = store.conversation(call.peerID) {
                    // A group call shows the group as the chat does: its photo, else its members' photos.
                    ConversationAvatar(conversation: chat, size: avatarSize)
                } else {
                    AvatarView(person: person(call), size: avatarSize)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(call.peerName), details")
            .accessibilityIdentifier("call-row-avatar")
            Button { callBack(call) } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(call.peerName + (group.count > 1 ? " (\(group.count))" : ""))
                                .font(Theme.font(.body, weight: .semibold))
                                .foregroundStyle(missed ? Color.red : Theme.text)
                                .lineLimit(1)
                                .accessibilityIdentifier("call-row-name")
                            Spacer(minLength: 4)
                            Text(CallGrouping.timeLabel(call.date)).font(Theme.secondary).foregroundStyle(Theme.textSecondary)
                        }
                        HStack(spacing: 5) {
                            Image(systemName: call.outgoing ? "arrow.up.right" : "arrow.down.left").font(Theme.font(.caption))
                            Text(call.video ? "Video" : "Voice")
                        }
                        .font(Theme.secondary).foregroundStyle(Theme.textSecondary)
                        if let note = call.outcome.silencedNote ?? (call.outcome == .unavailable ? "Unavailable" : nil) {
                            Text(note).font(Theme.caption).foregroundStyle(Theme.textSecondary).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("call-row-note")
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(rowLabel(call, missed: missed))
            .accessibilityHint("Double-tap to call back")
            .accessibilityAction(named: "Details") { openDetails(call) }
            .accessibilityIdentifier("call-history-row")
            Button { callBack(call) } label: {
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

    private var shown: [CallRecord] { store.callFilter.apply(log.records, missedOnly: store.callMissedOnly) }

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

    /// All | Missed and the filter button: the first row of the list (it scrolls away with the rows).
    private var filter: some View {
        @Bindable var store = store
        return FilterRow(first: "All", second: "Missed", secondSelected: $store.callMissedOnly, activeCount: store.callFilter.activeCount, idPrefix: "calls-filter") {
            Section("Kind") {
                Toggle("Voice", isOn: Binding(get: { store.callFilter.video == false }, set: { store.callFilter.video = $0 ? false : nil }))
                Toggle("Video", isOn: Binding(get: { store.callFilter.video == true }, set: { store.callFilter.video = $0 ? true : nil }))
            }
            Section("Direction") {
                Toggle("Incoming", isOn: Binding(get: { store.callFilter.direction == .incoming }, set: { store.callFilter.direction = $0 ? .incoming : nil }))
                Toggle("Outgoing", isOn: Binding(get: { store.callFilter.direction == .outgoing }, set: { store.callFilter.direction = $0 ? .outgoing : nil }))
            }
            if store.callFilter.isOn {
                Button("Clear filters", role: .destructive) { store.callFilter = CallFilter() }
            }
        }
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

    @ViewBuilder
    private var empty: some View {
        if !log.records.isEmpty && store.callFilter.isOn {
            FilteredEmpty(text: "No calls match") { store.callFilter = CallFilter() }
        } else {
            emptyPlain
        }
    }

    private var emptyPlain: some View {
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
    /// My groups (not waiting in Requests, not ended), by name; the search narrows them like it does people.
    private var groupChats: [Conversation] {
        store.conversations.filter { $0.isGroup && !$0.isRequest && $0.groupEnded == nil && (typed.isEmpty || $0.title.localizedCaseInsensitiveContains(typed)) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

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
                                    .font(Theme.font(.subheadline, weight: .semibold)).foregroundStyle(Theme.textSecondary)
                                    .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 4)
                                    .id("section-\(section.letter)")
                                    .accessibilityAddTraits(.isHeader)
                                ForEach(section.teachers) { teacher in
                                    HStack(spacing: 8) {
                                        TeacherRow(person: teacher.person)
                                        CallMenuButton(name: teacher.person.name, id: "new-call-\(teacher.person.id)", voice: { call(teacher, video: false) }, video: { call(teacher, video: true) })
                                    }
                                    .padding(.trailing, 28)
                                }
                            }
                            if !groupChats.isEmpty {
                                Text("Groups")
                                    .font(Theme.font(.subheadline, weight: .semibold)).foregroundStyle(Theme.textSecondary)
                                    .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 4)
                                    .accessibilityAddTraits(.isHeader)
                                ForEach(groupChats) { group in
                                    HStack(spacing: 8) {
                                        Text(group.title).font(Theme.body).foregroundStyle(Theme.text).lineLimit(1)
                                            .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 20)
                                        CallMenuButton(name: group.title, id: "new-call-group-\(group.id)", voice: { callGroup(group, video: false) }, video: { callGroup(group, video: true) })
                                    }
                                    .frame(minHeight: 56)
                                    .padding(.trailing, 28)
                                }
                            }
                            if sections.isEmpty && groupChats.isEmpty {
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

    private func callGroup(_ group: Conversation, video: Bool) {
        dismiss()
        Task { _ = await store.groupCalls.start(conversationID: group.id, title: group.title, video: video) }
    }

    private func call(_ teacher: KnownTeacher, video: Bool) {
        dismiss()
        Task { _ = await store.calls.start(peerID: teacher.person.id, name: teacher.person.name, video: video) }
    }
}
