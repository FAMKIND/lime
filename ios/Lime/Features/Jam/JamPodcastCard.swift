import SwiftUI

/// The podcast card (LIME-200), Substack-style, for a recording (audio or video): **a rounded-square cover on the left; on the right the org or writer
/// and the date, the title, and a pill** with a play icon and the time. Pressing play opens the full-screen player; closing it leaves the mini player;
/// the pill then shows the state: not started `▶ 45m`, paused `▶ ── 12m left`, playing `❚❚ ── 12m left`. The pill, the mini player and the full screen
/// are views of one player (`NowPlaying`'s controller), so pausing on any of them pauses all.
struct JamPodcastCard: View {
    let post: JamPostInfo
    @Environment(ConversationStore.self) private var store
    @State private var cover: UIImage?

    var body: some View {
        let files = store.jamAttachments(post.postId)
        let file = files.first(where: { $0.kind == "audio" }) ?? files.first(where: { $0.kind == "video" })
        let writer = store.teacher(post.author)
        let org = post.displayAs == "jam" ? store.jamTitle(post.jamId) : writer.name
        let now = NowPlaying.shared
        let mine = now.item.flatMap { $0.postID == post.postId ? $0 : nil }
        VStack(alignment: .leading, spacing: 4) {
        HStack(alignment: .top, spacing: 14) {
            Button { open(file) } label: {
                PostCover(postID: post.postId).frame(width: 96, height: 96).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain).accessibilityLabel("Open player").accessibilityIdentifier("jam-audio-expand")
            VStack(alignment: .leading, spacing: 6) {
                Text([org.uppercased(), JamDates.short(post.created)].joined(separator: " \u{00B7} ")).font(Theme.font(.caption2, weight: .semibold)).foregroundStyle(Theme.textSecondary).lineLimit(1)
                    .accessibilityIdentifier("jam-card-byline-\(post.postId)")
                // Every part of the card opens the black player and plays (LIME-204); the post's page is reached from the player.
                Button { if let file { play(file, mine?.controller) } } label: {
                    Text(post.title.isEmpty ? "Recording" : post.title).font(Theme.font(.body, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(2).multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityHint("Opens the player").accessibilityIdentifier("jam-podcast-title")
                SeriesTag(post: post)
                if let file { pill(file, mine?.controller) }
            }
            .padding(.trailing, 36)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 20).padding(.top, 14)
        .contentShape(Rectangle())
        .onTapGesture { if let file { play(file, mine?.controller) } }
        // The same action row as every other card (LIME-212b).
        JamActionRow(postID: post.postId) { openWithComments() }.padding(.horizontal, 20).padding(.bottom, 6)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(file.map { "jam-audio-card-\($0.attachmentId)" } ?? "jam-podcast-card")
        .task(id: post.postId) { await loadCover(files, file) }
    }

    private func pill(_ file: JamAttachmentInfo, _ controller: PodcastController?) -> some View {
        let total = Double(file.durationMs ?? 0) / 1000
        let started = controller.map { $0.hasStarted && ($0.position > 0.5 || $0.isPlaying) } ?? false
        let playing = controller?.isPlaying ?? false
        let left = controller.map { $0.remaining } ?? total
        let words = started ? "\(Self.short(left)) left" : Self.short(total)
        return Button { play(file, controller) } label: {
            HStack(spacing: 8) {
                Image(systemName: playing ? "pause.fill" : "play.fill").font(.system(size: 12, weight: .bold))
                if started {
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.text.opacity(0.2)).frame(width: 34, height: 3)
                        Capsule().fill(Theme.text).frame(width: 34 * (controller?.fraction ?? 0), height: 3)
                    }
                    .accessibilityHidden(true)
                }
                Text(words).font(Theme.font(.footnote, weight: .semibold).monospacedDigit())
            }
            .foregroundStyle(Theme.text).padding(.horizontal, 14).frame(minHeight: 36).background(Theme.surface, in: Capsule())
            .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(playing ? "Pause, \(Self.spoken(left)) left" : started ? "Resume, \(Self.spoken(left)) left" : "Play \(post.title), \(Self.spoken(total))")
        .accessibilityIdentifier("jam-audio-play-\(file.attachmentId)")
    }

    /// "45m", "1h 5m", "40s" (the length of what is left).
    static func short(_ seconds: Double) -> String {
        let total = max(Int(seconds.rounded()), 0)
        if total < 60 { return "\(total)s" }
        let minutes = Int((Double(total) / 60).rounded(.up))
        return minutes >= 60 ? (minutes % 60 == 0 ? "\(minutes / 60)h" : "\(minutes / 60)h \(minutes % 60)m") : "\(minutes)m"
    }

    static func spoken(_ seconds: Double) -> String {
        let minutes = Int((max(seconds, 0) / 60).rounded(.up))
        return minutes <= 1 ? "1 minute" : "\(minutes) minutes"
    }

    /// Pressing play starts it and opens the full-screen player; pressing it while it plays pauses it (the same as the mini player's button).
    private func play(_ file: JamAttachmentInfo, _ controller: PodcastController?) {
        let now = NowPlaying.shared
        if let controller, controller.isPlaying { controller.pause(); return }
        guard let item = now.makeItem(for: post, store: store) else { return }
        now.start(item)
        now.item?.cover = cover
        now.showsScreen = true
        Task { await item.controller.toggle(data: { await store.jamAttachmentData(item.postID, item.file.attachmentId) }) }
    }

    private func openWithComments() {
        guard let item = NowPlaying.shared.makeItem(for: post, store: store) else { return }
        NowPlaying.shared.start(item)
        NowPlaying.shared.item?.cover = cover
        NowPlaying.shared.opensComments = true
        NowPlaying.shared.showsScreen = true
    }

    private func open(_ file: JamAttachmentInfo?) {
        guard file != nil, let item = NowPlaying.shared.makeItem(for: post, store: store) else { return }
        NowPlaying.shared.start(item)
        NowPlaying.shared.item?.cover = cover
        NowPlaying.shared.showsScreen = true
    }

    /// The cover: an audio recording's own picture; a video's poster.
    private func loadCover(_ files: [JamAttachmentInfo], _ file: JamAttachmentInfo?) async {
        if let video = file, video.kind == "video", let poster = UIImage(data: video.poster) { cover = poster; return }
        guard let art = files.first(where: JamCover.isCover), let data = await store.jamAttachmentData(post.postId, art.attachmentId) else { return }
        cover = UIImage(data: data)
    }
}
