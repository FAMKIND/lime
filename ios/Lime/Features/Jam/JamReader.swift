import AVFoundation
import AVKit
import SwiftUI

/// Reading one post (LIME-188): the title, who wrote it, the date, the body drawn the way chats draw Markdown, and its photos, videos and files.
/// (Replying to the writer comes with LIME-189.)
struct JamPostView: View {
    let postID: String
    /// Open scrolled to the comments (LIME-189d).
    var toComments = false
    @Environment(ConversationStore.self) private var store

    @AppStorage(ReaderPrefs.fontKey) private var fontRaw = ReaderFont.newYork.rawValue
    @AppStorage(ReaderPrefs.sizeKey) private var sizeStep = 0
    @AppStorage(ReaderPrefs.lineKey) private var lineStep = 0
    @State private var editingPost: JamPostInfo?
    @State private var confirmingDelete = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let post = store.jamPost(postID)
        Group {
            if post?.kind == "article" {
                JamArticlePage(postID: postID, toComments: toComments)
            } else {
                quickReader(post)
            }
        }
        .onAppear { JamRead.mark(postID) }
    }

    /// A quick post or a recording, read in the reader's chosen face too.
    private func quickReader(_ post: JamPostInfo?) -> some View {
        let face = ReaderFont(rawValue: fontRaw) ?? .newYork
        let size = ReaderPrefs.points(forStep: sizeStep)
        return ScrollViewReader { proxy in ScrollView {
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
                            BylineAvatar(people: store.bylinePeople(post), jam: post.displayAs == "jam" ? store.jamTitle(post.jamId) : nil, size: 36)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(post.displayAs == "jam" ? store.jamTitle(post.jamId) : writer.name).font(Theme.font(.subheadline, weight: .semibold)).foregroundStyle(Theme.text)
                                Text([post.displayAs == "jam" ? "by \(writer.name)" : nil, store.byline(post), JamDates.text(post.created), post.editedAt > 0 ? "Edited \(JamDates.text(post.editedAt))" : nil].compactMap { $0 }.joined(separator: " \u{00B7} ")).font(Theme.caption).foregroundStyle(Theme.textSecondary)
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
                    if post.state == "ready" { JamEngagementSection(post: post).id("comments") }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .task { if toComments { try? await Task.sleep(for: .milliseconds(400)); withAnimation { proxy.scrollTo("comments", anchor: .top) } } }
        }
        .background(Theme.canvas)
        .environment(\.postContext, PostContext(post: post))
        .environment(\.postBodyFont, post?.kind == "quick" ? face.font(size: size) : nil)
        .environment(\.postLineSpacing, post?.kind == "quick" ? ReaderPrefs.lineSpacing(size: size, step: lineStep) : 0)
        .linkOpening()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            // The writer's own post: Edit and Delete in a ⋯ (until the cards have theirs, LIME-199).
            if let post, post.author == store.meProvider().id {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { editingPost = post } label: { Label("Edit", systemImage: "pencil") }.accessibilityIdentifier("options-edit")
                        Button(role: .destructive) { confirmingDelete = true } label: { Label("Delete post", systemImage: "trash") }.accessibilityIdentifier("options-delete")
                    } label: { Image(systemName: "ellipsis") }
                        .accessibilityLabel("More").accessibilityIdentifier("jam-post-more")
                }
            }
        }
        .fullScreenCover(item: $editingPost) { JamComposeSheet(editing: $0) }
        .confirmationDialog("Delete this post?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete post", role: .destructive) { if let post { Task { _ = await store.deleteJamPost(post.postId); dismiss() } } }.accessibilityIdentifier("options-delete-confirm")
            Button("Cancel", role: .cancel) {}
        } message: { Text("It goes from your subscribers' phones too.") }
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
                case "audio": JamAudioCard(postID: postID, file: file, coverFile: cover, captionFile: JamCaptions.file(for: entry.offset, in: all), showsWords: compact)
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
    @Environment(\.verticalSizeClass) private var verticalSize

    private struct ViewerStart: Identifiable { let index: Int; var id: Int { index } }

    var body: some View {
        let _ = verticalSize   // turning the phone redraws the frames
        let many = files.count > 1
        // A row you swipe is always portrait, 4:5 (LIME-188y: the "Pine" frame); one picture takes the standard frame nearest to its own shape.
        let ratio = many ? JamMedia.portrait : JamMedia.ratio(width: files.first?.width, height: files.first?.height)
        // An item is the column less a peek of the next, the row runs to the screen's right edge, 12 pt between. A frame never passes 600 pt wide or
        // 80% of the screen's height, so sideways on a phone it stays in proportion.
        let size = JamMedia.size(ratio: ratio, column: many ? JamMedia.column - 28 : JamMedia.column, screenHeight: UIScreen.main.bounds.height)
        let tileWidth = size.width
        let height = size.height
        GeometryReader { geo in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: JamMedia.gap) {
                    ForEach(Array(files.enumerated()), id: \.element.attachmentId) { index, file in
                        tile(file, index: index, size: size)
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
        .padding(.trailing, many ? -20 : 0)
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
            AttachmentViewer(items: files.map(item), start: start.index, load: { await picture(for: $0.id) }, bottomBar: AnyView(JamViewerBar(postID: postID)))
        }
    }

    private var index: Int { files.firstIndex { $0.attachmentId == current } ?? 0 }

    private func tile(_ file: JamAttachmentInfo, index: Int, size tileSize: CGSize) -> some View {
        // The size is set before the clip: a picture that fills the frame is wider or taller than it, and clipping first would draw it over its neighbours
        // with square corners (LIME-196).
        ZStack {
            Theme.surface
            if let image = images[file.attachmentId] { Image(uiImage: image).resizable().scaledToFill() } else { ProgressView() }
        }
        .frame(width: tileSize.width, height: tileSize.height)
        .clipped()
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
                Image(uiImage: image).resizable().scaledToFit()
                    .frame(maxWidth: JamMedia.maxColumn, maxHeight: UIScreen.main.bounds.height * JamMedia.maxHeightShare)
                    .jamMediaClip()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel(file.name.isEmpty ? "Photo" : "Photo, \(file.name)")
                    .onTapGesture { if tapToOpen { opened = true } }
                    .accessibilityAddTraits(tapToOpen ? .isButton : [])
                    .fullScreenCover(isPresented: $opened) {
                        ZStack(alignment: .topTrailing) {
                            Color.black.ignoresSafeArea()
                            Image(uiImage: image).resizable().scaledToFit().ignoresSafeArea()
                            VStack { Spacer(); JamViewerBar(postID: postID) }.frame(maxWidth: .infinity, maxHeight: .infinity)
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
        let controller = PodcastController(duration: Double(file.durationMs ?? 0) / 1000, title: post?.title ?? "", artist: store.authorName(post))
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

extension ConversationStore {
    /// A person's posts on their profile: their jam's posts shown as themselves, and (on my own profile) the ones I am credited on. Posts shown as
    /// the jam are the org's (LIME-188x).
    func profilePosts(jamID: String, isMe: Bool) -> [JamPostInfo] {
        let own = posts(of: jamID)
        let all = isMe ? (own + coauthoredPosts.filter { c in !own.contains { $0.postId == c.postId } }).sorted { $0.created > $1.created } : own
        return all.filter { $0.displayAs != "jam" }
    }

    /// The orgs a person writes as (LIME-188x). In v1 that is their jam, when they have posted as it at least once or have given it a title that
    /// is not their own name (a jam made on a first post is named after the person); LIME-193's organisations will add more.
    func profileOrgs(page: JamPageInfo?, personName: String) -> [JamPageInfo] {
        guard let page else { return [] }
        let postedAsJam = posts(of: page.jamId).contains { $0.displayAs == "jam" }
        let title = page.title.trimmingCharacters(in: .whitespaces)
        let differs = !title.isEmpty && title.lowercased() != personName.trimmingCharacters(in: .whitespaces).lowercased()
        return postedAsJam || differs ? [page] : []
    }
}

/// A person's posts of one kind on their profile (the Posts, Articles and Podcasts tabs, LIME-188x). Posts are readable once you subscribe; before
/// that the tab says so (the server's page holds no post text). The server learns that this account looked at the page, as it does for a profile.
struct JamProfilePosts: View {
    let posts: [JamPostInfo]
    /// Which tab: a profile's Podcasts tab is the compact list (LIME-203).
    var segment: JamSegment = .posts
    let locked: Bool
    @Environment(ConversationStore.self) private var store
    @State private var reading: JamPostRoute?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if locked {
                Text("Subscribe to read their posts.").font(Theme.body).foregroundStyle(Theme.textSecondary).accessibilityIdentifier("profile-jam-locked").padding(.top, 6)
            } else if posts.isEmpty {
                Text("Nothing here yet.").font(Theme.body).foregroundStyle(Theme.textSecondary).padding(.top, 6)
            } else {
                ForEach(posts, id: \.postId) { post in
                    JamPostCard(post: post, showsWriter: false, open: { reading = JamPostRoute(postID: $0) }, place: .profileTab(segment))
                    Divider().overlay(Theme.hairline)
                }
                .padding(.horizontal, -20)
            }
        }
        .sheet(item: $reading) { route in NavigationStack { JamPostView(postID: route.postID).toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { reading = nil } } } } }
    }
}

