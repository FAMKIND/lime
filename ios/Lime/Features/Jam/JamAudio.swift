import SwiftUI

/// What is playing now, across screens (LIME-188k): one audio recording at a time, kept while the person goes to other tabs, shown in the mini player
/// above the dock and opened in the now-playing screen.
@MainActor
@Observable
final class NowPlaying {
    static let shared = NowPlaying()
    init() {}

    struct Item {
        let postID: String
        let file: JamAttachmentInfo
        let controller: PodcastController
        let title: String
        let subtitle: String
        var cover: UIImage?
        var cues: [CaptionCue] = []
    }

    var item: Item?
    /// Up next (LIME-199): "Play next" puts one first, "Add to queue" last; when what plays ends, the first of these starts. On this phone only.
    var queue: [Item] = []
    /// Open the comments sheet when the screen comes up (a podcast card's 💬, LIME-204).
    var opensComments = false
    /// The now-playing screen is up (from the mini player or a card's expand button).
    var showsScreen = false

    func start(_ item: Item) {
        if let current = self.item, current.controller !== item.controller { current.controller.pause() }
        self.item = item
    }

    func close() {
        item?.controller.pause()
        item = nil
        queue = []
        showsScreen = false
    }

    /// A recording (or video) post as something to play: its first audio or video file.
    func makeItem(for post: JamPostInfo, store: ConversationStore, controller shared: PodcastController? = nil) -> Item? {
        let files = store.jamAttachments(post.postId)
        guard let file = files.first(where: { $0.kind == "audio" }) ?? files.first(where: { $0.kind == "video" }) else { return nil }
        if let now = item, now.postID == post.postId, now.file.attachmentId == file.attachmentId { return now }
        let controller = shared ?? PodcastController(duration: Double(file.durationMs ?? 0) / 1000, title: post.title, artist: store.authorName(post), isVideo: file.kind == "video")
        #if DEBUG
        if shared == nil { controller.simulated = store.isDemo }
        #endif
        return Item(postID: post.postId, file: file, controller: controller, title: post.title.isEmpty ? "Recording" : post.title,
                    subtitle: post.subtitle.isEmpty ? store.authorName(post) : post.subtitle)
    }

    func playNext(_ item: Item) { queue.removeAll { $0.postID == item.postID }; queue.insert(item, at: 0); if self.item == nil { advance() } }
    func enqueue(_ item: Item) { guard !queue.contains(where: { $0.postID == item.postID }), self.item?.postID != item.postID else { return }; queue.append(item); if self.item == nil { advance() } }

    /// Starts the first of the queue (what was playing ended).
    func advance() {
        guard !queue.isEmpty else { return }
        let next = queue.removeFirst()
        start(next)
    }
}

/// An audio recording as a card (LIME-188u, redoing 188k's): inside a rounded surface, **the cover as a 96 pt rounded square on the left; the title and
/// subtitle on the right; under them a compact player**: play or pause (the one lime control), the waveform (tap or drag to scrub), mute, and the time
/// left. At the largest text sizes the player drops under the cover and the words. The cover or the title opens now playing.
struct JamAudioCard: View {
    let postID: String
    let file: JamAttachmentInfo
    var coverFile: JamAttachmentInfo? = nil
    var captionFile: JamAttachmentInfo? = nil
    /// The reader has the title and subtitle in its own head: the card then shows the player alone beside the cover.
    var showsWords = true
    @Environment(ConversationStore.self) private var store
    @State private var controller: PodcastController?
    @State private var cover: UIImage?
    @State private var cues: [CaptionCue] = []

