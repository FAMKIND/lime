import SwiftUI

/// Someone "@" can offer (LIME-181): a person in the chat, or "@everyone" (a group's owner or admin).
struct MentionCandidate: Identifiable, Equatable {
    let id: String
    let name: String
    let detail: String?
    var isEveryone: Bool { id == MentionContext.everyone }

    private static func fold(_ text: String) -> String { text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }

    /// The best matches for what was typed after the "@": people whose name (or private label) starts with it, or has a word that does, then
    /// those that contain it. An empty query offers everyone in order. At most `limit` (a group of 500 shows the best, not all).
    static func matches(for query: String, people: [Person], everyone: Bool, limit: Int = 30) -> [MentionCandidate] {
        let wanted = Self.fold(query.trimmingCharacters(in: .whitespaces))
        var starts: [MentionCandidate] = []
        var contains: [MentionCandidate] = []
        for person in people {
            let candidate = MentionCandidate(id: person.id, name: person.name, detail: person.label)
            if wanted.isEmpty { starts.append(candidate); continue }
            let name = Self.fold(person.name)
            let words = name.split(separator: " ").map(String.init)
            if name.hasPrefix(wanted) || words.contains(where: { $0.hasPrefix(wanted) }) || name.contains(" " + wanted) {
                starts.append(candidate)
            } else if name.contains(wanted) || Self.fold(person.label ?? "").contains(wanted) {
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

/// The list above the composer while "@" is being typed.
struct MentionSuggestions: View {
    let matches: [MentionCandidate]
    let pick: (MentionCandidate) -> Void
    @ScaledMetric(relativeTo: .body) private var rowHeight: CGFloat = 48

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(matches) { candidate in
                    Button { pick(candidate) } label: {
                        HStack(spacing: 8) {
                            Text(candidate.isEveryone ? "@everyone" : candidate.name).font(Theme.body).foregroundStyle(Theme.text).lineLimit(1)
                            if let detail = candidate.detail {
                                Text("· " + detail).font(Theme.secondary).foregroundStyle(Theme.textSecondary).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 14)
                        .frame(maxWidth: .infinity, minHeight: max(rowHeight, 44), alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(candidate.isEveryone ? "Everyone, notify the group" : candidate.name)
                    .accessibilityIdentifier("mention-suggestion-\(candidate.id)")
                }
            }
        }
        // About eight rows, then it scrolls.
        .frame(maxHeight: max(rowHeight, 44) * 8)
        .fixedSize(horizontal: false, vertical: true)
        .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.bubbleEdge, lineWidth: 0.5))
        .padding(.horizontal, 4).padding(.bottom, 6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Suggestions, \(matches.count) \(matches.count == 1 ? "person" : "people")")
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
