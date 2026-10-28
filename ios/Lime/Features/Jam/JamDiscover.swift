import SwiftUI

/// Where an open post is pushed on the jam tab (LIME-210c).
struct OpenPostRoute: Hashable { let postID: String }

/// What a Discover item says it is, in the plural ("articles", "posts", "podcasts").
private func plural(_ items: [OpenFeedItem]) -> String {
    let kinds = Set(items.map(\.kind))
    return kinds == ["article"] ? "articles" : kinds == ["record"] ? "podcasts" : "posts"
}

/// Discover (LIME-210c, `docs/jam.md` 13.3): the posts teachers chose to make open, newest first, **no rankings**. Filters by subject, grade or topic are
/// done here on the phone, so the server never learns what a person looks for. A writer with many posts is **grouped** ("Shem posted 12 articles").
struct JamDiscoverList: View {
    @Environment(ConversationStore.self) private var store
    @State private var topic: String?
    @State private var expanded: Set<String> = []

    private struct Row: Identifiable {
        let id: String
        let author: String
        let items: [OpenFeedItem]
        var isGroup: Bool { id.hasPrefix("group-") }
    }

    /// A writer with three or more posts in the list becomes one group at the place of their newest.
    private func rows(_ items: [OpenFeedItem]) -> [Row] {
        var perAuthor: [String: [OpenFeedItem]] = [:]
        for item in items { perAuthor[item.authorId, default: []].append(item) }
        var done: Set<String> = []
        var out: [Row] = []
        for item in items {
            let mine = perAuthor[item.authorId] ?? []
            if mine.count >= 3 {
                if done.insert(item.authorId).inserted { out.append(Row(id: "group-\(item.authorId)", author: item.authorId, items: mine)) }
            } else {
                out.append(Row(id: item.postId, author: item.authorId, items: [item]))
            }
        }
        return out
    }

    var body: some View {
        let items = store.discoverList(topic: topic)
        VStack(spacing: 0) {
            if !store.discoverTopics.isEmpty { chips }
            if items.isEmpty {
                Text(topic == nil ? "Nothing here yet. Posts teachers share with everyone show up here." : "No posts match.")
                    .font(Theme.body).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
                    .padding(.horizontal, 40).padding(.top, 60).accessibilityIdentifier("discover-empty")
            }
            ForEach(rows(items)) { row in
                if row.isGroup {
                    group(row)
                } else if let item = row.items.first {
                    DiscoverCard(item: item)
                    Divider().overlay(Theme.hairline)
                }
            }
        }
        .task { await store.refreshDiscover(force: true) }
        .task(id: store.discoverItems.count) {
            for author in Set(store.discoverItems.map(\.authorId)).prefix(20) where store.openWriterPages[author] == nil { _ = await store.openWriterPage(author) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("jam-discover")
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All", on: topic == nil, id: "discover-topic-all") { topic = nil }
                ForEach(store.discoverTopics, id: \.self) { name in
                    chip(name, on: topic?.caseInsensitiveCompare(name) == .orderedSame, id: "discover-topic-\(name)") { topic = name }
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 8)
        }
        .accessibilityIdentifier("discover-topics")
    }

    private func chip(_ title: String, on: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(Theme.font(.subheadline, weight: on ? .semibold : .regular)).foregroundStyle(on ? Theme.text : Theme.textSecondary)
                .padding(.horizontal, 14).frame(minHeight: 44)
                .background { if on { Capsule().fill(.clear).limeGlass(in: Capsule()) } else { Capsule().strokeBorder(Theme.hairline, lineWidth: 1) } }
        }
        .buttonStyle(.plain).accessibilityAddTraits(on ? [.isSelected] : []).accessibilityIdentifier(id)
    }

    /// "Shem posted 12 articles": one row for a writer's many posts, which opens to show them.
    @ViewBuilder
    private func group(_ row: Row) -> some View {
        let open = expanded.contains(row.author)
        let name = store.openWriterName(row.author)
        Button { withAnimation { if open { expanded.remove(row.author) } else { expanded.insert(row.author) } } } label: {
            HStack(spacing: 12) {
                AvatarView(person: store.teacher(row.author), size: 40).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(name) posted \(row.items.count) \(plural(row.items))").font(Theme.font(.subheadline, weight: .semibold)).foregroundStyle(Theme.text).multilineTextAlignment(.leading)
                    Text(row.items.first.map { JamDates.short($0.created) } ?? "").font(Theme.caption).foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: open ? "chevron.up" : "chevron.down").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textSecondary).accessibilityHidden(true)
            }
            .padding(.horizontal, 20).padding(.vertical, 12).frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(name) posted \(row.items.count) \(plural(row.items))").accessibilityValue(open ? "Expanded" : "Collapsed")
        .accessibilityHint(open ? "Hides them" : "Shows them").accessibilityIdentifier("discover-group-\(row.author)")
        if open { ForEach(row.items, id: \.postId) { DiscoverCard(item: $0); Divider().overlay(Theme.hairline) } } else { Divider().overlay(Theme.hairline) }
    }
}

