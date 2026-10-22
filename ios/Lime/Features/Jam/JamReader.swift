import AVFoundation
import AVKit
import SwiftUI

/// Reading one post (LIME-188): the title, who wrote it, the date, the body drawn the way chats draw Markdown, and its photos, videos and files.
/// (Replying to the writer comes with LIME-189.)
struct JamPostView: View {
    let postID: String
    @Environment(ConversationStore.self) private var store

    @AppStorage(ReaderPrefs.fontKey) private var fontRaw = ReaderFont.newYork.rawValue
    @AppStorage(ReaderPrefs.sizeKey) private var sizeStep = 0
    @AppStorage(ReaderPrefs.lineKey) private var lineStep = 0

    var body: some View {
        let post = store.jamPost(postID)
        if post?.kind == "article" {
            JamArticlePage(postID: postID)
        } else {
            quickReader(post)
        }
    }

    /// A quick post or a recording, read in the reader's chosen face too.
    private func quickReader(_ post: JamPostInfo?) -> some View {
        let face = ReaderFont(rawValue: fontRaw) ?? .newYork
        let size = ReaderPrefs.points(forStep: sizeStep)
        return ScrollView {
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
                            if post.displayAs == "jam" { JamInitialTile(title: store.jamTitle(post.jamId), size: 36).accessibilityHidden(true) } else { AvatarView(person: writer, size: 36).accessibilityHidden(true) }
                            VStack(alignment: .leading, spacing: 0) {
                                Text(post.displayAs == "jam" ? store.jamTitle(post.jamId) : writer.name).font(Theme.font(.subheadline, weight: .semibold)).foregroundStyle(Theme.text)
                                Text([post.displayAs == "jam" ? "by \(writer.name)" : nil, store.byline(post), JamDates.text(post.created)].compactMap { $0 }.joined(separator: " \u{00B7} ")).font(Theme.caption).foregroundStyle(Theme.textSecondary)
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
        .environment(\.postContext, PostContext(post: post))
        .environment(\.postBodyFont, post?.kind == "quick" ? face.font(size: size) : nil)
        .environment(\.postLineSpacing, post?.kind == "quick" ? ReaderPrefs.lineSpacing(size: size, step: lineStep) : 0)
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
        let all = store.jamAttachments(postID)
        let indexed = all.enumerated().filter { !skipping.contains($0.offset) && $0.element.mime != "text/vtt" && !JamCover.isCover($0.element) }
        let cover = all.first(where: JamCover.isCover)
        let files = indexed.map(\.element)
        let photos = files.filter { $0.kind == "image" }
        let links = files.filter { $0.mime == JamLink.mime }
        VStack(alignment: .leading, spacing: 12) {
            // Several photos are one row that scrolls sideways (LIME-188h); a tap opens them in the same viewer chats use.
            if !photos.isEmpty { JamPhotoRow(postID: postID, files: photos, compact: compact) }
            ForEach(links, id: \.attachmentId) { JamLinkCard(postID: postID, file: $0) }
            ForEach(indexed.filter { $0.element.kind != "image" && $0.element.mime != JamLink.mime }, id: \.element.attachmentId) { entry in
                let file = entry.element
                switch file.kind {
                case "video": JamVideoCard(postID: postID, file: file, captionFile: JamCaptions.file(for: entry.offset, in: all))
                case "audio": JamAudioCard(postID: postID, file: file, coverFile: cover, captionFile: JamCaptions.file(for: entry.offset, in: all))
                default: JamFileCard(postID: postID, file: file)
                }
            }
        }
    }
}

/// A link in a post, drawn as the card chats draw: the picture, the title and the site; a tap opens the address.
struct JamLinkCard: View {
    let postID: String
    let file: JamAttachmentInfo
    @Environment(ConversationStore.self) private var store
    @Environment(\.openURL) private var openURL
    @State private var payload: JamLink.Payload?

    var body: some View {
        LinkCardView(title: payload?.title ?? file.name, site: payload?.site ?? "", image: UIImage(data: file.poster), width: 280)
            .contentShape(Rectangle())
            .onTapGesture { if let payload, let url = URL(string: payload.url) { openURL(url) } }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Link: \(payload?.title ?? file.name), \(payload?.site ?? "")").accessibilityAddTraits(.isLink)
            .accessibilityIdentifier("jam-link-card")
            .task {
                guard payload == nil, let data = await store.jamAttachmentData(postID, file.attachmentId) else { return }
                payload = try? JSONDecoder().decode(JamLink.Payload.self, from: data)
            }
    }
}

/// A post's photos in a row you swipe sideways, one page at a time with the next one peeking, and a "1 / 5" counter; a tap opens the full-screen viewer.
struct JamPhotoRow: View {
    let postID: String
    let files: [JamAttachmentInfo]
    var compact = false
    @Environment(ConversationStore.self) private var store
    @State private var images: [String: UIImage] = [:]
    @State private var current: String?
    @State private var viewing: ViewerStart?

    private struct ViewerStart: Identifiable { let index: Int; var id: Int { index } }

    var body: some View {
        let many = files.count > 1
        // One standard frame for the row (the first picture's nearer shape), so the items line up.
        let ratio = JamMedia.ratio(width: files.first?.width, height: files.first?.height)
        let narrow: CGFloat = compact ? 0.8 : 1
        let columnWidth = UIScreen.main.bounds.width - 40
        let tileWidth = (many ? columnWidth * 0.86 : columnWidth) * narrow
        let height = tileWidth / ratio
        GeometryReader { geo in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: JamMedia.gap) {
                    ForEach(Array(files.enumerated()), id: \.element.attachmentId) { index, file in
                        tile(file, index: index)
                            .frame(width: tileWidth, height: height)
                            .id(file.attachmentId)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $current)
        }
        .frame(height: height)
        .overlay(alignment: .topTrailing) {
            if many {
                Text("\(index + 1) / \(files.count)").font(Theme.font(.caption, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 4).background(.black.opacity(0.55), in: Capsule()).padding(10)
                    .accessibilityHidden(true).accessibilityIdentifier("jam-photo-counter")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("jam-photo-row")
        .fullScreenCover(item: $viewing) { start in
            AttachmentViewer(items: files.map(item), start: start.index, load: { await picture(for: $0.id) })
        }
    }

    private var index: Int { files.firstIndex { $0.attachmentId == current } ?? 0 }

    private func tile(_ file: JamAttachmentInfo, index: Int) -> some View {
        ZStack {
            Theme.surface
            if let image = images[file.attachmentId] { Image(uiImage: image).resizable().scaledToFill() } else { ProgressView() }
        }
        .jamMediaClip()
        .contentShape(Rectangle())
        .onTapGesture { viewing = ViewerStart(index: index) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(files.count > 1 ? "Photo \(index + 1) of \(files.count)" : "Photo")
        .accessibilityAddTraits(.isButton).accessibilityHint("Opens the photo")
        .accessibilityIdentifier("jam-row-photo-\(index)")
        .task { _ = await picture(for: file.attachmentId) }
    }

    private func picture(for id: String) async -> UIImage? {
        if let image = images[id] { return image }
        guard let data = await store.jamAttachmentData(postID, id), let image = UIImage(data: data) else { return nil }
        images[id] = image
        return image
    }

    private func item(_ file: JamAttachmentInfo) -> AttachmentItem {
        AttachmentItem(id: file.attachmentId, mime: file.mime, name: file.name, size: Int64(file.size), width: file.width.map(Int.init), height: file.height.map(Int.init),
                       durationMs: file.durationMs.map(Int.init), thumb: file.thumb, downloaded: true)
    }
}

/// A recording's cover is an image attachment named `cover.jpg` (LIME-188k); it is not a photo of the post.
enum JamCover {
    static let name = "cover.jpg"
    static func isCover(_ file: JamAttachmentInfo) -> Bool { file.kind == "image" && file.name == name }
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
                    JamVideoCard(postID: postID, file: file, captionFile: JamCaptions.file(for: index, in: files))
                } else if file.kind == "audio" {
                    JamAudio(postID: postID, file: file)
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
                Image(uiImage: image).resizable().scaledToFit().jamMediaClip()
                    .frame(maxWidth: .infinity, alignment: .leading)
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
                RoundedRectangle(cornerRadius: JamMedia.radius, style: .continuous).fill(Theme.surface)
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
    /// Their jam's page, loaded by the profile (which needs to know whether there is a Posts section).
    let page: JamPageInfo?
    @Environment(ConversationStore.self) private var store
    @State private var kind: PostKind = .all
    @State private var reading: JamPostRoute?
    @State private var editing: JamInfo?
    @State private var viewingSubscribers = false
    @State private var confirmingEnd = false

    var body: some View {
        Group {
            if let page { content(page) }
        }
        .sheet(item: $reading) { route in NavigationStack { JamPostView(postID: route.postID).toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { reading = nil } } } } }
        .sheet(item: $editing) { JamDetailsSheet(editing: $0) }
        .sheet(isPresented: $viewingSubscribers) { NavigationStack { JamSubscribersView(jamID: page?.jamId ?? "") } }
    }

    /// The kinds a profile's Posts can be narrowed to (LIME-188d).
    enum PostKind: String, CaseIterable, Identifiable {
        case all = "All", articles = "Articles", audio = "Audio", video = "Video", quick = "Quick"
        var id: String { rawValue }
    }

    private func matches(_ post: JamPostInfo) -> Bool {
        switch kind {
        case .all: return true
        case .articles: return post.kind == "article"
        case .quick: return post.kind == "quick"
        case .audio, .video:
            let files = store.jamAttachments(post.postId)
            return post.kind == "record" && files.contains { $0.kind == (kind == .audio ? "audio" : "video") }
        }
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
            if isMe || following {
                filterRow
                if posts.filter(matches).isEmpty {
                    Text(isMe ? "Your posts show here." : "Nothing here yet.").font(Theme.body).foregroundStyle(Theme.textSecondary)
                }
                VStack(spacing: 0) {
                    ForEach(posts.filter(matches), id: \.postId) { post in
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
            Button("End jam", role: .destructive) { Task { await store.endJam(page.jamId);  } }.accessibilityIdentifier("jam-end-confirm")
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Subscribers keep what they have.")
        }
    }

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(PostKind.allCases) { option in
                    Button { kind = option } label: {
                        Text(option.rawValue).font(Theme.secondary).foregroundStyle(Theme.text).padding(.horizontal, 14).frame(minHeight: 44)
                            .background(kind == option ? Theme.surface : Color.clear, in: Capsule())
                            .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: kind == option ? 0 : 1))
                    }
                    .buttonStyle(.plain).accessibilityAddTraits(kind == option ? .isSelected : []).accessibilityIdentifier("profile-posts-kind-\(option.rawValue)")
                }
            }
        }
        .accessibilityIdentifier("profile-posts-kinds")
    }

    private func pill(_ label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(Theme.secondary).foregroundStyle(Theme.text).padding(.horizontal, 12).frame(minHeight: 44).background(Theme.surface, in: Capsule())
        }
        .buttonStyle(.plain).accessibilityIdentifier(id)
    }
}

extension JamPostRoute: Identifiable { var id: String { postID } }
