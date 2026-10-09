import SwiftUI

/// Search from Messages: one field, then Chats (name or title matches) and Messages (the words in
/// context, matched words in bold). It runs on this iPhone only; the screen says so. Tapping a message
/// opens its chat scrolled to it.
struct MessageSearchScreen: View {
    @Environment(ConversationStore.self) private var store
    @Environment(\.dismiss) private var dismiss
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
        HStack(spacing: 8) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left").font(.system(size: 18, weight: .medium)).foregroundStyle(Theme.text)
                    .frame(width: 48, height: 48).limeGlass()
            }
            .accessibilityLabel("Back").accessibilityIdentifier("search-back")
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.textSecondary)
                TextField("Search chats and messages", text: $query)
                    .font(Theme.body)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .focused($focused)
                    .selectionTint()
                    .accessibilityIdentifier("search-field")
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

    @ViewBuilder
    private var content: some View {
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "lock.shield").font(.system(size: 28)).foregroundStyle(Theme.textSecondary)
                Text("Search your chats and messages.").font(Theme.body).foregroundStyle(Theme.text)
                Text("Search happens on this iPhone only. Nothing you type is sent anywhere.")
                    .font(Theme.secondary).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity).padding(.top, 60).padding(.horizontal, 24)
            .accessibilityIdentifier("search-hint")
        } else if results.isEmpty && searched == query {
            Text("No results for “\(query.trimmingCharacters(in: .whitespaces))”")
                .font(Theme.body).foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity).padding(.top, 60)
                .accessibilityIdentifier("search-none")
        } else {
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
        }
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
        Text(text).font(Theme.secondary.weight(.semibold)).foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 8).padding(.top, 14).padding(.bottom, 2)
            .accessibilityAddTraits(.isHeader)
    }
}
