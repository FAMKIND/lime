import SwiftUI

/// Settings → Storage (LIME-107): what Lime keeps on this iPhone, how long, and what it downloads by itself.
struct StorageScreen: View {
    @Environment(ConversationStore.self) private var store
    @State private var summary = ConversationStore.StorageSummary()
    @State private var loaded = false
    @AppStorage(MediaSettings.keepKey) private var keep = KeepMedia.forever.rawValue
    @AppStorage(MediaSettings.photosKey) private var photos = AutoDownload.wifiAndMobile.rawValue
    @AppStorage(MediaSettings.videoFilesKey) private var videoFiles = AutoDownload.wifiOnly.rawValue

    var body: some View {
        SettingsPage(title: "Storage") {
            SettingsCard {
                valueRow("Lime on this iPhone", ByteCountFormatter.string(fromByteCount: summary.databaseBytes, countStyle: .file), id: "storage-total")
                valueRow("Photos, videos and files", ByteCountFormatter.string(fromByteCount: summary.mediaBytes, countStyle: .file), id: "storage-media", last: true)
            }
            SettingsFootnote(text: "Photos, videos and files you receive are kept on this iPhone, encrypted. Lime's servers delete their copy about an hour after everyone has downloaded it, so this iPhone may hold the only copy. They are not backed up to iCloud.")
            if StorageGuard.shared.isLow {
                SettingsFootnote(text: "Your iPhone is almost full. Lime paused downloads.").accessibilityIdentifier("storage-low")
            }

            SettingsFootnote(text: "Keep media")
            SettingsCard {
                ForEach(KeepMedia.allCases) { option in
                    choice(option.title, selected: keep == option.rawValue, id: "keep-\(option.rawValue)", last: option == KeepMedia.allCases.last) {
                        keep = option.rawValue
                        Task { await store.applyKeepMedia(); summary = await store.storageSummary() }
                    }
                }
            }
            SettingsFootnote(text: "Older photos, videos and files are removed from this iPhone. The messages stay, marked “Media removed”.")

            SettingsFootnote(text: "Download photos automatically")
            SettingsCard {
                ForEach(AutoDownload.allCases) { option in
                    choice(option.title, selected: photos == option.rawValue, id: "auto-photos-\(option.rawValue)", last: option == AutoDownload.allCases.last) { photos = option.rawValue }
                }
            }
            SettingsFootnote(text: "Download videos and files automatically")
            SettingsCard {
                ForEach(AutoDownload.allCases) { option in
                    choice(option.title, selected: videoFiles == option.rawValue, id: "auto-videofiles-\(option.rawValue)", last: option == AutoDownload.allCases.last) { videoFiles = option.rawValue }
                }
            }
            SettingsFootnote(text: "Voice messages always download. What is not downloaded shows its size and how long it stays available; tap it to download.")

            SettingsFootnote(text: "By chat")
            SettingsCard {
                if summary.chats.isEmpty {
                    Text(loaded ? "No media on this iPhone." : " ").font(Theme.body).foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 18).frame(minHeight: 54)
                        .accessibilityIdentifier("storage-empty")
                }
                ForEach(summary.chats) { chat in
                    NavigationLink(value: SettingsRoute.chatMedia(chat.id)) {
                        HStack {
                            Text(chat.title).font(Theme.body).foregroundStyle(Theme.text).lineLimit(1)
                            Spacer(minLength: 8)
                            Text(ByteCountFormatter.string(fromByteCount: chat.bytes, countStyle: .file)).font(Theme.body).foregroundStyle(Theme.textSecondary)
                        }
                        .padding(.horizontal, 18).frame(minHeight: 54)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("storage-chat-\(chat.id)")
                }
            }
        }
        .task { summary = await store.storageSummary(); loaded = true }
        .accessibilityIdentifier("storage-screen")
    }

