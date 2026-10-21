import AVFoundation
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
                    if !post.title.isEmpty {
                        Text(post.title).font(Theme.font(.title2, weight: .bold)).foregroundStyle(Theme.text)
                            .accessibilityAddTraits(.isHeader).accessibilityIdentifier("jam-reader-title")
                    }
                    if !post.subtitle.isEmpty {
                        Text(post.subtitle).font(Theme.font(.title3)).foregroundStyle(Theme.textSecondary).accessibilityIdentifier("jam-reader-subtitle")
                    }
                    Button { store.openProfile(ProfileRoute(userID: writer.id, name: writer.name, isMe: writer.id == store.meProvider().id)) } label: {
                        HStack(spacing: 10) {
                            AvatarView(person: writer, size: 36).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(writer.name).font(Theme.font(.subheadline, weight: .semibold)).foregroundStyle(Theme.text)
                                Text([store.byline(post), JamDates.text(post.created)].compactMap { $0 }.joined(separator: " \u{00B7} ")).font(Theme.caption).foregroundStyle(Theme.textSecondary)
                                    .accessibilityIdentifier("jam-reader-byline")
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
                            // The pictures an article carries stand where the writer put them (LIME-188e).
                            FormattedMessageText(markdown: post.markdown, ink: Theme.text, link: Theme.linkOther,
                                                 postImage: { caption, index in AnyView(JamInlineAttachment(postID: post.postId, index: index, caption: caption)) })
                                .accessibilityIdentifier("jam-reader-body")
                        }
                        // Anything the text does not place (a quick post's photos, a recording) comes after it.
                        JamAttachmentsView(postID: post.postId, skipping: JamInline.placed(in: post.markdown))
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
    /// In a feed card: pictures a little smaller.
    var compact = false
    /// Numbers of files the text already shows in place.
    var skipping: Set<Int> = []
    @Environment(ConversationStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(store.jamAttachments(postID).enumerated()).filter { !skipping.contains($0.offset) }.map(\.element), id: \.attachmentId) { file in
                switch file.kind {
                case "image": JamPhoto(postID: postID, file: file)
                case "video": JamVideo(postID: postID, file: file)
                case "audio": JamAudio(postID: postID, file: file)
                default: JamFileCard(postID: postID, file: file)
                }
            }
        }
    }
}

enum JamInline {
    /// The numbers of the attachments the text puts in place, with an image block each.
    static func placed(in markdown: String) -> Set<Int> {
        Set(MessageRender.blocks(markdown, post: true).compactMap { if case .image(_, let index) = $0 { index } else { nil } })
    }
}

/// One image block of an article: the picture (or a card for a file) at full width, its caption under it; a tap opens the picture full screen.
struct JamInlineAttachment: View {
    let postID: String
    let index: Int
    let caption: String
    @Environment(ConversationStore.self) private var store
    @State private var full: UIImage?

    var body: some View {
        let files = store.jamAttachments(postID)
        if files.indices.contains(index) {
            let file = files[index]
            VStack(alignment: .leading, spacing: 6) {
                if file.kind == "image" {
                    JamPhoto(postID: postID, file: file, onLoaded: { full = $0 }, tapToOpen: true)
                } else if file.kind == "video" {
                    JamVideo(postID: postID, file: file)
                } else {
                    JamFileCard(postID: postID, file: file)
                }
                if !caption.isEmpty { Text(caption).font(Theme.caption).foregroundStyle(Theme.textSecondary).accessibilityIdentifier("jam-inline-caption") }
            }
            .padding(.vertical, 4)
            .accessibilityIdentifier("jam-inline-\(index)")
        }
    }
}

private struct JamPhoto: View {
    let postID: String
    let file: JamAttachmentInfo
    var onLoaded: ((UIImage) -> Void)? = nil
    var tapToOpen = false
    @Environment(ConversationStore.self) private var store
    @State private var image: UIImage?
    @State private var failed = false
    @State private var opened = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityLabel(file.name.isEmpty ? "Photo" : "Photo, \(file.name)")
                    .onTapGesture { if tapToOpen { opened = true } }
                    .accessibilityAddTraits(tapToOpen ? .isButton : [])
                    .fullScreenCover(isPresented: $opened) {
                        ZStack(alignment: .topTrailing) {
                            Color.black.ignoresSafeArea()
                            Image(uiImage: image).resizable().scaledToFit().ignoresSafeArea()
                            Button { opened = false } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 30)).foregroundStyle(.white).frame(width: 44, height: 44) }
                                .padding().accessibilityLabel("Close").accessibilityIdentifier("jam-photo-close")
                        }
                        .onTapGesture { opened = false }
                    }
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.surface)
                    .aspectRatio(file.width.flatMap { w in file.height.map { CGFloat(w) / CGFloat(max($0, 1)) } } ?? 1.5, contentMode: .fit)
                    .overlay { if failed { Text("Photo not available").font(Theme.caption).foregroundStyle(Theme.textSecondary) } else { ProgressView() } }
            }
        }
        .accessibilityIdentifier("jam-photo")
        .task {
            if let data = await store.jamAttachmentData(postID, file.attachmentId), let picture = UIImage(data: data) { image = picture; onLoaded?(picture) } else { failed = true }
        }
    }
}

