import SwiftUI

/// In-memory state for the skeleton. Nothing is persisted or sent anywhere.
@MainActor
@Observable
final class ConversationStore {
    var conversations: [Conversation]
    var banner: String?
    private var bannerTask: Task<Void, Never>?

    init(conversations: [Conversation] = SampleData.conversations()) {
        self.conversations = conversations
    }

    func conversation(_ id: Conversation.ID) -> Conversation? {
        conversations.first { $0.id == id }
    }

    func person(_ id: String?, in conversation: Conversation) -> Person? {
        guard let id else { return SampleData.me }
        return conversation.members.first { $0.id == id }
    }

    func send(_ text: String, in id: Conversation.ID) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let i = conversations.firstIndex(where: { $0.id == id }) else { return }
        let message = Message(id: UUID().uuidString, senderID: nil, text: trimmed, date: Date())
        conversations[i].messages.append(message)
    }

    func comingSoon(_ what: String = "This") {
        banner = "\(what) is coming soon"
        bannerTask?.cancel()
        bannerTask = Task {
            try? await Task.sleep(for: .seconds(2))
            if !Task.isCancelled { banner = nil }
        }
    }
}
