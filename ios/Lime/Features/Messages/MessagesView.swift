import SwiftUI

struct MessagesView: View {
    @Environment(ConversationStore.self) private var store

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(store.conversations) { conversation in
                        NavigationLink(value: conversation.id) {
                            ConversationRow(conversation: conversation)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("conversation-row-\(conversation.id)")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 76)
                .padding(.bottom, 170)
            }
            .accessibilityIdentifier("messages-list")
        }
        .overlay(alignment: .top) { TopControls() }
        .overlay(alignment: .bottomTrailing) {
            Button { store.comingSoon("New message") } label: {
                Image(systemName: "plus")
                    .font(.system(size: 26, weight: .regular))
                    .foregroundStyle(Theme.primaryInk)
                    .frame(width: 64, height: 64)
                    .background(Theme.primary, in: Circle())
                    .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
            }
            .accessibilityLabel("New message")
            .padding(.trailing, 20)
            .padding(.bottom, 92)
        }
        .overlay(alignment: .bottom) { DockBar().padding(.bottom, 8) }
        .toolbar(.hidden, for: .navigationBar)
    }
}

private struct TopControls: View {
    @Environment(ConversationStore.self) private var store

    var body: some View {
        HStack {
            Button { store.comingSoon() } label: {
                Image("LimeLogo")
                    .resizable().scaledToFit()
                    .frame(width: 34, height: 34)
                    .frame(width: 48, height: 48)
                    .limeGlass()
            }
            .accessibilityLabel("Lime menu")
            Spacer()
            HStack(spacing: 12) {
                Button { store.comingSoon("Search") } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(Theme.text)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Search")
                Button { store.comingSoon("Your profile") } label: {
                    AvatarView(person: SampleData.me, size: 36)
                }
                .accessibilityLabel("Your profile")
            }
            .padding(.horizontal, 8).padding(.vertical, 2)
            .limeGlass()
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }
}

struct ConversationRow: View {
    let conversation: Conversation
    @ScaledMetric(relativeTo: .body) private var avatarSize: CGFloat = 52

    private var preview: String {
        guard let last = conversation.lastMessage else { return "" }
        if conversation.isGroup, let sender = conversation.members.first(where: { $0.id == last.senderID }) {
            return "\(sender.name.split(separator: " ").first ?? ""): \(last.text)"
        }
        return last.text
    }

    private var time: String { MessageFormat.listTime(conversation.lastMessage?.date) }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ConversationAvatar(conversation: conversation, size: avatarSize)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(conversation.title)
                        .font(Theme.title)
                        .foregroundStyle(Theme.text)
                        .lineLimit(2)
                    if conversation.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .accessibilityHidden(true)
                    }
                    Spacer(minLength: 4)
                    Text(time)
                        .font(Theme.secondary)
                        .foregroundStyle(Theme.textSecondary)
                }
                HStack(alignment: .top, spacing: 8) {
                    Text(preview)
                        .font(Theme.secondary)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if conversation.unread > 0 {
                        Text("\(conversation.unread)")
                            .font(Theme.caption.weight(.semibold))
                            .foregroundStyle(Theme.primaryInk)
                            .frame(minWidth: 22)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Theme.primary, in: Capsule())
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(conversation.title)\(conversation.isPinned ? ", pinned" : ""), \(preview), \(time)\(conversation.unread > 0 ? ", \(conversation.unread) unread" : "")")
        .accessibilityAddTraits(.isButton)
    }
}