/// One open post in Discover: who and when, the globe (open) or the lock and "Preview" (the rest is for subscribers), the title and a few lines.
struct DiscoverCard: View {
    let item: OpenFeedItem
    @Environment(ConversationStore.self) private var store
    @State private var reporting: ReportTarget?

    var body: some View {
        let isPreview = item.previewOf != nil
        Button { open() } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    AvatarView(person: store.teacher(item.authorId), size: 28).accessibilityHidden(true)
                    Text(store.openWriterName(item.authorId)).font(Theme.font(.subheadline, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                    Text("\u{00B7} \(JamDates.short(item.created))").font(Theme.secondary).foregroundStyle(Theme.textSecondary)
                    Spacer(minLength: 0)
                    HStack(spacing: 4) {
                        Image(systemName: isPreview ? "lock" : "globe").font(.system(size: 12, weight: .medium)).accessibilityHidden(true)
                        if isPreview { Text("Preview").font(Theme.caption) }
                    }
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityElement(children: .ignore).accessibilityLabel(isPreview ? "Preview, the rest is for subscribers" : "Open to everyone")
                    .accessibilityIdentifier(isPreview ? "discover-preview-\(item.postId)" : "discover-globe-\(item.postId)")
                }
                if !item.title.isEmpty { Text(item.title).font(Theme.font(.headline, weight: .semibold)).foregroundStyle(Theme.text).multilineTextAlignment(.leading) }
                let line = item.subtitle.isEmpty ? item.excerpt : item.subtitle
                if !line.isEmpty { Text(line).font(Theme.body).foregroundStyle(Theme.textSecondary).lineLimit(2).multilineTextAlignment(.leading) }
                if !item.topics.isEmpty { Text(item.topics.joined(separator: " \u{00B7} ")).font(Theme.caption).foregroundStyle(Theme.textSecondary).lineLimit(1) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20).padding(.vertical, 14).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the post")
        .accessibilityIdentifier("discover-post-\(item.postId)")
        .overlay(alignment: .topTrailing) {
            // Report is on every open post for every reader (LIME-210h, docs/jam.md 13.9).
            Menu {
                Button(role: .destructive) { Task { if let post = await store.openPost(item.postId) { reporting = store.reportTarget(openPost: post) } } } label: { Label("Report", systemImage: "flag") }
                    .accessibilityIdentifier("discover-report-\(item.postId)")
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.textSecondary).frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .accessibilityLabel("More").accessibilityIdentifier("discover-more-\(item.postId)")
        }
        .reportSheet($reporting)
    }

    /// A post I can already read in full (mine, or from a jam I follow) opens as usual; anything else opens the open copy.
    private func open() {
        if store.jamPost(item.postId) != nil { store.jamPath.append(JamPostRoute(postID: item.postId)) } else { store.jamPath.append(OpenPostRoute(postID: item.postId)) }
    }
}

/// An open post, read by someone who may not be a subscriber (LIME-210c, 13.4 and 13.5): the open text, and at a Preview's cut a quiet rule and **Subscribe
/// to read the rest**. Likes and comments are for subscribers: for anyone else they say so. When the reader subscribes (or already is one) the whole post
/// opens instead.
struct OpenPostPage: View {
    let postID: String
    @Environment(ConversationStore.self) private var store
    @State private var post: OpenPostInfo?
    @State private var failed = false
    @State private var page: JamPageInfo?
    @State private var asking = false
    @State private var reporting: ReportTarget?

    var body: some View {
        Group {
            if store.jamPost(postID) != nil {
                JamPostView(postID: postID)
            } else if let post {
                content(post)
            } else if failed {
                Text("This post is no longer available.").font(Theme.body).foregroundStyle(Theme.textSecondary).frame(maxWidth: .infinity, maxHeight: .infinity).accessibilityIdentifier("open-post-gone")
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.canvas)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let post, store.jamPost(postID) == nil {
                    Menu {
                        Button(role: .destructive) { reporting = store.reportTarget(openPost: post) } label: { Label("Report", systemImage: "flag") }.accessibilityIdentifier("open-post-report")
                    } label: { Image(systemName: "ellipsis") }
                    .accessibilityLabel("More").accessibilityIdentifier("open-post-more")
                }
            }
        }
        .reportSheet($reporting)
        .task {
            if let loaded = await store.openPost(postID) {
                post = loaded
                page = await store.openWriterPage(loaded.authorId)
            } else {
                failed = true
            }
        }
    }

