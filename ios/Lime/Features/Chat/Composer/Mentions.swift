import SwiftUI

/// Someone "@" can offer (LIME-181): a person in the chat, or "@everyone" (a group's owner or admin).
struct MentionCandidate: Identifiable, Equatable {
    let id: String
    let name: String
    let detail: String?
    /// Their username, when this phone already knows it.
    var username: String? = nil
    /// For the avatar.
    var person: Person? = nil
    var isEveryone: Bool { id == MentionContext.everyone }

    /// The usernames this phone was told inside the encryption (LIME-184), by user id. Someone who hides from search shares none, so they have no entry
    /// and are found, and shown, by name alone.
    static func usernames(from people: [Person]) -> [String: String] {
        var result: [String: String] = [:]
        for person in people { if let handle = person.username, !handle.isEmpty { result[person.id] = handle } }
        return result
    }

    private static func fold(_ text: String) -> String { text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }

    /// The best matches for what was typed after the "@": people whose name (or private label) starts with it, or has a word that does, then
    /// those that contain it. An empty query offers everyone in order. At most `limit` (a group of 500 shows the best, not all).
    static func matches(for query: String, people: [Person], everyone: Bool, usernames: [String: String] = [:], limit: Int = 30) -> [MentionCandidate] {
        let wanted = Self.fold(query.trimmingCharacters(in: .whitespaces))
        var starts: [MentionCandidate] = []
        var contains: [MentionCandidate] = []
        for person in people {
            let handle = usernames[person.id]
            let candidate = MentionCandidate(id: person.id, name: person.name, detail: person.label, username: handle, person: person)
            if wanted.isEmpty { starts.append(candidate); continue }
            let name = Self.fold(person.name)
            let words = name.split(separator: " ").map(String.init)
            if name.hasPrefix(wanted) || words.contains(where: { $0.hasPrefix(wanted) }) || name.contains(" " + wanted) {
                starts.append(candidate)
            } else if handle.map({ Self.fold($0).hasPrefix(wanted) }) == true {
                starts.append(candidate)
            } else if name.contains(wanted) || Self.fold(person.label ?? "").contains(wanted) || handle.map({ Self.fold($0).contains(wanted) }) == true {
                contains.append(candidate)
            }
        }
        var result = Array((starts + contains).prefix(limit))
        if everyone, wanted.isEmpty || "everyone".hasPrefix(wanted) {
            result.insert(MentionCandidate(id: MentionContext.everyone, name: "everyone", detail: "Notify the group"), at: 0)
        }
        return result
    }
}

/// The list that floats above the composer while "@" is being typed: its own Liquid Glass panel over the messages (LIME-181c), not part of the
/// composer, which keeps its height. About five rows, then it scrolls; fewer when the window is short, so it never goes under the header.
struct MentionSuggestions: View {
    let matches: [MentionCandidate]
    /// The room there is above the composer's top (the window below the header), so a landscape window gets fewer rows.
    var room: CGFloat = .infinity
    let pick: (MentionCandidate) -> Void
    @ScaledMetric(relativeTo: .body) private var rowHeight: CGFloat = 52
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Kept after the list empties so it can fade out with its last rows.
    @State private var shown: [MentionCandidate] = []

    private var row: CGFloat { max(rowHeight, 44) }
    private var height: CGFloat { max(row, min(row * 5, room.isFinite ? room : row * 5)) }

    var body: some View {
        ZStack {
            if !shown.isEmpty { panel.transition(reduceMotion ? .identity : .opacity) }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: shown.isEmpty)
        .onChange(of: matches, initial: true) { _, now in shown = now }
        .padding(.horizontal, 12)
    }

    private var panel: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(shown) { candidate in
                    Button { pick(candidate) } label: {
                        HStack(spacing: 10) {
                            if let person = candidate.person {
                                AvatarView(person: person, size: 32)
                            } else {
                                Image(systemName: "person.3.fill").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
                                    .frame(width: 32, height: 32).background(Theme.pressed, in: Circle())
                            }
                            VStack(alignment: .leading, spacing: 1) {
                                Text(candidate.isEveryone ? "@everyone" : candidate.name).font(Theme.body).foregroundStyle(Theme.text).lineLimit(1)
                                if let second = candidate.isEveryone ? candidate.detail : candidate.username.map({ "@" + $0 }) {
                                    Text(second).font(Theme.secondary).foregroundStyle(Theme.textSecondary).lineLimit(1)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 6)
                        .frame(maxWidth: .infinity, minHeight: row, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(candidate.isEveryone ? "Everyone, notify the group" : candidate.username.map { "\(candidate.name), \($0)" } ?? candidate.name)
                    .accessibilityIdentifier("mention-suggestion-\(candidate.id)")
                }
            }
        }
        .frame(height: min(height, row * CGFloat(shown.count)))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .limeGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Suggestions, \(shown.count) \(shown.count == 1 ? "person" : "people")")
        .accessibilityIdentifier("mention-suggestions")
    }
}

extension ConversationStore {
    /// Who the mentions in a chat are, for drawing and tapping them.
    func mentionContext(for conversation: Conversation) -> MentionContext {
        let me = meProvider()
        let members = conversation.members
        let id = conversation.id
        return MentionContext(
            meID: me.id,
            name: { who in who == me.id ? me.name : members.first { $0.id == who }?.name },
            username: { who in members.first { $0.id == who }?.username },
            open: { [weak self] who in
                let name = who == me.id ? me.name : members.first { $0.id == who }?.name ?? ""
                self?.openProfile(ProfileRoute(userID: who, name: name, conversationID: id, isMe: who == me.id))
            })
    }
}

/// Tells a chat's composer who "@" can offer. A group's owner or admin also gets "@everyone".
struct ComposerMentionSource: ViewModifier {
    @Environment(ConversationStore.self) private var store
    let model: RichComposerModel
    let conversation: Conversation?

    func body(content: Content) -> some View {
        content
            .onChange(of: conversation?.members ?? [], initial: true) { _, members in model.mentionPeople = members }
            .onChange(of: conversation?.members ?? [], initial: true) { _, members in model.mentionUsernames = MentionCandidate.usernames(from: members) }
            .task(id: conversation?.id) {
                guard let conversation, conversation.isGroupChat else { model.mentionEveryone = false; return }
                let role = await store.groupDetails(conversation.id)?.myRole
                model.mentionEveryone = role == "owner" || role == "admin"
            }
    }
}

extension View {
    func composerMentions(_ model: RichComposerModel, in conversation: Conversation?) -> some View {
        modifier(ComposerMentionSource(model: model, conversation: conversation))
    }
}

/// The @ list as its own floating glass panel over the messages, about 8 pt above the composer (LIME-181c). It is placed by the chat, not inside the
/// composer, so the composer keeps its height and the panel's rows can be tapped.
struct MentionPanelOverlay: ViewModifier {
    let model: RichComposerModel

    func body(content: Content) -> some View {
        content.overlay {
            GeometryReader { proxy in
                let bottom = proxy.frame(in: .global).maxY
                let gap = max(0, bottom - model.composerTop + 8)
                // Between the header and the composer: a short (landscape) window gets fewer rows and never goes under the header.
                let room = model.composerTop - 8 - (model.topInset + ComposerSizing.headerHeight)
                MentionSuggestions(matches: model.mentionMatches, room: room) { model.pick($0) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, gap)
            }
        }
    }
}

extension View {
    func mentionPanel(_ model: RichComposerModel) -> some View { modifier(MentionPanelOverlay(model: model)) }
}