/// A recording that is a video: the picture (tap to play or pause) and, under it, the same player as a podcast.
struct JamVideo: View {
    let postID: String
    let file: JamAttachmentInfo
    @Environment(ConversationStore.self) private var store
    @State private var controller: PodcastController?

    var body: some View {
        let controller = self.controller ?? makeController()
        VStack(spacing: 10) {
            Button { Task { await controller.toggle(data: { await store.jamAttachmentData(postID, file.attachmentId) }) } } label: {
                ZStack {
                    if controller.simulated || controller.player == nil {
                        if let poster = UIImage(data: file.poster) { Image(uiImage: poster).resizable().scaledToFit() } else { Rectangle().fill(Theme.surface).aspectRatio(16.0 / 9, contentMode: .fit) }
                    } else {
                        PlayerLayerView(player: controller.player).aspectRatio(file.width.flatMap { w in file.height.map { CGFloat(w) / CGFloat(max($0, 1)) } } ?? 16.0 / 9, contentMode: .fit)
                    }
                    if controller.loading { ProgressView() }
                    else if !controller.isPlaying { Image(systemName: "play.circle.fill").font(.system(size: 52)).foregroundStyle(.white).shadow(radius: 4) }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain).accessibilityLabel(controller.isPlaying ? "Pause video" : "Play video").accessibilityIdentifier("jam-video")
            PodcastBar(controller: controller, waveform: Data(), load: { await store.jamAttachmentData(postID, file.attachmentId) }, id: file.attachmentId)
        }
        .onAppear { if self.controller == nil { self.controller = controller } }
    }

    private func makeController() -> PodcastController {
        let post = store.jamPost(postID)
        let controller = PodcastController(duration: Double(file.durationMs ?? 0) / 1000, title: post?.title ?? "", artist: store.teacherName(post?.author ?? ""), isVideo: true)
        #if DEBUG
        controller.simulated = store.isDemo
        #endif
        return controller
    }
}

/// A recording that is audio: the podcast player, with the waveform the writer's phone made.
struct JamAudio: View {
    let postID: String
    let file: JamAttachmentInfo
    @Environment(ConversationStore.self) private var store
    @State private var controller: PodcastController?

    var body: some View {
        let controller = self.controller ?? makeController()
        PodcastBar(controller: controller, waveform: file.thumb, load: { await store.jamAttachmentData(postID, file.attachmentId) }, id: file.attachmentId)
            .onAppear { if self.controller == nil { self.controller = controller } }
    }

    private func makeController() -> PodcastController {
        let post = store.jamPost(postID)
        let controller = PodcastController(duration: Double(file.durationMs ?? 0) / 1000, title: post?.title ?? "", artist: store.teacherName(post?.author ?? ""))
        #if DEBUG
        controller.simulated = store.isDemo
        #endif
        return controller
    }
}

struct JamFileCard: View {
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

/// On a teacher's profile, which is their jam's page (LIME-188b): the subscriber count (public), **Subscribe / Subscribed ✓**, and their posts. Posts
/// are readable once you subscribe; before that the page says so (the server's page holds no post text). On your own profile: your posts, who follows,
/// and Edit jam page. The server learns that this account looked at the page, as it does for a profile.
struct JamProfileSection: View {
    let userID: String
    let isMe: Bool
    @Environment(ConversationStore.self) private var store
    @State private var page: JamPageInfo?
    @State private var reading: JamPostRoute?
    @State private var editing: JamInfo?
    @State private var viewingSubscribers = false
    @State private var confirmingEnd = false

