import AVKit
import SwiftUI

/// Reading one post (LIME-188): the title, who wrote it, the date, the body drawn the way chats draw Markdown, and its photos, videos and files.
/// (Replying to the writer comes with LIME-189.)
struct JamPostView: View {
    let postID: String
    @Environment(ConversationStore.self) private var store

    var body: some View {
        let post = store.jamPost(postID)
        ScrollView {
            if let post {
                let writer = store.teacher(post.author)
                VStack(alignment: .leading, spacing: 14) {
                    Text(post.title).font(Theme.font(.title2, weight: .bold)).foregroundStyle(Theme.text)
                        .accessibilityAddTraits(.isHeader).accessibilityIdentifier("jam-reader-title")
                    Button { store.openProfile(ProfileRoute(userID: writer.id, name: writer.name, isMe: writer.id == store.meProvider().id)) } label: {
                        HStack(spacing: 10) {
                            AvatarView(person: writer, size: 36).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(writer.name).font(Theme.font(.subheadline, weight: .semibold)).foregroundStyle(Theme.text)
                                Text(JamDates.text(post.created)).font(Theme.caption).foregroundStyle(Theme.textSecondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).accessibilityLabel("\(writer.name), \(JamDates.text(post.created))").accessibilityHint("Opens their profile")
                    switch post.state {
                    case "fetching":
                        Text("Downloading\u{2026}").font(Theme.body).foregroundStyle(Theme.textSecondary).accessibilityIdentifier("jam-reader-fetching")
                    case "gone":
                        Text("This post is no longer available.").font(Theme.body).foregroundStyle(Theme.textSecondary)
                    default:
                        if !post.markdown.isEmpty {
                            FormattedMessageText(markdown: post.markdown, ink: Theme.text, link: Theme.linkOther)
                                .accessibilityIdentifier("jam-reader-body")
                        }
                        JamAttachmentsView(postID: post.postId)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Theme.canvas)
        .linkOpening()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .accessibilityIdentifier("jam-reader")
        .onAppear { store.refreshJams() }
    }
}

/// A post's photos (inline), videos (poster, then a player) and files (a card to open or share). Each downloads when it is shown, with no session.
struct JamAttachmentsView: View {
    let postID: String
    @Environment(ConversationStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(store.jamAttachments(postID), id: \.attachmentId) { file in
                switch file.kind {
                case "image": JamPhoto(postID: postID, file: file)
                case "video": JamVideo(postID: postID, file: file)
                default: JamFileCard(postID: postID, file: file)
                }
            }
        }
    }
}

private struct JamPhoto: View {
    let postID: String
    let file: JamAttachmentInfo
    @Environment(ConversationStore.self) private var store
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityLabel(file.name.isEmpty ? "Photo" : "Photo, \(file.name)")
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.surface)
                    .aspectRatio(file.width.flatMap { w in file.height.map { CGFloat(w) / CGFloat(max($0, 1)) } } ?? 1.5, contentMode: .fit)
                    .overlay { if failed { Text("Photo not available").font(Theme.caption).foregroundStyle(Theme.textSecondary) } else { ProgressView() } }
            }
        }
        .accessibilityIdentifier("jam-photo")
        .task {
            if let data = await store.jamAttachmentData(postID, file.attachmentId), let picture = UIImage(data: data) { image = picture } else { failed = true }
        }
    }
}

private struct JamVideo: View {
    let postID: String
    let file: JamAttachmentInfo
    @Environment(ConversationStore.self) private var store
    @State private var player: AVPlayer?
    @State private var loading = false

    var body: some View {
        ZStack {
            if let player {
                VideoPlayer(player: player).aspectRatio(file.width.flatMap { w in file.height.map { CGFloat(w) / CGFloat(max($0, 1)) } } ?? 16.0 / 9, contentMode: .fit)
            } else {
                Button { load() } label: {
                    ZStack {
                        if let poster = UIImage(data: file.poster) { Image(uiImage: poster).resizable().scaledToFit() } else { Rectangle().fill(Theme.surface).aspectRatio(16.0 / 9, contentMode: .fit) }
                        if loading { ProgressView() } else { Image(systemName: "play.circle.fill").font(.system(size: 52)).foregroundStyle(.white).shadow(radius: 4) }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain).accessibilityLabel("Play video").accessibilityIdentifier("jam-video")
            }
        }
    }

    private func load() {
        loading = true
        Task {
            if let data = await store.jamAttachmentData(postID, file.attachmentId) {
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("jam-\(file.attachmentId).mp4")
                try? data.write(to: url)
                player = AVPlayer(url: url)
                player?.play()
            }
            loading = false
        }
    }
}

private struct JamFileCard: View {
    let postID: String
    let file: JamAttachmentInfo
    @Environment(ConversationStore.self) private var store
    @State private var shared: URL?

