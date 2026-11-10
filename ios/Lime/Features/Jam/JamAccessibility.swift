import SwiftUI

/// What VoiceOver reads for a jam card, and how a card becomes one stop (LIME-130-6a).
enum JamCardSpeech {
    /// "Mei Lin, Oct 22, Unread, Title, Subtitle, first words, Part 2 of the series X, Saved, 3 likes, 2 comments".
    static func label(author: String, time: String, unread: Bool, title: String, subtitle: String, text: String, series: String?,
                      saved: Bool, likes: Int, liked: Bool, comments: Int, coverAlt: String = "") -> String {
        var parts = [author, time]
        if unread { parts.append("Unread") }
        for words in [title, subtitle] where !words.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { parts.append(words) }
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !body.isEmpty, body != title { parts.append(String(body.prefix(160))) }
        let cover = coverAlt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cover.isEmpty { parts.append("Cover: \(cover)") }
        if let series { parts.append(series) }
        if saved { parts.append("Saved") }
        if likes > 0 { parts.append("\(likes) \(likes == 1 ? "like" : "likes")\(liked ? ", you liked it" : "")") } else if liked { parts.append("You liked it") }
        if comments > 0 { parts.append("\(comments) \(comments == 1 ? "comment" : "comments")") }
        return parts.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    static func likeAction(liked: Bool) -> String { liked ? "Unlike" : "Like" }
    static func saveAction(saved: Bool) -> String { saved ? "Unsave" : "Save" }
}

/// With VoiceOver or Switch Control running, a card is **one stop** (the byline once, the words, the counts) with Open as its action and Like, Comment,
/// Save, Open author and Open series as named actions. Touch is unchanged: the buttons stay (UI tests tap them). The ⋯ menu stays its own stop, because
/// a menu cannot be opened from an action.
struct JamCardStop: ViewModifier {
    let active: Bool
    let label: String
    let hint: String
    let open: () -> Void
    let like: (_ liked: Bool) -> Void
    let liked: Bool
    let comment: () -> Void
    let save: (_ saved: Bool) -> Void
    let saved: Bool
    let author: () -> Void
    let series: (() -> Void)?

    func body(content: Content) -> some View {
        if active {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(label)
                .accessibilityHint(hint)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction(.default) { open() }
                .accessibilityAction(named: JamCardSpeech.likeAction(liked: liked)) { like(liked) }
                .accessibilityAction(named: "Comment") { comment() }
                .accessibilityAction(named: JamCardSpeech.saveAction(saved: saved)) { save(saved) }
                .accessibilityAction(named: "Open author") { author() }
                .accessibilityAction(named: "Open series") { series?() }
        } else { content }
    }
}

extension View {
    /// White text over a cover photo or its tint (WCAG 1.4.3): a black scrim at 0.6 under it, so it stays at 4.5:1 or better on a white picture
    /// (white on 60% black over white is #666: 5.7:1). The same scrim the call text uses.
    func coverTextScrim() -> some View {
        padding(.horizontal, 10).padding(.vertical, 4)
            .background(.black.opacity(CallScrim.text), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// What VoiceOver calls a post's picture (LIME-130-6b): the writer's description, else "Photo": never the file name. "2 of 5" is its value.
enum JamPhotoLabel {
    static func label(alt: String) -> String {
        let words = alt.trimmingCharacters(in: .whitespacesAndNewlines)
        return words.isEmpty ? "Photo" : words
    }
    static func value(index: Int, count: Int) -> String { count > 1 ? "\(index + 1) of \(count)" : "" }
}

/// What a picture being described is, in the composer (LIME-130-6b).
enum DescribeTarget: Identifiable, Equatable {
    case photo(Int), articleFile(Int), cover
    var id: String { switch self { case .photo(let i): "photo-\(i)"; case .articleFile(let i): "file-\(i)"; case .cover: "cover" } }
}

/// The "+ Alt" / "Alt" pill on a picture (the same words as the chat composer's): 44 pt, with a spoken name that says what it describes.
struct AltPill: View {
    let described: Bool
    let what: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(described ? "Alt" : "+ Alt").font(Theme.font(.caption, weight: .bold)).foregroundStyle(Theme.text)
                .padding(.horizontal, 10).frame(minHeight: 28).background(Theme.surface, in: Capsule()).overlay(Capsule().strokeBorder(Theme.hairline))
                .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(described ? "Edit description of \(what)" : "Add description to \(what)")
        .accessibilityIdentifier("alt-pill")
    }
}

/// "Read the transcript" under a recording or video whose writer published one (LIME-130-6b): 44 pt, and an action on the card's own element.
struct ReadTranscriptButton: View {
    let text: String
    @State private var open = false
    var body: some View {
        if !text.isEmpty {
            Button { open = true } label: {
                Label("Read the transcript", systemImage: "text.alignleft").font(Theme.secondary).foregroundStyle(Theme.text)
                    .padding(.horizontal, 14).frame(minHeight: 44).background(Theme.surface, in: Capsule())
            }
            .buttonStyle(.plain).accessibilityIdentifier("jam-read-transcript")
            .sheet(isPresented: $open) { TranscriptSheet(cues: [], writerText: text) }
        }
    }
}

/// The writer types or pastes a transcript for a recording or video (LIME-130-6b): at most 100,000 characters, shown to everyone who reads the post.
struct TranscriptEditSheet: View {
    let save: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @FocusState private var focused: Bool
    nonisolated static let limit = 100_000

    init(text: String, save: @escaping (String) -> Void) { self.save = save; _text = State(initialValue: text) }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 10) {
                TextEditor(text: $text).font(Theme.body).focused($focused).scrollContentBackground(.hidden)
                    .padding(10).background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .frame(minHeight: 220)
                    .onChange(of: text) { _, new in if new.count > Self.limit { text = String(new.prefix(Self.limit)) } }
                    .accessibilityLabel("Transcript").accessibilityIdentifier("transcript-field")
                HStack {
                    Text("Shown to everyone who reads the post, end-to-end encrypted like the rest of it.").font(Theme.caption).foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Text("\(text.count)/\(Self.limit)").font(Theme.caption.monospacedDigit()).foregroundStyle(Theme.textSecondary)
                        .accessibilityLabel("\(text.count) of \(Self.limit) characters")
                }
            }
            .padding(16)
            .background(Theme.canvas)
            .sheetHeader("Transcript")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Save") { save(text.trimmingCharacters(in: .whitespacesAndNewlines)); dismiss() }.font(Theme.font(.body, weight: .semibold)).accessibilityIdentifier("transcript-save") } }
        }
        .presentationDetents([.large])
        .onAppear { focused = true }
    }
}
