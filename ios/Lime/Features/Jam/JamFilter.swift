import SwiftUI

/// The jam feed's three segments (LIME-188v): **Posts** (everything that is not an article: quick posts, photos, audio, video), **Articles**
/// (the inbox, LIME-188c) and **Saved** (what is bookmarked on this phone, both kinds).
enum JamSegment: Int, CaseIterable {
    case posts, articles, saved
    var title: String { ["Posts", "Articles", "Saved"][rawValue] }
    /// Which kind the segment lists; nil is both.
    var articles: Bool? { switch self { case .posts: false; case .articles: true; case .saved: nil } }
}

/// The jam feed's and a profile's filters (LIME-188t): the segment, and on top of it a media kind (within Posts), **Co-authored** and
/// **From jams & groups** (posts shown as a jam, LIME-188q; LIME-193's organisations will show here too).
struct JamFilter: Equatable {
    enum Media: String, CaseIterable { case audio = "Audio", video = "Video", photos = "Photos" }
    var media: Media?
    var coauthored = false
    /// Only the posts shown as a jam or a group.
    var orgs = false

    var activeCount: Int { (media != nil ? 1 : 0) + (coauthored ? 1 : 0) + (orgs ? 1 : 0) }
    var isOn: Bool { activeCount > 0 }

    /// The rule both the feed and a profile use. `files` are the kinds of the post's attachments (`image`, `video`, `audio`, `file`).
    static func matches(kind: String, files: [String], coauthored: Bool, asJam: Bool = false, articles: Bool?, filter: JamFilter) -> Bool {
        if let articles, (kind == "article") != articles { return false }
        if filter.coauthored && !coauthored { return false }
        if filter.orgs && !asJam { return false }
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
    /// Does this post pass the Posts | Articles choice and the filters?
    func jamPostMatches(_ post: JamPostInfo, articles: Bool?, filter: JamFilter) -> Bool {
        let files = post.kind == "article" || filter.media == nil ? [] : jamAttachments(post.postId).filter { !JamCover.isCover($0) }.map(\.kind)
        return JamFilter.matches(kind: post.kind, files: files, coauthored: !post.coauthors.isEmpty, asJam: post.displayAs == "jam", articles: articles, filter: filter)
    }
}

/// The glass segmented control and the filter button with its menu: the same row as link and call. The feed has three segments (`segment`); a
/// profile's Posts keeps two (`articles`).
struct JamFilterRow: View {
    private enum Choice { case segment(Binding<JamSegment>), articles(Binding<Bool>) }
    private let choice: Choice
    @Binding var filter: JamFilter
    var idPrefix = "jam-filter"

    init(segment: Binding<JamSegment>, filter: Binding<JamFilter>, idPrefix: String = "jam-filter") {
        choice = .segment(segment); _filter = filter; self.idPrefix = idPrefix
    }

    init(articles: Binding<Bool>, filter: Binding<JamFilter>, idPrefix: String = "jam-filter") {
        choice = .articles(articles); _filter = filter; self.idPrefix = idPrefix
    }

    private var showsMedia: Bool {
        switch choice { case .segment(let s): s.wrappedValue == .posts; case .articles(let a): !a.wrappedValue }
    }

    var body: some View {
        switch choice {
        case .segment(let segment):
            FilterRow(titles: JamSegment.allCases.map(\.title), selection: Binding(get: { segment.wrappedValue.rawValue }, set: { segment.wrappedValue = JamSegment(rawValue: $0) ?? .posts }),
                      activeCount: filter.activeCount, idPrefix: idPrefix, menu: menu)
        case .articles(let articles):
            FilterRow(first: "Posts", second: "Articles", secondSelected: articles, activeCount: filter.activeCount, idPrefix: idPrefix, menu: menu)
        }
    }

    @ViewBuilder
    private func menu() -> some View {
        if showsMedia {
            Section("Media") {
                ForEach(JamFilter.Media.allCases, id: \.self) { media in
                    Toggle(media.rawValue, isOn: Binding(get: { filter.media == media }, set: { filter.media = $0 ? media : nil }))
                }
            }
        }
        Section("Show") {
            Toggle("Co-authored", isOn: $filter.coauthored)
            Toggle("From jams & groups", isOn: $filter.orgs)
        }
        if filter.isOn {
            Button("Clear filters", role: .destructive) { filter = JamFilter() }
        }
    }
}
