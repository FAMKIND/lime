import SwiftUI

/// Edit decides which editor a post gets (LIME-212): a recording opens a **podcast page**, everything else the writing screen.
struct JamEditSheet: View {
    let post: JamPostInfo
    var body: some View {
        if post.kind == "record" { PodcastStudioEdit(post: post) } else { JamComposeSheet(editing: post) }
    }
}

/// Editing a podcast (LIME-227): the black studio in edit mode, with its own state.
struct PodcastStudioEdit: View {
    let post: JamPostInfo
    @State private var title = ""
    @State private var subtitle = ""
    @State private var details = ""
    @State private var cover: OutgoingAttachment?
    @State private var coauthors: [Person] = []
    @State private var postAsJam: String?
    @State private var series: SeriesInfo?
    @State private var audience = "subscribers"
    @State private var topics: [String] = []

    var body: some View {
        PodcastRecorder(title: $title, coauthors: $coauthors, camera: false, subtitle: $subtitle, details: $details, cover: $cover, postAsJam: $postAsJam, series: $series, audience: $audience, topics: $topics, editing: post)
    }
}
