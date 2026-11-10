import SwiftUI

/// What VoiceOver reads for a jam card, and how a card becomes one stop (LIME-130-6a).
enum JamCardSpeech {
    /// "Mei Lin, Oct 22, Unread, Title, Subtitle, first words, Part 2 of the series X, Saved, 3 likes, 2 comments".
    static func label(author: String, time: String, unread: Bool, title: String, subtitle: String, text: String, series: String?,
                      saved: Bool, likes: Int, liked: Bool, comments: Int) -> String {
        var parts = [author, time]
        if unread { parts.append("Unread") }
        for words in [title, subtitle] where !words.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { parts.append(words) }
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !body.isEmpty, body != title { parts.append(String(body.prefix(160))) }
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
