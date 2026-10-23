import SwiftUI

/// What the featured row shows (LIME-188c): the newest articles, recordings and quick posts with media from the teachers you subscribe to and you,
/// from the last 7 days, newest first, at most 10. No ranking: time only.
enum JamFeatured {
    static let days = 7
    static let limit = 10

    static func pick(_ posts: [JamPostInfo], now: Date = Date(), hasMedia: (JamPostInfo) -> Bool) -> [JamPostInfo] {
        let since = Int64((now.timeIntervalSince1970 - Double(days) * 86_400) * 1000)
        return Array(posts.filter { post in
            guard post.state == "ready", post.created >= since else { return false }
            return post.kind == "article" || post.kind == "record" || hasMedia(post)
        }.sorted { $0.created > $1.created }.prefix(limit))
    }

    /// Minutes to read at 200 words a minute, at least one.
    static func minutes(words: Int) -> Int { max(1, Int((Double(words) / 200).rounded(.up))) }
}

/// Which jam posts were opened on this phone (never sent anywhere): an unread article from someone else has a dot.
enum JamRead {
    static let key = "lime.jam.readPosts"
    static var ids: Set<String> { Set(UserDefaults.standard.stringArray(forKey: key) ?? []) }
    static func mark(_ id: String) {
        var now = UserDefaults.standard.stringArray(forKey: key) ?? []
        guard !now.contains(id) else { return }
        now.append(id)
        UserDefaults.standard.set(Array(now.suffix(2000)), forKey: key)
    }
    static func isUnread(_ post: JamPostInfo, me: String) -> Bool { post.kind == "article" && post.state == "ready" && post.author != me && !ids.contains(post.postId) }
}

/// The row at the top of the feed: cards about 70% of the width that swipe sideways. For VoiceOver it is one adjustable element ("Featured, 1 of 6").
struct JamFeaturedRow: View {
    let posts: [JamPostInfo]
    @Environment(ConversationStore.self) private var store
    @State private var current: String?

    private var index: Int { posts.firstIndex { $0.postId == current } ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Featured").font(Theme.font(.subheadline, weight: .semibold)).foregroundStyle(Theme.textSecondary).padding(.horizontal, 20).accessibilityHidden(true)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(posts, id: \.postId) { post in
                        JamFeaturedCard(post: post)
                            .containerRelativeFrame(.horizontal) { width, _ in width * 0.7 }
                            .id(post.postId)
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, 20)
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $current)
        }
        .padding(.top, 8).padding(.bottom, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Featured")
        .accessibilityValue("\(index + 1) of \(posts.count), \(posts[safe: index]?.title ?? "")")
        .accessibilityAdjustableAction { direction in
            let next = direction == .increment ? min(index + 1, posts.count - 1) : max(index - 1, 0)
            withAnimation { current = posts[next].postId }
        }
        .accessibilityAction(named: "Open") { if let post = posts[safe: index] { store.jamPath.append(JamPostRoute(postID: post.postId)) } }
        .accessibilityIdentifier("jam-featured")
    }
}

private struct JamFeaturedCard: View {
    let post: JamPostInfo
    @Environment(ConversationStore.self) private var store
    @State private var image: UIImage?

    var body: some View {
        let writer = store.teacher(post.author)
        let files = store.jamAttachments(post.postId)
        Button { store.jamPath.append(JamPostRoute(postID: post.postId)) } label: {
            VStack(alignment: .leading, spacing: 6) {
                ZStack {
                    if let image {
                        Image(uiImage: image).resizable().scaledToFill()
                    } else {
                        LinearGradient(colors: [Theme.accent.opacity(0.35), Theme.surface], startPoint: .topLeading, endPoint: .bottomTrailing)
                        Text(post.title.isEmpty ? post.plain : post.title).font(Theme.font(.headline, weight: .bold)).foregroundStyle(Theme.text).lineLimit(4).multilineTextAlignment(.leading).padding(14)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    }
                }
                .aspectRatio(1.5, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                HStack(spacing: 6) {
                    AvatarView(person: writer, size: 18)
                    Text(writer.name).font(Theme.caption).foregroundStyle(Theme.textSecondary).lineLimit(1)
                }
                if image != nil, !post.title.isEmpty {
                    Text(post.title).font(Theme.font(.subheadline, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(2).multilineTextAlignment(.leading)
                }
                Text(detail(files)).font(Theme.caption).foregroundStyle(Theme.textSecondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .task {
            if let video = files.first(where: { $0.kind == "video" }), let poster = UIImage(data: video.poster) { image = poster; return }
            if let photo = files.first(where: { $0.kind == "image" && !JamCover.isCover($0) }) ?? files.first(where: JamCover.isCover),
               let data = await store.jamAttachmentData(post.postId, photo.attachmentId) { image = UIImage(data: data) }
        }
    }

    /// "New · 4 min read" for an article, "New · 18:00" for a clip, "New · 3 photos".
    private func detail(_ files: [JamAttachmentInfo]) -> String {
        if post.kind == "article" { return "New \u{00B7} \(JamFeatured.minutes(words: post.plain.split { $0.isWhitespace }.count)) min read" }
        if let clip = files.first(where: { $0.kind == "audio" || $0.kind == "video" }), let ms = clip.durationMs { return "New \u{00B7} \(VoiceFormat.clock(Double(ms) / 1000))" }
        let photos = files.filter { $0.kind == "image" && !JamCover.isCover($0) }.count
        return photos > 1 ? "New \u{00B7} \(photos) photos" : "New \u{00B7} photo"
    }
}