    private func content(_ post: OpenPostInfo) -> some View {
        let isPreview = post.previewOf != nil
        let writer = store.teacher(post.authorId)
        let segments = ArticleSegments.split(post.markdown)
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let jam = page?.title, !jam.isEmpty {
                    Text(jam.uppercased()).font(Theme.font(.caption, weight: .semibold)).tracking(1).foregroundStyle(Theme.textSecondary)
                }
                if !post.title.isEmpty {
                    Text(post.title).font(Theme.font(.title2, weight: .bold)).foregroundStyle(Theme.text).accessibilityAddTraits(.isHeader).accessibilityIdentifier("open-post-title")
                }
                if !post.subtitle.isEmpty { Text(post.subtitle).font(Theme.font(.title3)).foregroundStyle(Theme.textSecondary) }
                HStack(spacing: 10) {
                    AvatarView(person: writer, size: 36).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(store.teacherName(post.authorId)).font(Theme.font(.subheadline, weight: .semibold)).foregroundStyle(Theme.text)
                        HStack(spacing: 4) {
                            Text(JamDates.text(post.created))
                            Image(systemName: isPreview ? "lock" : "globe").font(.system(size: 11)).accessibilityHidden(true)
                            if isPreview { Text("Preview") }
                        }
                        .font(Theme.caption).foregroundStyle(Theme.textSecondary)
                        .accessibilityElement(children: .ignore).accessibilityLabel("\(JamDates.spoken(post.created)), \(isPreview ? "preview, the rest is for subscribers" : "open to everyone")")
                    }
                    Spacer(minLength: 0)
                }
                Rectangle().fill(Theme.hairline).frame(height: 1).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                        FormattedMessageText(markdown: segment, ink: Theme.text, link: Theme.linkOther,
                                             postImage: { caption, i in AnyView(OpenInlineImage(file: post.files.indices.contains(i) ? post.files[i] : nil, caption: caption)) })
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("open-post-body")
                if isPreview && post.hasRest { theCut(post) }
                responses(post)
            }
            .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 40)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("open-post-page")
    }

    /// The quiet rule and the one primary action.
    private func theCut(_ post: OpenPostInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Rectangle().fill(Theme.hairline).frame(height: 1).accessibilityHidden(true)
            Button { Task { await subscribe(post) } } label: {
                Text("Subscribe to read the rest").font(Theme.font(.body, weight: .semibold)).foregroundStyle(Theme.accentInk)
                    .padding(.horizontal, 20).frame(minHeight: 48).background(Theme.accent, in: Capsule())
            }
            .buttonStyle(.plain).accessibilityHint("Free. The rest opens here").accessibilityIdentifier("open-post-subscribe")
        }
        .padding(.top, 8)
    }

    /// Hearts and comments come from subscribers (13.5): anyone else is asked to subscribe, which is free. No counts are shown.
    private func responses(_ post: OpenPostInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                ForEach([("heart", "Like"), ("bubble.left", "Comment")], id: \.0) { symbol, label in
                    Button { withAnimation { asking = true } } label: {
                        Image(systemName: symbol).font(.system(size: 20)).foregroundStyle(Theme.textSecondary).frame(width: 44, height: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).accessibilityLabel(label).accessibilityHint("Subscribe to like and comment").accessibilityIdentifier("open-post-\(symbol)")
                }
            }
            if asking {
                HStack(spacing: 12) {
                    Text("Subscribe to like and comment").font(Theme.body).foregroundStyle(Theme.text).accessibilityIdentifier("open-post-subscribe-prompt")
                    Spacer(minLength: 0)
                    Button { Task { await subscribe(post) } } label: { Text("Subscribe").font(Theme.font(.subheadline, weight: .semibold)).foregroundStyle(Theme.linkOther).frame(minHeight: 44) }
                        .buttonStyle(.plain).accessibilityIdentifier("open-post-prompt-subscribe")
                }
                .transition(.opacity)
            }
        }
    }

    private func subscribe(_ post: OpenPostInfo) async {
        let target = page ?? JamPageInfo(jamId: post.jamId, writerId: post.authorId, title: "", about: "", topics: post.topics, postCount: 0, subscriberCount: 0, hasCommunity: false)
        await store.subscribe(to: target)
    }
}

/// A picture of an open post, from its plain public address.
struct OpenInlineImage: View {
    let file: OpenFileRef?
    let caption: String
    @Environment(ConversationStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let file, let url = store.openFileURL(file.url) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFit().frame(maxWidth: JamMedia.maxColumn).jamMediaClip()
                    case .failure: Text("Photo not available").font(Theme.caption).foregroundStyle(Theme.textSecondary)
                    default: RoundedRectangle(cornerRadius: JamMedia.radius, style: .continuous).fill(Theme.surface).frame(height: 180).overlay { ProgressView() }
                    }
                }
                .accessibilityLabel(caption.isEmpty ? "Photo" : "Photo, \(caption)")
            }
            if !caption.isEmpty { Text(caption).font(Theme.caption).foregroundStyle(Theme.textSecondary) }
        }
        .padding(.vertical, 4)
    }
}