    var body: some View {
        Button { open() } label: {
            HStack(spacing: 12) {
                Image(systemName: "doc").font(.system(size: 24)).foregroundStyle(Theme.text).frame(width: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.name.isEmpty ? "File" : file.name).font(Theme.font(.body, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(2)
                    Text(ByteCountFormatter.string(fromByteCount: Int64(file.size), countStyle: .file)).font(Theme.caption).foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(14).background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(file.name.isEmpty ? "File" : file.name), \(ByteCountFormatter.string(fromByteCount: Int64(file.size), countStyle: .file))")
        .accessibilityHint("Opens the file").accessibilityIdentifier("jam-file")
        .sheet(item: Binding(get: { shared.map(SharedFile.init) }, set: { shared = $0?.url })) { ActivitySheet(url: $0.url) }
    }

    private func open() {
        Task {
            guard let data = await store.jamAttachmentData(postID, file.attachmentId) else { return }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(file.name.isEmpty ? "file-\(file.attachmentId)" : file.name)
            try? data.write(to: url)
            shared = url
        }
    }
}

private struct SharedFile: Identifiable { let url: URL; var id: URL { url } }

private struct ActivitySheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: [url], applicationActivities: nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// The writer's list of who follows (shown to nobody else), with a way to remove someone.
struct JamSubscribersView: View {
    let jamID: String
    @Environment(ConversationStore.self) private var store
    @State private var removing: JamSubscriberInfo?

    var body: some View {
        let people = (store.jamSubscribers[jamID] ?? []).filter { $0.status == "active" }
        List {
            if people.isEmpty {
                Text("No one yet. Teachers subscribe from your profile.").font(Theme.body).foregroundStyle(Theme.textSecondary)
                    .listRowBackground(Theme.canvas).accessibilityIdentifier("jam-subscribers-empty")
            }
            ForEach(people, id: \.userId) { person in
                HStack(spacing: 12) {
                    AvatarView(person: store.teacher(person.userId), size: 40).accessibilityHidden(true)
                    Text(person.name == person.userId ? store.teacherName(person.userId) : person.name).font(Theme.body).foregroundStyle(Theme.text)
                    Spacer()
                    Button("Remove") { removing = person }.font(Theme.secondary).foregroundStyle(.red).frame(minHeight: 44)
                        .accessibilityLabel("Remove \(person.name)").accessibilityIdentifier("jam-remove-\(person.userId)")
                }
                .listRowBackground(Theme.canvas)
            }
        }
        .listStyle(.plain)
        .background(Theme.canvas)
        .navigationTitle("Subscribers")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .onAppear { store.loadJamSubscribers(jamID) }
        .confirmSheet("Remove \(removing?.name ?? "this teacher")?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            if let removing {
                Button("Remove", role: .destructive) { Task { await store.removeJamSubscriber(jamID, user: removing.userId) } }.accessibilityIdentifier("jam-remove-confirm")
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("They keep what they have and will not get new posts.")
        }
    }
}

/// On a teacher's profile: their jam, if they have one, with Subscribe (LIME-188). The server learns that this account looked at that page, as it
/// does for a profile.
struct JamProfileRow: View {
    let userID: String
    let isMe: Bool
    @Environment(ConversationStore.self) private var store
    @State private var page: JamPageInfo?

    var body: some View {
        ZStack {
            // Something always in the tree, so the lookup below runs even while there is nothing to show.
            Color.clear.frame(height: 0).accessibilityHidden(true)
            if let page {
                let following = store.isFollowing(page.jamId)
                SettingsCard {
                    HStack(spacing: 12) {
                        Image(systemName: "book.pages").font(.system(size: 20)).foregroundStyle(Theme.text).frame(width: 28).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(page.title).font(Theme.font(.body, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(2).accessibilityIdentifier("profile-jam-row")
                            Text("jam").font(Theme.caption).foregroundStyle(Theme.textSecondary)
                        }
                        Spacer(minLength: 8)
                        if !isMe {
                            Button { Task { if following { await store.unsubscribe(page.jamId) } else { await store.subscribe(to: page) } } } label: {
                                Text(following ? "Subscribed \u{2713}" : "Subscribe").font(Theme.font(.subheadline, weight: .semibold))
                                    .foregroundStyle(following ? Theme.text : Theme.accentInk)
                                    .padding(.horizontal, 14).frame(minHeight: 44)
                                    .background(following ? Theme.surface : Theme.accent, in: Capsule())
                            }
                            .buttonStyle(.plain).accessibilityIdentifier("profile-jam-subscribe")
                            .accessibilityLabel(following ? "Subscribed. Tap to unsubscribe." : "Subscribe to \(page.title)")
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 8)
                }
            }
        }
        .task(id: userID) {
            if isMe { page = store.jamsMine.first.map { JamPageInfo(jamId: $0.jamId, writerId: $0.writer, title: $0.title, about: $0.about, topics: $0.topics, postCount: $0.postCount) } }
            else { page = await store.jamPage(of: userID) }
        }
    }
}
