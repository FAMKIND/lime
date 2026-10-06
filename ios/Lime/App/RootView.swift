import SwiftUI

struct RootView: View {
    @Environment(ConversationStore.self) private var store

    var body: some View {
        NavigationStack {
            MessagesView()
                .navigationDestination(for: Conversation.ID.self) { id in
                    ChatView(conversationID: id)
                }
        }
        .tint(Theme.text)
        .overlay(alignment: .top) { ComingSoonBanner() }
    }
}

struct ComingSoonBanner: View {
    @Environment(ConversationStore.self) private var store

    var body: some View {
        if let text = store.banner {
            Text(text)
                .font(Theme.secondary.weight(.medium))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .limeGlass()
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .accessibilityIdentifier("coming-soon-banner")
                .accessibilityAddTraits(.updatesFrequently)
        }
    }
}
