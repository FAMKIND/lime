import SwiftUI

/// The jam feed's and a profile's filters (LIME-188t): **Posts | Articles** (Posts is everything that is not an article: quick posts, photos, audio,
/// video), and on top of it a media kind (within Posts) and **Co-authored**. "From orgs & groups" comes with LIME-193 and stays hidden until then.
struct JamFilter: Equatable {
    enum Media: String, CaseIterable { case audio = "Audio", video = "Video", photos = "Photos" }
    var media: Media?
    var coauthored = false
    /// Only the posts of organisations and groups (LIME-193): not offered yet.
    var orgs = false

    var activeCount: Int { (media != nil ? 1 : 0) + (coauthored ? 1 : 0) + (orgs ? 1 : 0) }
    var isOn: Bool { activeCount > 0 }

    /// The rule both the feed and a profile use. `files` are the kinds of the post's attachments (`image`, `video`, `audio`, `file`).
    static func matches(kind: String, files: [String], coauthored: Bool, articles: Bool, filter: JamFilter) -> Bool {
        if (kind == "article") != articles { return false }
        if filter.coauthored && !coauthored { return false }
        if !articles, let media = filter.media {
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
    func jamPostMatches(_ post: JamPostInfo, articles: Bool, filter: JamFilter) -> Bool {
        let files = post.kind == "article" || filter.media == nil ? [] : jamAttachments(post.postId).filter { !JamCover.isCover($0) }.map(\.kind)
        return JamFilter.matches(kind: post.kind, files: files, coauthored: !post.coauthors.isEmpty, articles: articles, filter: filter)
    }
}

/// The glass Posts | Articles control and the filter button with its menu: the same row as link and call.
struct JamFilterRow: View {
    @Binding var articles: Bool
    @Binding var filter: JamFilter
    var idPrefix = "jam-filter"

    var body: some View {
        FilterRow(first: "Posts", second: "Articles", secondSelected: $articles, activeCount: filter.activeCount, idPrefix: idPrefix) {
            if !articles {
                Section("Media") {
                    ForEach(JamFilter.Media.allCases, id: \.self) { media in
                        Toggle(media.rawValue, isOn: Binding(get: { filter.media == media }, set: { filter.media = $0 ? media : nil }))
                    }
                }
            }
            Section("Show") {
                Toggle("Co-authored", isOn: $filter.coauthored)
            }
            if filter.isOn {
                Button("Clear filters", role: .destructive) { filter = JamFilter() }
            }
        }
    }
}