    var body: some View {
        let controller = self.controller ?? makeController()
        let post = store.jamPost(postID)
        let writer = store.teacher(post?.author ?? "")
        // The player is always to the right of the cover, under the words (LIME-188y); at the largest text sizes the cover and the wave shrink.
        HStack(alignment: .top, spacing: 12) {
            coverButton(controller, writer: writer)
            VStack(alignment: .leading, spacing: 8) {
                words(post, controller)
                player(controller)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: JamMedia.radius, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("jam-audio-card-\(file.attachmentId)")
        .onAppear { if self.controller == nil { self.controller = controller } }
        .task(id: coverFile?.attachmentId) {
            guard let coverFile, let data = await store.jamAttachmentData(postID, coverFile.attachmentId) else { return }
            cover = UIImage(data: data)
        }
        .task(id: captionFile?.attachmentId) {
            guard let captionFile, let data = await store.jamAttachmentData(postID, captionFile.attachmentId), let text = String(data: data, encoding: .utf8) else { return }
            cues = parseCaptions(vtt: text)
        }
    }

    @Environment(\.dynamicTypeSize) private var typeSize
    private var coverSize: CGFloat { typeSize.isAccessibilitySize ? 72 : 96 }

    private func coverButton(_ controller: PodcastController, writer: Person) -> some View {
        Button { open(controller) } label: {
            PostCover(postID: postID).frame(width: coverSize, height: coverSize).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain).accessibilityLabel("Open player").accessibilityIdentifier("jam-audio-expand")
    }

    @ViewBuilder
    private func words(_ post: JamPostInfo?, _ controller: PodcastController) -> some View {
        if showsWords, let post {
            Button { open(controller) } label: {
                VStack(alignment: .leading, spacing: 4) {
                    if !post.title.isEmpty { Text(post.title).font(Theme.font(.body, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(2).multilineTextAlignment(.leading) }
                    if !post.subtitle.isEmpty { Text(post.subtitle).font(Theme.secondary).foregroundStyle(Theme.textSecondary).lineLimit(2).multilineTextAlignment(.leading) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityHint("Opens the player").accessibilityIdentifier("jam-audio-title")
        }
    }

    /// Play or pause, the waveform to scrub, mute, and the time left.
    private func player(_ controller: PodcastController) -> some View {
        let playing = NowPlaying.shared.item?.controller === controller && controller.isPlaying
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 2) {
                Button { play(controller) } label: {
                    ZStack {
                        Circle().fill(Theme.accent).frame(width: 36, height: 36)
                        Image(systemName: playing ? "pause.fill" : "play.fill").font(.system(size: 14)).foregroundStyle(Theme.accentInk)
                    }
                    .frame(width: 40, height: 44)
                }
                .accessibilityLabel(playing ? "Pause" : "Play").accessibilityIdentifier("jam-audio-play-\(file.attachmentId)")
                WaveformScrubber(controller: controller, waveform: file.thumb, id: file.attachmentId, height: 32)
                Button { controller.muted.toggle() } label: {
                    Image(systemName: controller.muted ? "speaker.slash.fill" : "speaker.wave.2.fill").font(.system(size: 15)).foregroundStyle(Theme.text).frame(width: 36, height: 44)
                }
                .accessibilityLabel(controller.muted ? "Unmute" : "Mute").accessibilityIdentifier("jam-audio-mute-\(file.attachmentId)")
            }
            Text(VoiceFormat.clock(max(controller.duration - controller.position, 0))).font(Theme.caption.monospacedDigit()).foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .trailing).padding(.trailing, 38)
                .accessibilityLabel("Length \(PodcastFormat.spoken(Double(file.durationMs ?? 0) / 1000))").accessibilityIdentifier("jam-audio-length")
        }
    }

    private func makeController() -> PodcastController {
        // The same recording keeps one controller while it is the one playing, so the card and the mini player agree.
        if let now = NowPlaying.shared.item, now.postID == postID, now.file.attachmentId == file.attachmentId { return now.controller }
        let post = store.jamPost(postID)
        let controller = PodcastController(duration: Double(file.durationMs ?? 0) / 1000, title: post?.title ?? "", artist: store.authorName(post))
        #if DEBUG
        controller.simulated = store.isDemo
        #endif
        return controller
    }

    private func item(_ controller: PodcastController) -> NowPlaying.Item {
        let post = store.jamPost(postID)
        return NowPlaying.Item(postID: postID, file: file, controller: controller, title: post?.title.isEmpty == false ? post?.title ?? "" : "Recording",
                               subtitle: post?.subtitle.isEmpty == false ? post?.subtitle ?? "" : store.authorName(post), cover: cover, cues: cues)
    }

    private func play(_ controller: PodcastController) {
        NowPlaying.shared.start(item(controller))
        Task { await controller.toggle(data: { await store.jamAttachmentData(postID, file.attachmentId) }) }
    }

    private func open(_ controller: PodcastController) {
        NowPlaying.shared.start(item(controller))
        NowPlaying.shared.showsScreen = true
    }
}

/// The cover: the writer's picture, or (when the recording has none) their avatar on a soft tint.
struct CoverArt: View {
    let image: UIImage?
    let person: Person
    /// A post shown as a jam has the jam's tile in place of the writer's face (LIME-201).
    var org: String? = nil

    var body: some View {
        // The art fills what it is given and never asks for more (a picture that fills is bigger than its frame): it is an overlay on a clear
        // view, clipped to it (LIME-196).
        Color.clear.overlay {
            ZStack {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Theme.surface
                    LinearGradient(colors: [Theme.accent.opacity(0.35), Theme.surface], startPoint: .topLeading, endPoint: .bottomTrailing)
                    if let org { JamInitialTile(title: org, size: 72) } else { AvatarView(person: person, size: 96) }
                }
            }
        }
        .clipped()
        .accessibilityHidden(true)
    }
}

/// The mini player (LIME-188k): above the dock while an audio recording is loaded: the cover, the title and subtitle, pause and close on the right.
/// A tap on the rest opens the now-playing screen. It stays across tabs; Background playback and the lock screen come from the player.
struct AudioMiniPlayer: View {
    @Environment(ConversationStore.self) private var store

    var body: some View {
        let now = NowPlaying.shared
        let speaker = ArticleSpeaker.shared
        if now.item == nil, speaker.active {
            // An article read aloud (LIME-188p): its title, play or pause, the speed and close.
            HStack(spacing: 10) {
                Image(systemName: "headphones").frame(width: 40, height: 40).background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous)).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text(speaker.title).font(Theme.font(.subheadline, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                    Text("Listening").font(Theme.caption).foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 0)
                Button { speaker.cycleSpeed() } label: {
                    Text(speaker.rate == 1 ? "1\u{00D7}" : speaker.rate == 1.25 ? "1.25\u{00D7}" : "1.5\u{00D7}").font(Theme.font(.subheadline, weight: .bold)).foregroundStyle(Theme.text).frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Reading speed").accessibilityIdentifier("speech-mini-speed")
                Button { speaker.toggle() } label: { Image(systemName: speaker.paused ? "play.fill" : "pause.fill").font(.system(size: 18)).foregroundStyle(Theme.text).frame(width: 44, height: 44) }
                    .accessibilityLabel(speaker.paused ? "Play" : "Pause").accessibilityIdentifier("speech-mini-play")
                Button { speaker.stop() } label: { Image(systemName: "xmark").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text).frame(width: 44, height: 44) }
                    .accessibilityLabel("Stop listening").accessibilityIdentifier("speech-mini-close")
            }
            .padding(.leading, 12).padding(.trailing, 4).frame(minHeight: 56).limeGlass(in: Capsule()).padding(.horizontal, 16).padding(.bottom, 4)
        } else if let item = now.item {
            let writer = store.teacher(store.jamPost(item.postID)?.author ?? "")
            HStack(spacing: 10) {
                Button { now.showsScreen = true } label: {
                    HStack(spacing: 10) {
                        // A video podcast's thumbnail plays the video (LIME-200); VoiceOver gets the controls, not the picture.
                        ZStack {
                            PostCover(postID: item.postID)
                            if item.file.kind == "video", item.controller.player != nil, !item.controller.simulated { PlayerLayerView(player: item.controller.player, fill: true).accessibilityIdentifier("mini-video-layer") }
                        }
                        .frame(width: 40, height: 40).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous)).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(store.playerTitle(item.postID)).font(Theme.font(.subheadline, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                            Text(store.playerSubtitle(item.postID)).font(Theme.caption).foregroundStyle(Theme.textSecondary).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityLabel("Now playing: \(store.playerTitle(item.postID))").accessibilityHint("Opens the player").accessibilityIdentifier("audio-mini-open")
                Button { Task { await item.controller.toggle(data: { await store.jamAttachmentData(item.postID, item.file.attachmentId) }) } } label: {
                    Image(systemName: item.controller.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 18)).foregroundStyle(Theme.text).frame(width: 44, height: 44)
                }
                .accessibilityLabel(item.controller.isPlaying ? "Pause" : "Play").accessibilityIdentifier("audio-mini-play")
                Button { now.close() } label: {
                    Image(systemName: "xmark").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text).frame(width: 44, height: 44)
                }
                .accessibilityLabel("Close").accessibilityIdentifier("audio-mini-close")
            }
            .padding(.leading, 12).padding(.trailing, 4).frame(minHeight: 56)
            .limeGlass(in: Capsule())
            .padding(.horizontal, 16).padding(.bottom, 4)
            // An edit shows at once on the lock screen too (LIME-212).
            .onChange(of: store.playerTitle(item.postID) + "|" + store.authorName(store.jamPost(item.postID))) { _, _ in
                item.controller.updateInfo(title: store.jamPost(item.postID)?.title ?? "", artist: store.authorName(store.jamPost(item.postID)))
            }
            .onChange(of: item.controller.atEnd) { _, ended in
                // What was playing ended: the next in the queue starts.
                if ended, let next = now.queue.first { now.advance(); Task { await next.controller.toggle(data: { await store.jamAttachmentData(next.postID, next.file.attachmentId) }) } }
            }
            .fullScreenCover(isPresented: Binding(get: { now.showsScreen }, set: { now.showsScreen = $0 })) {
                if let item = now.item {
                    JamVideoScreen(postID: item.postID, file: item.file, controller: item.controller, cues: item.cues, cover: item.cover, subtitle: item.subtitle, isAudio: item.file.kind != "video")
                }
            }
        }
    }
}