    var body: some View {
        ZStack {
            // Something always in the tree, so the lookup below runs even while there is nothing to show.
            Color.clear.frame(height: 0).accessibilityHidden(true)
            if let page { content(page) }
        }
        .task(id: userID) { await load() }
        .onChange(of: store.jamsMine) { _, _ in if isMe { Task { await load() } } }
        .sheet(item: $reading) { route in NavigationStack { JamPostView(postID: route.postID).toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { reading = nil } } } } }
        .sheet(item: $editing) { JamDetailsSheet(editing: $0) }
        .sheet(isPresented: $viewingSubscribers) { NavigationStack { JamSubscribersView(jamID: page?.jamId ?? "") } }
    }

    private func load() async {
        if isMe { page = store.jamsMine.first.map { JamPageInfo(jamId: $0.jamId, writerId: $0.writer, title: $0.title, about: $0.about, topics: $0.topics, postCount: $0.postCount, subscriberCount: $0.subscriberCount) } }
        else { page = await store.jamPage(of: userID) }
    }

    @ViewBuilder
    private func content(_ page: JamPageInfo) -> some View {
        let following = store.isFollowing(page.jamId)
        // On my own page: my jam's posts and the ones I am credited on.
        let posts = isMe ? (store.posts(of: page.jamId) + store.coauthoredPosts.filter { c in !store.posts(of: page.jamId).contains { $0.postId == c.postId } }).sorted { $0.created > $1.created } : store.posts(of: page.jamId)
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(page.title).font(Theme.font(.title3, weight: .bold)).foregroundStyle(Theme.text).accessibilityAddTraits(.isHeader).accessibilityIdentifier("profile-jam-row")
                if !page.topics.isEmpty { Text(page.topics.joined(separator: " \u{00B7} ")).font(Theme.secondary).foregroundStyle(Theme.textSecondary) }
                Text(page.subscriberCount == 1 ? "1 subscriber" : "\(page.subscriberCount) subscribers").font(Theme.secondary).foregroundStyle(Theme.textSecondary)
                    .accessibilityIdentifier("profile-jam-subscribers")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if isMe {
                HStack(spacing: 10) {
                    pill("Edit jam page", id: "jam-edit-page") { editing = store.jamsMine.first }
                    pill("Subscribers", id: "jam-subscribers") { store.loadJamSubscribers(page.jamId); viewingSubscribers = true }
                    pill("End jam", id: "jam-end") { confirmingEnd = true }
                }
            } else {
                Button { Task { if following { await store.unsubscribe(page.jamId) } else { await store.subscribe(to: page) } } } label: {
                    Text(following ? "Subscribed \u{2713}" : "Subscribe").font(Theme.title).foregroundStyle(following ? Theme.text : Theme.accentInk)
                        .frame(maxWidth: .infinity, minHeight: 50).background(following ? Theme.surface : Theme.accent, in: Capsule())
                }
                .buttonStyle(.plain).accessibilityIdentifier("profile-jam-subscribe")
                .accessibilityLabel(following ? "Subscribed. Tap to unsubscribe." : "Subscribe to \(page.title)")
            }
            Text("Posts").font(Theme.font(.headline, weight: .semibold)).foregroundStyle(Theme.text).accessibilityAddTraits(.isHeader)
            if isMe || following {
                if posts.isEmpty {
                    Text(isMe ? "Your posts show here." : "Nothing here yet.").font(Theme.body).foregroundStyle(Theme.textSecondary)
                }
                VStack(spacing: 0) {
                    ForEach(posts, id: \.postId) { post in
                        JamPostCard(post: post, showsWriter: false) { reading = JamPostRoute(postID: $0) }
                        Divider().overlay(Theme.hairline)
                    }
                }
                .padding(.horizontal, -20)
            } else {
                Text("Subscribe to read their posts.").font(Theme.body).foregroundStyle(Theme.textSecondary).accessibilityIdentifier("profile-jam-locked")
            }
        }
        .padding(.top, 6)
        .confirmSheet("End this jam?", isPresented: $confirmingEnd) {
            Button("End jam", role: .destructive) { Task { await store.endJam(page.jamId); await load() } }.accessibilityIdentifier("jam-end-confirm")
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Subscribers keep what they have.")
        }
    }

    private func pill(_ label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(Theme.secondary).foregroundStyle(Theme.text).padding(.horizontal, 12).frame(minHeight: 44).background(Theme.surface, in: Capsule())
        }
        .buttonStyle(.plain).accessibilityIdentifier(id)
    }
}

extension JamPostRoute: Identifiable { var id: String { postID } }