    private func valueRow(_ title: String, _ value: String, id: String, last: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(Theme.body).foregroundStyle(Theme.text)
                Spacer()
                Text(value).font(Theme.body).foregroundStyle(Theme.textSecondary).accessibilityIdentifier(id)
            }
            .padding(.horizontal, 18).frame(minHeight: 54)
        }
    }

    private func choice(_ title: String, selected: Bool, id: String, last: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).font(Theme.body).foregroundStyle(Theme.text)
                Spacer()
                if selected { Image(systemName: "checkmark").font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.text) }
            }
            .padding(.horizontal, 18).frame(minHeight: 54)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

/// One chat's media on this iPhone, largest first: pick some and remove them (the messages stay).
struct ChatMediaScreen: View {
    let conversationID: Conversation.ID
    @Environment(ConversationStore.self) private var store
    @State private var files: [ConversationStore.MediaFile] = []
    @State private var selected: Set<String> = []
    @State private var confirming = false
    @State private var loaded = false

    private var title: String { store.conversation(conversationID)?.title ?? "Media" }

    var body: some View {
        SettingsPage(title: title) {
            if files.isEmpty {
                Text(loaded ? "No media on this iPhone." : " ").font(Theme.body).foregroundStyle(Theme.textSecondary).padding(.top, 40)
                    .accessibilityIdentifier("chat-media-empty")
            } else {
                SettingsCard {
                    ForEach(files) { file in
                        Button { toggle(file.id) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: selected.contains(file.id) ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 24)).foregroundStyle(selected.contains(file.id) ? Theme.text : Theme.textSecondary.opacity(0.7))
                                Image(systemName: symbol(file.mime)).font(.system(size: 20)).frame(width: 28).foregroundStyle(Theme.text)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(file.name).font(Theme.body).foregroundStyle(Theme.text).lineLimit(1).truncationMode(.middle)
                                    Text(file.date.formatted(.dateTime.month(.abbreviated).day().year())).font(Theme.caption).foregroundStyle(Theme.textSecondary)
                                }
                                Spacer(minLength: 8)
                                Text(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file)).font(Theme.secondary).foregroundStyle(Theme.textSecondary)
                            }
                            .padding(.horizontal, 18).frame(minHeight: 58)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(selected.contains(file.id) ? [.isSelected] : [])
                        .accessibilityIdentifier("media-row-\(file.attachmentID)")
                    }
                }
                HStack(spacing: 12) {
                    Button(selected.count == files.count ? "Select none" : "Select all") {
                        selected = selected.count == files.count ? [] : Set(files.map(\.id))
                    }
                    .font(Theme.secondary.weight(.semibold)).foregroundStyle(Theme.text)
                    .accessibilityIdentifier("media-select-all")
                    Spacer()
                    Button(role: .destructive) { confirming = true } label: {
                        Text(selected.isEmpty ? "Delete" : "Delete \(selected.count)").font(Theme.secondary.weight(.semibold))
                    }
                    .disabled(selected.isEmpty)
                    .accessibilityIdentifier("media-delete")
                }
                .padding(.horizontal, 12)
                SettingsFootnote(text: "Removed from this iPhone only. The messages stay and say “Media removed”. If the other person still has it, they keep it.")
            }
        }
        .task { await load() }
        .confirmationDialog("Remove \(selected.count) \(selected.count == 1 ? "file" : "files") from this iPhone?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Remove from this iPhone", role: .destructive) {
                let chosen = files.filter { selected.contains($0.id) }
                Task { await store.removeMedia(chosen); selected = []; await load() }
            }
            .accessibilityIdentifier("media-delete-confirm")
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The messages stay. You can't download these again.")
        }
        .accessibilityIdentifier("chat-media-screen")
    }

    private func load() async { files = await store.mediaFiles(in: conversationID); loaded = true }
    private func toggle(_ id: String) { if selected.contains(id) { selected.remove(id) } else { selected.insert(id) } }
    private func symbol(_ mime: String) -> String {
        if mime.hasPrefix("image/") { return "photo" }
        if mime.hasPrefix("video/") { return "video" }
        if mime.hasPrefix("audio/") { return "mic" }
        return "doc"
    }
}
