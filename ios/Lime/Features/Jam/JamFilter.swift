import SwiftUI

/// The jam feed's segments (LIME-188x): **All**, **Posts** (quick posts: words, photos, videos that are not recordings), **Articles** and
/// **Podcasts** (recordings, audio or video).
enum JamSegment: Int, CaseIterable {
    case all, posts, articles, podcasts
    var title: String { ["All", "Posts", "Articles", "Podcasts"][rawValue] }
    func includes(kind: String) -> Bool {
        switch self { case .all: true; case .posts: kind == "quick"; case .articles: kind == "article"; case .podcasts: kind == "record" }
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

/// The glass segmented control and the filter button with its menu: the same row as link and call.
struct JamFilterRow: View {
    @Binding var segment: JamSegment
    @Binding var filter: JamFilter
    var idPrefix = "jam-filter"

    var body: some View {
        FilterRow(titles: JamSegment.allCases.map(\.title), selection: Binding(get: { segment.rawValue }, set: { segment = JamSegment(rawValue: $0) ?? .all }),
                  activeCount: filter.activeCount, idPrefix: idPrefix) {
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
    }
}
