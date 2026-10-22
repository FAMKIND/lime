import SwiftUI

/// What is playing now, across screens (LIME-188k): one audio recording at a time, kept while the person goes to other tabs, shown in the mini player
/// above the dock and opened in the now-playing screen.
@MainActor
@Observable
final class NowPlaying {
    static let shared = NowPlaying()

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
    /// The now-playing screen is up (from the mini player or a card's expand button).
    var showsScreen = false

    func start(_ item: Item) {
        if let current = self.item, current.controller !== item.controller { current.controller.pause() }
        self.item = item
    }

    func close() {
        item?.controller.pause()
        item = nil
        showsScreen = false
    }
}

/// An audio recording as a card (LIME-188k): its cover in the standard frame, a play button and the length. No waveform here (that is in the
/// now-playing screen). Play starts it in the mini player; the expand button opens the now-playing screen.
struct JamAudioCard: View {
    let postID: String
    let file: JamAttachmentInfo
    var coverFile: JamAttachmentInfo? = nil
    var captionFile: JamAttachmentInfo? = nil
    @Environment(ConversationStore.self) private var store
    @State private var controller: PodcastController?
    @State private var cover: UIImage?
    @State private var cues: [CaptionCue] = []

    var body: some View {
        let controller = self.controller ?? makeController()
        let post = store.jamPost(postID)
        let writer = store.teacher(post?.author ?? "")
        let playing = NowPlaying.shared.item?.controller === controller && controller.isPlaying
        ZStack {
            CoverArt(image: cover, person: writer)
            VStack {
                HStack {
                    Spacer()
                    Button { open(controller) } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).frame(width: 36, height: 36).background(.black.opacity(0.45), in: Circle()).frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Open player").accessibilityIdentifier("jam-audio-expand")
                }
                Spacer()
                HStack(spacing: 10) {
                    Button { play(controller) } label: {
                        ZStack {
                            Circle().fill(Theme.accent).frame(width: 52, height: 52)
                            Image(systemName: playing ? "pause.fill" : "play.fill").font(.system(size: 20)).foregroundStyle(Theme.accentInk)
                        }
                        .frame(width: 56, height: 56)
                    }
                    .accessibilityLabel(playing ? "Pause" : "Play").accessibilityIdentifier("jam-audio-play-\(file.attachmentId)")
                    Text(VoiceFormat.clock(Double(file.durationMs ?? 0) / 1000)).font(Theme.font(.subheadline, weight: .semibold).monospacedDigit()).foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 4).background(.black.opacity(0.45), in: Capsule())
                        .accessibilityLabel("Length \(PodcastFormat.spoken(Double(file.durationMs ?? 0) / 1000))").accessibilityIdentifier("jam-audio-length")
                    Spacer()
                }
            }
            .padding(10)
        }
        .aspectRatio(JamMedia.landscape, contentMode: .fit)
        .jamMediaClip()
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

    private func makeController() -> PodcastController {
        // The same recording keeps one controller while it is the one playing, so the card and the mini player agree.
        if let now = NowPlaying.shared.item, now.postID == postID, now.file.attachmentId == file.attachmentId { return now.controller }
        let post = store.jamPost(postID)
        let controller = PodcastController(duration: Double(file.durationMs ?? 0) / 1000, title: post?.title ?? "", artist: store.teacherName(post?.author ?? ""))
        #if DEBUG
        controller.simulated = store.isDemo
        #endif
        return controller
    }

    private func item(_ controller: PodcastController) -> NowPlaying.Item {
        let post = store.jamPost(postID)
        return NowPlaying.Item(postID: postID, file: file, controller: controller, title: post?.title.isEmpty == false ? post?.title ?? "" : "Recording",
                               subtitle: post?.subtitle.isEmpty == false ? post?.subtitle ?? "" : store.teacherName(post?.author ?? ""), cover: cover, cues: cues)
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

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Theme.surface
                LinearGradient(colors: [Theme.accent.opacity(0.35), Theme.surface], startPoint: .topLeading, endPoint: .bottomTrailing)
                AvatarView(person: person, size: 96)
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
                        CoverArt(image: item.cover, person: writer).frame(width: 40, height: 40).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        VStack(alignment: .leading, spacing: 0) {
                            Text(item.title).font(Theme.font(.subheadline, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                            Text(item.subtitle).font(Theme.caption).foregroundStyle(Theme.textSecondary).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityLabel("Now playing: \(item.title)").accessibilityHint("Opens the player").accessibilityIdentifier("audio-mini-open")
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
            .fullScreenCover(isPresented: Binding(get: { now.showsScreen }, set: { now.showsScreen = $0 })) {
                if let item = now.item {
                    JamVideoScreen(postID: item.postID, file: item.file, controller: item.controller, cues: item.cues, cover: item.cover, subtitle: item.subtitle, isAudio: true)
                }
            }
        }
    }
}