/// The Orgs tab: a row for each org the person writes as (name, subscribers, Subscribe); a tap opens the org's page.
struct JamOrgsSection: View {
    let orgs: [JamPageInfo]
    let isMe: Bool
    @Environment(ConversationStore.self) private var store
    @State private var open: JamPageInfo?

    var body: some View {
        VStack(spacing: 0) {
            ForEach(orgs, id: \.jamId) { org in
                HStack(spacing: 12) {
                    Button { open = org } label: {
                        HStack(spacing: 12) {
                            JamInitialTile(title: org.title, size: 44).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(org.title).font(Theme.font(.body, weight: .semibold)).foregroundStyle(Theme.text)
                                Text(org.subscriberCount == 1 ? "1 subscriber" : "\(org.subscriberCount) subscribers").font(Theme.secondary).foregroundStyle(Theme.textSecondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(minHeight: 56).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(org.title), \(org.subscriberCount) subscribers").accessibilityHint("Opens its page")
                    .accessibilityIdentifier("profile-org-\(org.jamId)")
                    if !isMe { SubscribeLink(page: org, id: "profile-org-subscribe-\(org.jamId)") }
                }
            }
        }
        .padding(.top, 6)
        .sheet(item: $open) { page in JamOrgPage(page: page, isMe: isMe) }
    }
}

/// "Subscribe" as a lime-green text link; "Subscribed ✓" in the quiet colour once you follow, and a tap then asks before it unsubscribes.
struct SubscribeLink: View {
    let page: JamPageInfo
    var id = "profile-jam-subscribe"
    @Environment(ConversationStore.self) private var store
    @State private var confirming = false

    var body: some View {
        let following = store.isFollowing(page.jamId)
        Button { if following { confirming = true } else { Task { await store.subscribe(to: page) } } } label: {
            Text(following ? "Subscribed \u{2713}" : "Subscribe").font(Theme.font(.subheadline, weight: .semibold)).foregroundStyle(following ? Theme.textSecondary : Theme.linkOther)
                .frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(following ? "Subscribed to \(page.title). Tap to unsubscribe." : "Subscribe to \(page.title)")
        .accessibilityIdentifier(id)
        .confirmSheet("Unsubscribe from \(page.title)?", isPresented: $confirming) {
            Button("Unsubscribe", role: .destructive) { Task { await store.unsubscribe(page.jamId) } }.accessibilityIdentifier("\(id)-confirm")
            Button("Cancel", role: .cancel) {}
        } message: { Text("What you have stays on this phone.") }
    }
}

/// An org's page (LIME-188x), opened from the Orgs tab: its head (title, topics, subscribers; Edit jam page, Subscribers and End jam on your own),
/// then the posts shown as the org with All · Posts · Articles · Podcasts.
struct JamOrgPage: View {
    let page: JamPageInfo
    let isMe: Bool
    @Environment(ConversationStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var segment: JamSegment = .all
    @State private var reading: JamPostRoute?
    @State private var editing: JamInfo?
    @State private var viewingSubscribers = false
    @State private var confirmingEnd = false

    var body: some View {
        let following = store.isFollowing(page.jamId)
        let posts = store.posts(of: page.jamId).filter { $0.displayAs == "jam" && segment.includes(kind: $0.kind) }
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(page.title).font(Theme.font(.title3, weight: .bold)).foregroundStyle(Theme.text).accessibilityAddTraits(.isHeader).accessibilityIdentifier("profile-jam-row")
                        if !page.topics.isEmpty { Text(page.topics.joined(separator: " \u{00B7} ")).font(Theme.secondary).foregroundStyle(Theme.textSecondary) }
                        Text(page.subscriberCount == 1 ? "1 subscriber" : "\(page.subscriberCount) subscribers").font(Theme.secondary).foregroundStyle(Theme.textSecondary)
                            .accessibilityIdentifier("profile-jam-subscribers")
                        if !page.about.isEmpty { Text(page.about).font(Theme.body).foregroundStyle(Theme.text).padding(.top, 4) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if isMe {
                        HStack(spacing: 10) {
                            pill("Edit jam page", id: "jam-edit-page") { editing = store.jamsMine.first }
                            pill("Subscribers", id: "jam-subscribers") { store.loadJamSubscribers(page.jamId); viewingSubscribers = true }
                            pill("End jam", id: "jam-end") { confirmingEnd = true }
                        }
                    } else {
                        SubscribeLink(page: page, id: "profile-org-page-subscribe")
                    }
                    if isMe || following {
                        Picker("Show", selection: $segment) { ForEach(JamSegment.allCases, id: \.self) { Text($0.title).tag($0) } }
                            .pickerStyle(.segmented).accessibilityIdentifier("profile-org-segments")
                        if posts.isEmpty { Text("Nothing here yet.").font(Theme.body).foregroundStyle(Theme.textSecondary) }
                        VStack(spacing: 0) {
                            ForEach(posts, id: \.postId) { post in
                                JamPostCard(post: post, showsWriter: false, open: { reading = JamPostRoute(postID: $0) }, place: .orgPage(segment))
                                Divider().overlay(Theme.hairline)
                            }
                        }
                        .padding(.horizontal, -20)
                    } else {
                        Text("Subscribe to read their posts.").font(Theme.body).foregroundStyle(Theme.textSecondary).accessibilityIdentifier("profile-jam-locked")
                    }
                }
                .padding(.horizontal, 20).padding(.top, 6)
            }
            .background(Theme.canvas.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("profile-org-done") } }
            .sheet(item: $reading) { route in NavigationStack { JamPostView(postID: route.postID).toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { reading = nil } } } } }
            .sheet(item: $editing) { JamDetailsSheet(editing: $0) }
            .sheet(isPresented: $viewingSubscribers) { NavigationStack { JamSubscribersView(jamID: page.jamId) } }
            .confirmSheet("End this jam?", isPresented: $confirmingEnd) {
                Button("End jam", role: .destructive) { Task { await store.endJam(page.jamId); dismiss() } }.accessibilityIdentifier("jam-end-confirm")
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Subscribers keep what they have.")
            }
        }
    }

    private func pill(_ label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(Theme.secondary).foregroundStyle(Theme.text).padding(.horizontal, 12).frame(minHeight: 44).background(Theme.surface, in: Capsule())
        }
        .buttonStyle(.plain).accessibilityIdentifier(id)
    }
}

extension JamPageInfo: Identifiable { public var id: String { jamId } }

extension JamPostRoute: Identifiable { var id: String { postID } }
