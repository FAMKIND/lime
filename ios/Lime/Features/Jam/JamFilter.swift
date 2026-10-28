import SwiftUI

/// The jam feed's segments (LIME-188x): **All**, **Posts** (quick posts: words, photos, videos that are not recordings), **Articles** and
/// **Podcasts** (recordings, audio or video).
enum JamSegment: Int, CaseIterable {
    case all, posts, articles, podcasts, drafts, discover
    var title: String { ["All", "Posts", "Articles", "Podcasts", "Drafts", "Discover"][rawValue] }
    func includes(kind: String) -> Bool {
        switch self { case .all: true; case .posts: kind == "quick"; case .articles: kind == "article"; case .podcasts: kind == "record"; case .drafts, .discover: false }
    }
}

/// The filters on top of the segment: a media kind, **Co-authored**, **Subscribed** (jams you follow, not your own), **Orgs** (posts shown as a jam,
/// LIME-188q; LIME-193's organisations will show here too) and **Saved** (bookmarked on this phone).
struct JamFilter: Equatable {
    enum Media: String, CaseIterable { case photos = "Photos", video = "Video", audio = "Audio" }
    var media: Media?
    var coauthored = false
    var subscribed = false
    var orgs = false
    var saved = false

    var activeCount: Int { (media != nil ? 1 : 0) + [coauthored, subscribed, orgs, saved].filter { $0 }.count }
    var isOn: Bool { activeCount > 0 }

    /// `files` are the kinds of the post's attachments (`image`, `video`, `audio`, `file`).
    static func matches(kind: String, files: [String], coauthored: Bool, asJam: Bool = false, subscribed: Bool = true, saved: Bool = false, segment: JamSegment, filter: JamFilter) -> Bool {
        if !segment.includes(kind: kind) { return false }
        if filter.coauthored && !coauthored { return false }
        if filter.orgs && !asJam { return false }
        if filter.subscribed && !subscribed { return false }
        if filter.saved && !saved { return false }
        if kind != "article", let media = filter.media {
            switch media {
            case .audio: if !files.contains("audio") { return false }
            case .video: if !files.contains("video") { return false }
            case .photos: if !files.contains("image") { return false }
            }
        }
        return true
    }
}

extension ConversationStore {
    /// Does this post pass the segment and the filters?
    func jamPostMatches(_ post: JamPostInfo, segment: JamSegment, filter: JamFilter) -> Bool {
        let files = post.kind == "article" || filter.media == nil ? [] : jamAttachments(post.postId).filter { !JamCover.isCover($0) }.map(\.kind)
        return JamFilter.matches(kind: post.kind, files: files, coauthored: !post.coauthors.isEmpty, asJam: post.displayAs == "jam",
                                 subscribed: !jamsMine.contains { $0.jamId == post.jamId }, saved: JamSaved.contains(post.postId), segment: segment, filter: filter)
    }
}

/// jam's row under the header (LIME-198): pills **All · Posts · Articles · Podcasts**, one chosen (a glass capsule, like a profile's tabs), that scroll
/// sideways with a soft fade at the left and right edges, and the filter button fixed at the far right, outside the scrolling part.
struct JamFilterRow: View {
    @Binding var segment: JamSegment
    @Binding var filter: JamFilter
    var idPrefix = "jam-filter"
    @Environment(ConversationStore.self) private var store
    private let fade: CGFloat = 16

    var body: some View {
        HStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(JamSegment.allCases.filter { $0 != .discover || store.openPostsEnabled }, id: \.self) { item in
                            let on = segment == item
                            Button { segment = item } label: {
                                Text(item.title).font(Theme.font(.subheadline, weight: on ? .semibold : .regular)).foregroundStyle(on ? Theme.text : Theme.textSecondary)
                                    .padding(.horizontal, 14).frame(minHeight: 44)
                                    .background { if on { Capsule().fill(.clear).limeGlass(in: Capsule()) } }
                            }
                            .buttonStyle(.plain).id(item)
                            .accessibilityLabel(item.title).accessibilityAddTraits(on ? [.isSelected] : [])
                            .accessibilityIdentifier("jam-segment-\(item.title)")
                        }
                    }
                    // Room inside the fades, so at rest the first pill and the last are fully clear.
                    .padding(.horizontal, fade)
                }
                .onChange(of: segment) { _, now in withAnimation { proxy.scrollTo(now, anchor: .center) } }
            }
            .mask {
                HStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing).frame(width: fade)
                    Rectangle().fill(.black)
                    LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing).frame(width: fade)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("\(idPrefix)-segments")
            FilterMenuButton(activeCount: filter.activeCount, idPrefix: idPrefix) {
                Section("Media") {
                    ForEach(JamFilter.Media.allCases, id: \.self) { media in
                        Toggle(media.rawValue, isOn: Binding(get: { filter.media == media }, set: { filter.media = $0 ? media : nil }))
                    }
                }
                Section("Show") {
                    Toggle("Co-authored", isOn: $filter.coauthored)
                    Toggle("Subscribed", isOn: $filter.subscribed)
                    Toggle("Orgs", isOn: $filter.orgs)
                    Toggle("Saved", isOn: $filter.saved).accessibilityIdentifier("\(idPrefix)-saved")
                }
                if filter.isOn {
                    Button("Clear filters", role: .destructive) { filter = JamFilter() }
                }
            }
            .padding(.trailing, 10)
        }
        .frame(maxWidth: .infinity)
    }
}
