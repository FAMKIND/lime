import SwiftUI

/// What VoiceOver reads for the things shared in a chat, in the profile and in group details (LIME-130-5a). Pure, so a test pins the wording.
enum SharedItemLabel {
    /// "Photo from Mei Lin, Nov 9, 2026" / "Video, 0:12, from you, Nov 9, 2026", then the photo's description when there is one.
    static func media(video: Bool, sender: String?, dateText: String, durationMs: Int?, alt: String) -> String {
        var parts = [video ? "Video" : "Photo"]
        if video, let durationMs, durationMs > 0 { parts.append(clock(durationMs)) }
        parts.append("from \(sender ?? "you")")
        parts.append(dateText)
        // "Photo from X, date" (no comma after "Photo"); "Video, 0:12, from X, date".
        let head = video ? parts.joined(separator: ", ") : "\(parts[0]) \(parts.dropFirst().joined(separator: ", "))"
        let description = alt.trimmingCharacters(in: .whitespacesAndNewlines)
        return description.isEmpty ? head : "\(head). \(description)"
    }

    static func file(name: String, size: Int64?, dateText: String) -> String {
        [name, size.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }, dateText].compactMap { $0 }.joined(separator: ", ")
    }

    static func link(title: String, host: String?, dateText: String) -> String {
        [title, host.flatMap { $0.isEmpty || $0 == title ? nil : $0 }, dateText].compactMap { $0 }.joined(separator: ", ")
    }

    static func host(of url: String) -> String? { URL(string: url)?.host }

    private static func clock(_ ms: Int) -> String {
        let seconds = ms / 1000
        return "\(seconds / 60):" + String(format: "%02d", seconds % 60)
    }
}

/// A picture or video in a shared-media grid, as a real button that says who sent it and when.
struct SharedMediaButton: View {
    @Environment(ConversationStore.self) private var store
    let message: Message
    let item: AttachmentItem
    let conversationID: String
    let open: () -> Void

    private var label: String {
        let sender = store.conversation(conversationID).flatMap { store.person(message.senderID, in: $0) }
        return SharedItemLabel.media(video: item.kind == .video, sender: message.isOwn ? nil : sender?.name,
                                     dateText: message.date.formatted(date: .abbreviated, time: .omitted), durationMs: item.durationMs, alt: item.alt)
    }

    var body: some View {
        Button(action: open) { MediaCell(item: item) }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isImage)
    }
}
