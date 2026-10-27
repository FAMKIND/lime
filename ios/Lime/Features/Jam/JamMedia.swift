import AVFoundation
import AVKit
import SwiftUI
import MediaPlayer

/// Jam media, one look (LIME-188j): corner radius 24, a portrait (4:5) or a landscape (16:9) frame, 12 pt between items.
enum JamMedia {
    static let radius: CGFloat = 24
    static let gap: CGFloat = 12
    static let portrait: CGFloat = 4.0 / 5
    static let landscape: CGFloat = 16.0 / 9
    /// An article cover card: 2/3 of the height of a portrait (4:5) photo of the same width (LIME-215b), so width ÷ height = 1.2.
    static let coverRatio: CGFloat = 1.2
    /// A frame never gets wider than this (LIME-188y): on a phone held sideways the column is capped and centred on the text margin.
    static let maxColumn: CGFloat = 600
    /// ...nor taller than this share of the screen's height, so a 4:5 photo always fits in sight.
    static let maxHeightShare: CGFloat = 0.8

    /// The size of a frame of `ratio` (width ÷ height) in a column `column` points wide on a screen `screenHeight` tall: the column's width, up to
    /// `maxColumn`; when that would be too tall the frame shrinks in proportion (the shape never changes).
    static func size(ratio: CGFloat, column: CGFloat, screenHeight: CGFloat) -> CGSize {
        var width = min(column, maxColumn)
        var height = width / ratio
        let cap = screenHeight * maxHeightShare
        if height > cap { height = cap; width = cap * ratio }
        return CGSize(width: width, height: height)
    }

    /// The text column of a card or the reader: the screen less the 20 pt margins.
    @MainActor static var column: CGFloat { UIScreen.main.bounds.width - 40 }

    /// The standard frame nearest to the picture's own shape (a square is nearer 4:5), cropped from the centre; the viewer shows the whole picture.
    static func ratio(width: UInt32?, height: UInt32?) -> CGFloat {
        guard let width, let height, width > 0, height > 0 else { return landscape }
        let own = CGFloat(width) / CGFloat(height)
        return abs(log(own / portrait)) <= abs(log(own / landscape)) ? portrait : landscape
    }
}

/// Whether a video card may start by itself (LIME-188j): only when the video is already on the phone or the phone is on Wi-Fi without Low Data
/// Mode, and the person has not turned "Auto-Play Video Previews" off (Settings → Accessibility → Motion).
enum VideoAutoplay {
    static func allows(onPhone: Bool, wifiWithoutLowData: Bool, systemAutoplay: Bool) -> Bool {
        systemAutoplay && (onPhone || wifiWithoutLowData)
    }

    @MainActor
    static func allowed(onPhone: Bool) -> Bool {
        allows(onPhone: onPhone, wifiWithoutLowData: StorageGuard.shared.isOnWiFi && !StorageGuard.shared.isLowData, systemAutoplay: UIAccessibility.isVideoAutoplayEnabled)
    }
}

/// App-wide video choices, remembered on this phone.
enum VideoPrefs {
    static let captionsKey = "lime.video.captions"
    static let autoAdvanceKey = "lime.video.autoAdvance"
    static let hiddenKey = "lime.jam.hiddenPosts"
}

private struct MediaClip: ViewModifier {
    func body(content: Content) -> some View { content.clipShape(RoundedRectangle(cornerRadius: JamMedia.radius, style: .continuous)) }
}

extension View {
    /// The rounded corners every jam picture and video shares.
    func jamMediaClip() -> some View { modifier(MediaClip()) }
}

// MARK: The card

/// A video in a feed card, a profile or the reader: the frame, muted autoplay while at least half of it shows, a mute button (and CC when it has
/// captions) top right, a thin progress line, and a tap to the full screen. No other controls here.
struct JamVideoCard: View {
    let postID: String
    let file: JamAttachmentInfo
    /// The captions file of this video in the post, if it has one (LIME-188o).
    var captionFile: JamAttachmentInfo? = nil
    /// A video podcast's card (LIME-203): a different label, and a tap hands the player to the shared full screen instead of opening its own.
    var label: String? = nil
    var onOpen: ((PodcastController) -> Void)? = nil
    @Environment(ConversationStore.self) private var store
    @AppStorage(VideoPrefs.captionsKey) private var captionsOn = true
    @State private var cues: [CaptionCue] = []
    @State private var controller: PodcastController?
    @State private var visible = false
    @State private var opening = false
    @State private var userPaused = false
    /// Turning the phone redraws the frame (LIME-188y).
    @Environment(\.verticalSizeClass) private var verticalSize

    var body: some View {
        let _ = verticalSize
        let controller = self.controller ?? makeController()
        let ratio = JamMedia.ratio(width: file.width, height: file.height)
        let screenHeight = UIScreen.main.bounds.height
        let frame = JamMedia.size(ratio: ratio, column: JamMedia.column, screenHeight: screenHeight)
        ZStack {
            Color.black
            if controller.simulated || controller.player == nil {
                if let poster = UIImage(data: file.poster) { Image(uiImage: poster).resizable().scaledToFill() }
            } else {
                PlayerLayerView(player: controller.player, fill: true)
            }
            if controller.loading { ProgressView().tint(.white) }
            else if !controller.isPlaying {
                Image(systemName: "play.circle.fill").font(.system(size: 52)).foregroundStyle(.white).shadow(radius: 4).accessibilityHidden(true)
            }
            VStack(spacing: 8) {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        round(controller.muted ? "speaker.slash.fill" : "speaker.wave.2.fill", label: controller.muted ? "Unmute" : "Mute", id: "jam-video-mute") { controller.muted.toggle() }
                        if !cues.isEmpty {
                            round(captionsOn ? "captions.bubble.fill" : "captions.bubble", label: captionsOn ? "Turn captions off" : "Turn captions on", id: "jam-video-cc") { captionsOn.toggle() }
                        }
                    }
                }
                Spacer()
                if captionsOn, let line = JamCaptions.line(at: Int(controller.position * 1000), in: cues) {
                    Text(line).font(Theme.font(.footnote, weight: .semibold)).foregroundStyle(.white).multilineTextAlignment(.center)
                        .padding(.horizontal, 10).padding(.vertical, 5).background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .accessibilityIdentifier("jam-video-caption")
                }
                // The timeline (LIME-188y): "0:16 / 1:05" and a line to drag.
                HStack(spacing: 10) {
                    Text("\(VoiceFormat.clock(controller.position)) / \(VoiceFormat.clock(controller.duration))").font(Theme.caption.monospacedDigit()).foregroundStyle(.white)
                        .accessibilityIdentifier("jam-video-time")
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.3)).frame(height: 3)
                            Capsule().fill(.white).frame(width: geo.size.width * controller.fraction, height: 3)
                        }
                        .frame(maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                            controller.seek(to: Double(min(max(value.location.x / max(geo.size.width, 1), 0), 1)) * controller.duration)
                        })
                    }
                    .frame(height: 28)
                    .accessibilityElement().accessibilityLabel("Position")
                    .accessibilityValue("\(PodcastFormat.spoken(controller.position)) of \(PodcastFormat.spoken(controller.duration))")
                    .accessibilityAdjustableAction { direction in controller.skip(by: direction == .increment ? 10 : -10) }
                    .accessibilityIdentifier("jam-video-timeline")
                }
                .padding(.horizontal, 4).padding(.bottom, 2)
            }
            .padding(.top, 10).padding(.horizontal, 10).padding(.bottom, 0)
        }
        .frame(width: frame.width, height: frame.height)
        .jamMediaClip()
        .contentShape(Rectangle())
        .onTapGesture { if let onOpen { onOpen(controller) } else { opening = true } }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label ?? "Video, \(VoiceFormat.clock(controller.duration))").accessibilityHint("Opens the video full screen")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("jam-video")
        .onGeometryChange(for: Bool.self) { proxy in
            let frame = proxy.frame(in: .global)
            let shown = frame.intersection(CGRect(x: 0, y: 0, width: 10_000, height: screenHeight))
            return !shown.isNull && frame.height > 0 && shown.height / frame.height >= 0.5
        } action: { now in
            visible = now
            Task { await autoplay(controller) }
        }
        .onAppear { if self.controller == nil { self.controller = controller } }
        .task(id: captionFile?.attachmentId) {
            guard let captionFile, let data = await store.jamAttachmentData(postID, captionFile.attachmentId), let text = String(data: data, encoding: .utf8) else { return }
            cues = parseCaptions(vtt: text)
        }
        .onDisappear { controller.pause() }
        .fullScreenCover(isPresented: $opening, onDismiss: { controller.muted = true; Task { await autoplay(controller) } }) {
            JamVideoScreen(postID: postID, file: file, controller: controller, cues: cues)
        }
    }

    private func round(_ symbol: String, label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white).frame(width: 36, height: 36).background(.black.opacity(0.55), in: Circle())
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel(label).accessibilityIdentifier(id)
    }

    private func makeController() -> PodcastController {
        let post = store.jamPost(postID)
        let controller = PodcastController(duration: Double(file.durationMs ?? 0) / 1000, title: post?.title ?? "", artist: store.authorName(post), isVideo: true)
        controller.muted = true
        #if DEBUG
        controller.simulated = store.isDemo
        #endif
        return controller
    }

    /// Plays while at least half of it shows and the rule allows; otherwise it waits with its cover and a play button.
    private func autoplay(_ controller: PodcastController) async {
        guard !opening else { return }
        if visible {
            guard VideoAutoplay.allowed(onPhone: file.available) else { return }
            await controller.play { await store.jamAttachmentData(postID, file.attachmentId) }
        } else {
            controller.pause()
        }
    }
}

enum JamCaptions {
    /// The caption line showing at this time, if any.
    static func line(at ms: Int, in cues: [CaptionCue]) -> String? {
        cues.first { Int($0.startMs) <= ms && ms < Int($0.endMs) }?.text
    }

    /// The captions file that belongs to the post's n-th attachment, if there is one.
    static func file(for index: Int, in files: [JamAttachmentInfo]) -> JamAttachmentInfo? {
        files.first { $0.mime == "text/vtt" && captionMediaIndex(name: $0.name) == UInt32(index) }
    }
}

// MARK: Full screen

/// The video full screen (LIME-188j; 188k reuses this layout for audio): dark, the video at its own shape, ±10 s and play on a tap, the writer and
/// the post's words under it (tap them to read them in full over the video), the timeline and the action pill at the bottom, ⋯ and AirPlay on top.
struct JamVideoScreen: View {
    let postID: String
    let file: JamAttachmentInfo
    let controller: PodcastController
    var cues: [CaptionCue] = []
    /// For a recording (LIME-188k): the cover where the video would be, a subtitle, and the audio's own controls; it keeps playing when this closes.
    var cover: UIImage? = nil
    var subtitle = ""
    var isAudio = false
    @Environment(ConversationStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(VideoPrefs.captionsKey) private var captionsOn = true
    @AppStorage(VideoPrefs.autoAdvanceKey) private var autoAdvance = true
    @State private var textOpen = false
    /// The comments under the player (LIME-189d), on black.
    @State private var commenting = false
    @State private var editingPost: JamPostInfo?
    @State private var confirmingDelete = false
    @State private var sharing = false
    @State private var reporting: ReportTarget?
    @State private var transcript = false
    @State private var watching: Bool?
    @State private var fullScreen = false
    @State private var upNext = false
    @State private var noVideoHint = false
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var current: (postID: String, file: JamAttachmentInfo, controller: PodcastController)?

    private var active: (postID: String, file: JamAttachmentInfo, controller: PodcastController) { current ?? (postID, file, controller) }
    /// Watch (the picture) or Listen (the cover; the sound goes on). An audio podcast has only Listen.
    private var watch: Bool { isAudio ? false : (watching ?? true) }

    /// The post's captions, read from its .vtt when the player came up without them (the shared path from a card, the mini player or the queue, LIME-230).
    @State private var loadedCues: [CaptionCue] = []
    private var shownCues: [CaptionCue] { cues.isEmpty ? loadedCues : cues }

    var body: some View {
        let item = active
        let post = store.jamPost(item.postID)
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar(post)
                if typeSize.isAccessibilitySize {
                    // Large text: the page scrolls, the stage never overlaps the words.
                    ScrollView { VStack(spacing: 16) { stage(item, post).frame(height: 260); lower(item, post) }.padding(.horizontal, 20) }
                } else {
                    stage(item, post).frame(maxHeight: .infinity)
                    lower(item, post).padding(.horizontal, 20)
                }
                bottomBar(item, post)
            }
            if textOpen, let post {
                TextOver(post: post, writer: store.teacher(post.author), close: { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { textOpen = false } })
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .preferredColorScheme(.dark)
        .gesture(DragGesture(minimumDistance: 30).onEnded { if $0.translation.height > 120, abs($0.translation.width) < 80, !textOpen { close() } })
        .fullScreenCover(item: $editingPost) { JamEditSheet(post: $0) }
        .fullScreenCover(isPresented: $fullScreen) {
            JamVideoFullScreen(postID: item.postID, file: item.file, controller: item.controller, cues: shownCues, captionsOn: captionsOn) { fullScreen = false }
        }
        .confirmationDialog("Delete this post for everyone?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete post", role: .destructive) { Task { _ = await store.deleteJamPost(active.postID); NowPlaying.shared.close(); dismiss() } }.accessibilityIdentifier("jam-video-delete-confirm")
            Button("Cancel", role: .cancel) {}
        } message: { Text("Subscribers' copies are removed.") }
        .sheet(isPresented: $commenting) {
            if let post {
                // Black with a little see-through, not the glass (LIME-228); the shared comments component in dark mode.
                ScrollView { JamEngagementSection(post: post).padding(20) }
                    .preferredColorScheme(.dark).presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
                    .presentationBackground(Color.black.opacity(0.88))
            }
        }
        .sheet(isPresented: $upNext) { UpNextSheet() }
        .task(id: item.file.attachmentId) {
            loadedCues = []
            guard cues.isEmpty || current != nil,
                  let vtt = JamCaptions.file(for: store.jamAttachments(item.postID).firstIndex { $0.attachmentId == item.file.attachmentId } ?? 0, in: store.jamAttachments(item.postID)),
                  let data = await store.jamAttachmentData(item.postID, vtt.attachmentId), let text = String(data: data, encoding: .utf8) else { return }
            loadedCues = parseCaptions(vtt: text)
        }
        .onAppear {
            item.controller.muted = false
            if NowPlaying.shared.opensComments { NowPlaying.shared.opensComments = false; commenting = true }
        }
        .onChange(of: active.controller.atEnd) { _, ended in if ended, !isAudio { advance() } }
        .onChange(of: watch) { _, on in active.controller.setPicture(on) }
        .sheet(isPresented: $sharing) { if let post { JamShareSheet(post: post) } }
        .reportSheet($reporting)
        .sheet(isPresented: $transcript) { TranscriptSheet(cues: shownCues) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("jam-video-screen")
    }

    // MARK: Parts (LIME-235: the black player, Liquid Glass throughout)

    /// Closes the player (a mini player stays) and opens the post's page.
    private func viewPost() {
        let id = active.postID
        NowPlaying.shared.showsScreen = false
        dismiss()
        Task { try? await Task.sleep(for: .milliseconds(450)); store.jamPath.append(JamPostRoute(postID: id)) }
    }

    /// ⌄ (left) · Listen | Watch (centre) · ⋯ (right), all glass.
    private func topBar(_ post: JamPostInfo?) -> some View {
        HStack(spacing: 10) {
            glassCircle("chevron.down", label: "Close", id: "jam-video-close") { close() }
            Spacer(minLength: 0)
            modeToggle
            Spacer(minLength: 0)
            Menu {
                if let post, post.author == store.meProvider().id {
                    Section {
                        Button { editingPost = post } label: { Label("Edit", systemImage: "pencil") }.accessibilityIdentifier("jam-video-edit")
                    }
                }
                Section {
                    Button { sharing = true } label: { Label("Share in lime\u{2026}", systemImage: "square.and.arrow.up") }.accessibilityIdentifier("jam-video-share")
                    // The post's own page (description, captions, files, comments) is reached from here (LIME-204).
                    Button { viewPost() } label: { Label("View post", systemImage: "doc.text") }.accessibilityIdentifier("jam-video-viewpost")
                }
                Section {
                    if !shownCues.isEmpty, !isAudio { Toggle(isOn: $captionsOn) { Label("Closed captions", systemImage: "captions.bubble") }.accessibilityIdentifier("jam-video-captions-toggle") }
                    if !shownCues.isEmpty { Button { transcript = true } label: { Label("Transcript", systemImage: "text.alignleft") }.accessibilityIdentifier("jam-video-transcript") }
                    if !isAudio { Toggle(isOn: $autoAdvance) { Label("Auto-advance", systemImage: "forward.end") }.accessibilityIdentifier("jam-video-autoadvance") }
                }
                Section {
                    Button { hide(post) } label: { Label("Hide post", systemImage: "eye.slash") }.accessibilityIdentifier("jam-video-hide")
                    if let post, post.author != store.meProvider().id {
                        Button(role: .destructive) { reporting = store.reportTarget(post: post) } label: { Label("Report", systemImage: "flag") }.accessibilityIdentifier("jam-video-report")
                    }
                }
                if let post, post.author == store.meProvider().id {
                    Section {
                        Button(role: .destructive) { confirmingDelete = true } label: { Label("Delete post", systemImage: "trash") }.accessibilityIdentifier("jam-video-delete")
                    }
                }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white).frame(width: 44, height: 44).limeGlass(in: Circle())
            }
            .accessibilityLabel("More").accessibilityIdentifier("jam-video-more")
        }
        .padding(.horizontal, 16).padding(.top, 6)
    }

    /// A glass segmented toggle, waveform | video: Listen keeps the sound with the cover on the stage; Watch shows the picture. An audio-only podcast has
    /// no picture, so its Watch half is dimmed.
    private var modeToggle: some View {
        // The system's segmented control (glass on iOS 26; a segmented control for VoiceOver). An audio podcast has no picture: Watch gives way to Listen.
        Picker("Listen or watch", selection: Binding(get: { watch }, set: { if $0 && isAudio { noVideoHint = true } else { watching = $0 } })) {
            Image(systemName: "waveform").accessibilityLabel("Listen").tag(false)
            Image(systemName: "video").accessibilityLabel(isAudio ? "Watch, no video" : "Watch").tag(true)
        }
        .pickerStyle(.segmented).frame(width: 128)
        .accessibilityIdentifier("jam-player-mode")
    }

    private func glassCircle(_ symbol: String, label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white).frame(width: 44, height: 44).limeGlass(in: Circle())
        }
        .buttonStyle(.plain).accessibilityLabel(label).accessibilityIdentifier(id)
    }

    // The stage

    @ViewBuilder
    private func stage(_ item: (postID: String, file: JamAttachmentInfo, controller: PodcastController), _ post: JamPostInfo?) -> some View {
        GeometryReader { geo in
            if watch {
                let ratio = JamVideoRatio.of(item.file)
                let landscape = ratio >= 1
                let paused = !item.controller.isPlaying
                video(item)
                    .aspectRatio(ratio, contentMode: .fit)
                    .frame(maxWidth: landscape ? .infinity : geo.size.width * 0.7, maxHeight: geo.size.height)
                    .clipShape(RoundedRectangle(cornerRadius: paused || !landscape ? 20 : 0, style: .continuous))
                    .frame(width: geo.size.width, height: geo.size.height)
                    .contentShape(Rectangle())
                    .onTapGesture { fullScreen = true }
                    .accessibilityElement(children: .ignore).accessibilityLabel("Video").accessibilityHint("Opens it full screen")
                    .accessibilityAddTraits(.isButton).accessibilityIdentifier("jam-video-stage")
            } else {
                PostCover(postID: post?.postId ?? active.postID)
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .frame(maxWidth: geo.size.width * 0.82, maxHeight: geo.size.height)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .accessibilityLabel("Cover").accessibilityHidden(false).accessibilityIdentifier("jam-audio-cover")
            }
        }
        .frame(minHeight: 120)
    }

    private func video(_ item: (postID: String, file: JamAttachmentInfo, controller: PodcastController)) -> some View {
        Group {
            if item.controller.simulated || item.controller.player == nil {
                if let poster = UIImage(data: item.file.poster) { Image(uiImage: poster).resizable().scaledToFit() } else { Rectangle().fill(.white.opacity(0.08)).aspectRatio(16.0 / 9, contentMode: .fit) }
            } else {
                PlayerLayerView(player: item.controller.player)
            }
        }
    }

    // Under the stage

    @ViewBuilder
    private func lower(_ item: (postID: String, file: JamAttachmentInfo, controller: PodcastController), _ post: JamPostInfo?) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if captionsOn, let line = JamCaptions.line(at: Int(item.controller.position * 1000), in: shownCues) {
                Text(line).font(Theme.font(.subheadline, weight: .semibold)).foregroundStyle(.white).multilineTextAlignment(.center)
                    .padding(.horizontal, 12).padding(.vertical, 6).background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .frame(maxWidth: .infinity).accessibilityIdentifier("jam-video-caption")
            }
            if isAudio {
                controls(item.controller, circle: true)
                if let post { writerRow(post, withDate: false); titleBlock(post) }
                timeline(item.controller)
            } else {
                if let post {
                    // One block: the cover on the left; the writer and date, a one-line title and a one-line subtitle on the right.
                    HStack(alignment: .top, spacing: 12) {
                        PostCover(postID: post.postId).frame(width: 110, height: 110).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous)).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            writerRow(post, withDate: true)
                            titleBlock(post, lines: 1)
                        }
                    }
                }
                timeline(item.controller)
                controls(item.controller, circle: false)
                VolumeSlider().frame(height: 34).accessibilityLabel("Volume").accessibilityIdentifier("jam-video-volume")
            }
        }
        .padding(.top, 8)
    }

    /// 1.5× · ⟲10 · play/pause · ⟳30 · captions.
    private func controls(_ controller: PodcastController, circle: Bool) -> some View {
        HStack(spacing: 0) {
            Button { controller.cycleRate() } label: {
                Text(controller.rate == 1.5 ? "1.5\u{00D7}" : "\(Int(controller.rate))\u{00D7}").font(Theme.font(.subheadline, weight: .bold)).foregroundStyle(.white)
                    .frame(minWidth: 52, minHeight: 44).contentShape(Rectangle())
            }
            .accessibilityLabel("Playback speed, \(controller.rate == 1.5 ? "1.5" : "\(Int(controller.rate))")\u{00D7}").accessibilityIdentifier("jam-video-speed")
            Spacer(minLength: 0)
            skipButton("gobackward.10", "Skip back 10 seconds", id: "jam-video-back10") { controller.skip(by: -10) }
            Spacer(minLength: 0)
            Button { Task { await controller.toggle(data: { await store.jamAttachmentData(active.postID, active.file.attachmentId) }) } } label: {
                Image(systemName: controller.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 30)).foregroundStyle(.white)
                    .frame(width: 72, height: 72).background { if circle { Circle().fill(.clear).limeGlass(in: Circle()) } }
            }
            .buttonStyle(.plain).accessibilityLabel(controller.isPlaying ? "Pause" : "Play").accessibilityIdentifier("jam-video-play")
            Spacer(minLength: 0)
            skipButton("goforward.30", "Skip forward 30 seconds", id: "jam-video-fwd30") { controller.skip(by: 30) }
            Spacer(minLength: 0)
            Button { if isAudio { transcript = true } else { captionsOn.toggle() } } label: {
                Image(systemName: isAudio ? "text.quote" : (captionsOn ? "captions.bubble.fill" : "captions.bubble")).font(.system(size: 20)).foregroundStyle(.white.opacity(shownCues.isEmpty ? 0.35 : 1))
                    .frame(width: 52, height: 44).contentShape(Rectangle())
            }
            .disabled(shownCues.isEmpty)
            .accessibilityLabel(isAudio ? "Transcript" : (captionsOn ? "Captions, on" : "Captions, off")).accessibilityIdentifier("jam-video-captions")
        }
    }

    private func skipButton(_ symbol: String, _ label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 26)).foregroundStyle(.white).frame(width: 52, height: 52).contentShape(Rectangle())
        }
        .accessibilityLabel(label).accessibilityIdentifier(id)
    }

    private func writerRow(_ post: JamPostInfo, withDate: Bool) -> some View {
        let writer = store.teacher(post.author)
        return HStack(spacing: 10) {
            if let org = store.orgName(post) { JamInitialTile(title: org, size: 36).accessibilityHidden(true) } else { AvatarView(person: writer, size: 36).accessibilityHidden(true) }
            VStack(alignment: .leading, spacing: 0) {
                Text(store.authorName(post)).font(Theme.font(.subheadline, weight: .semibold)).foregroundStyle(.white)
                if withDate { Text(JamDates.text(post.created)).font(Theme.caption).foregroundStyle(.white.opacity(0.7)) }
            }
            Spacer(minLength: 0)
            if !store.isFollowing(post.jamId), post.author != store.meProvider().id {
                Button { Task { if let page = await store.jamPage(of: post.author) { await store.subscribe(to: page) } } } label: {
                    Text("Subscribe").font(Theme.font(.subheadline, weight: .semibold)).foregroundStyle(Theme.accentInk).padding(.horizontal, 14).frame(minHeight: 36).background(Theme.accent, in: Capsule())
                }
                .accessibilityIdentifier("jam-video-subscribe")
            }
        }
    }

    /// The title (bold) and the subtitle; a tap reads the whole post over the player.
    private func titleBlock(_ post: JamPostInfo, lines: Int = 2) -> some View {
        let subtitle = store.playerSubtitle(post.postId)
        return Button { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { textOpen = true } } label: {
            VStack(alignment: .leading, spacing: 2) {
                if !post.title.isEmpty { Text(post.title).font(Theme.font(.title3, weight: .bold)).foregroundStyle(.white).lineLimit(lines) }
                if !subtitle.isEmpty { Text(subtitle).font(Theme.body).foregroundStyle(.white.opacity(0.75)).lineLimit(lines) }
            }
            .multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityHint("Reads the whole post").accessibilityIdentifier("jam-video-text")
    }

    private func timeline(_ controller: PodcastController) -> some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.3)).frame(height: 4)
                    Capsule().fill(.white).frame(width: geo.size.width * controller.fraction, height: 4)
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { controller.seek(to: Double(min(max($0.location.x / max(geo.size.width, 1), 0), 1)) * controller.duration) })
            }
            .frame(height: 28)
            .accessibilityElement().accessibilityLabel("Position")
            .accessibilityValue("\(PodcastFormat.spoken(controller.position)) of \(PodcastFormat.spoken(controller.duration))")
            .accessibilityAdjustableAction { direction in controller.skip(by: direction == .increment ? 10 : -10) }
            .accessibilityIdentifier("jam-video-timeline")
            HStack {
                Text(VoiceFormat.clock(controller.position)).accessibilityIdentifier("jam-video-elapsed")
                Spacer()
                Text(VoiceFormat.clock(controller.duration))
            }
            .font(Theme.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.8)).accessibilityHidden(true)
        }
    }

    // The bottom bar

    /// AirPlay · ♥ 💬 remix share · Up next, all glass.
    private func bottomBar(_ item: (postID: String, file: JamAttachmentInfo, controller: PodcastController), _ post: JamPostInfo?) -> some View {
        HStack(spacing: 10) {
            AirPlayButton().frame(width: 44, height: 44).limeGlass(in: Circle()).accessibilityLabel("AirPlay").accessibilityIdentifier("jam-video-airplay")
            JamActionPill(dark: true, share: { sharing = true }, postID: item.postID, comment: { commenting = true })
            glassCircle("list.bullet", label: "Up next", id: "jam-video-upnext") { upNext = true }
        }
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 10)
    }

    // MARK: Doing

    private func close() {
        // A video stops when its screen closes; a recording goes on in the mini player.
        if !isAudio { active.controller.pause(); controller.pause() }
        if isAudio { NowPlaying.shared.showsScreen = false }
        dismiss()
    }

    /// At the end, the next video post in the feed plays (when Auto-advance is on).
    private func advance() {
        guard autoAdvance else { return }
        let feed = store.jamFeed
        guard let at = feed.firstIndex(where: { $0.postId == active.postID }) else { return }
        for post in feed[(at + 1)...] {
            guard let next = store.jamAttachments(post.postId).first(where: { $0.kind == "video" }) else { continue }
            let c = PodcastController(duration: Double(next.durationMs ?? 0) / 1000, title: post.title, artist: store.authorName(post), isVideo: true)
            #if DEBUG
            c.simulated = store.isDemo
            #endif
            current = (post.postId, next, c)
            Task { await c.play { await store.jamAttachmentData(post.postId, next.attachmentId) } }
            return
        }
    }

    private func hide(_ post: JamPostInfo?) {
        guard let post else { return }
        store.hideJamPost(post.postId)
        close()
    }
}

/// The post's words over the video, on a dark veil; a tap or a swipe down folds them back.
private struct TextOver: View {
    @Environment(ConversationStore.self) private var store
    let post: JamPostInfo
    let writer: Person
    let close: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.7).ignoresSafeArea().onTapGesture(perform: close)
                .accessibilityLabel("Close the post text").accessibilityAddTraits(.isButton).accessibilityIdentifier("jam-video-text-open")
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !post.title.isEmpty { Text(post.title).font(Theme.font(.title3, weight: .bold)).foregroundStyle(.white) }
                    if !post.plain.isEmpty { Text(post.plain).font(Theme.body).foregroundStyle(.white) }
                    Text("\(store.authorName(post)) \u{00B7} \(JamDates.text(post.created))").font(Theme.caption).foregroundStyle(.white.opacity(0.7))
                }
                .padding(24).frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.top, 80)
        }
        .gesture(DragGesture(minimumDistance: 30).onEnded { if $0.translation.height > 80 { close() } })
        .accessibilityAddTraits(.isModal)
    }
}

/// ♥ · comment · remix · share. Inert until LIME-189 (as on the cards), except Share, which sends the post to a chat.
struct JamActionPill: View {
    var dark = false
    var share: (() -> Void)? = nil
    /// With a post, the heart and the comment count are live (LIME-189c).
    var postID: String? = nil
    var comment: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 0) {
            if let postID {
                JamHeartButton(postID: postID, size: 20, dark: dark)
                JamCommentCount(postID: postID, size: 20, dark: dark) { comment?() }
            }
            ForEach(postID == nil ? [("heart", "like"), ("bubble.left", "comment"), ("arrow.2.squarepath", "remix"), ("square.and.arrow.up", "share")] : [("arrow.2.squarepath", "remix"), ("square.and.arrow.up", "share")], id: \.1) { icon, label in
                let live = label == "share" && share != nil
                Button { if live { share?() } } label: {
                    Image(systemName: icon).font(.system(size: 20)).frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain).foregroundStyle(dark ? Color.white.opacity(live ? 1 : 0.5) : Theme.text.opacity(live ? 1 : 0.5))
                .accessibilityLabel(label).accessibilityHint(live ? "Sends the post to a chat" : "Coming soon").accessibilityIdentifier("jam-pill-\(label)")
            }
        }
        .padding(.horizontal, 8).limeGlass(in: Capsule())
    }
}

/// The bar under a jam photo in the full-screen viewer (LIME-188y): ♥ · 💬 · remix · share, like the one under the reader; only Share works until
/// LIME-189.
struct JamViewerBar: View {
    let postID: String
    @Environment(ConversationStore.self) private var store
    @State private var sharing = false

    var body: some View {
        JamActionPill(dark: true, share: { sharing = true }, postID: postID)
            .padding(.horizontal, 24).padding(.bottom, 8)
            .sheet(isPresented: $sharing) { if let post = store.jamPost(postID) { JamShareSheet(post: post) } }
    }
}

/// AirPlay's own button.
struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.activeTintColor = .white
        view.tintColor = .white
        view.prioritizesVideoDevices = true
        return view
    }

    func updateUIView(_ view: AVRoutePickerView, context: Context) {}
}

/// "Share in lime": pick a chat; it gets the post's title and first words (a post is end-to-end encrypted, so there is no link; the people who can
/// read it are its subscribers).
struct JamShareSheet: View {
    let post: JamPostInfo
    @Environment(ConversationStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(store.forwardTargets, id: \.id) { conversation in
                Button { send(to: conversation) } label: {
                    Text(conversation.id == store.selfChatID ? "Note to self" : conversation.title).font(Theme.body).foregroundStyle(Theme.text).frame(minHeight: 44, alignment: .leading)
                }
                .accessibilityIdentifier("jam-share-\(conversation.id)")
            }
            .listStyle(.plain)
            .navigationTitle("Share in lime").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }

    private func send(to conversation: Conversation) {
        let writer = store.authorName(post)
        let words = [post.title, String(post.plain.prefix(200))].filter { !$0.isEmpty }.joined(separator: "\n")
        let text = "\(writer)\u{2019}s post on jam: \(words)"
        Task {
            await store.sendNow(text, in: conversation.id)
            store.showBanner("Shared")
            dismiss()
        }
    }
}

/// The whole of a video's or recording's words, readable (and for VoiceOver) in one place.
struct TranscriptSheet: View {
    let cues: [CaptionCue]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(cues.map(\.text).joined(separator: "\n")).font(Theme.body).foregroundStyle(Theme.text).frame(maxWidth: .infinity, alignment: .leading).padding(20)
                    .accessibilityIdentifier("jam-transcript-text")
            }
            .background(Theme.canvas)
            .navigationTitle("Transcript").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}


/// The system's volume slider.
struct VolumeSlider: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: .zero)
        view.showsRouteButton = false
        view.tintColor = .white
        return view
    }

    func updateUIView(_ view: MPVolumeView, context: Context) {}
}

/// Up next (LIME-199) as a sheet from the player's bottom bar: what plays after this, in order.
struct UpNextSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if NowPlaying.shared.queue.isEmpty {
                    Text("Nothing is queued. Use \u{201C}Add to queue\u{201D} on a podcast.").font(Theme.body).foregroundStyle(.white.opacity(0.7)).accessibilityIdentifier("jam-upnext-empty")
                }
                ForEach(NowPlaying.shared.queue, id: \.postID) { item in
                    Text(item.title).font(Theme.body).foregroundStyle(.white).frame(minHeight: 44, alignment: .leading).listRowBackground(Color.white.opacity(0.08))
                        .accessibilityIdentifier("jam-upnext-\(item.postID)")
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Up next").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .preferredColorScheme(.dark).presentationDetents([.medium, .large]).presentationBackground(Color.black.opacity(0.88))
        .accessibilityIdentifier("jam-upnext")
    }
}

/// The video full screen (LIME-235): black, ✕ and sound as glass circles, the video centred at full width while the phone is upright (a landscape video
/// letterboxed) and filling the screen when it is turned to match; a tap shows ⟲10 · play · ⟳10 and the writer, title and progress, which go after 3 s
/// while it plays.
struct JamVideoFullScreen: View {
    let postID: String
    let file: JamAttachmentInfo
    let controller: PodcastController
    let cues: [CaptionCue]
    let captionsOn: Bool
    let close: () -> Void
    @Environment(ConversationStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsControls = true
    @State private var hideTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { geo in
            let deviceLandscape = geo.size.width > geo.size.height
            let ratio = JamVideoRatio.of(file)
            let videoLandscape = ratio >= 1
            let fills = deviceLandscape == videoLandscape
            ZStack {
                Color.black.ignoresSafeArea()
                picture(fills: fills, ratio: ratio)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped().ignoresSafeArea(fills ? .all : [])
                    .contentShape(Rectangle())
                    .onTapGesture { toggle() }
                    .accessibilityElement(children: .ignore).accessibilityLabel("Video").accessibilityHint("Shows the controls").accessibilityAddTraits(.isButton)
                    .accessibilityIdentifier("jam-fullscreen-video")
                if let line = captionsOn ? JamCaptions.line(at: Int(controller.position * 1000), in: cues) : nil {
                    Text(line).font(Theme.font(.subheadline, weight: .semibold)).foregroundStyle(.white).multilineTextAlignment(.center)
                        .padding(.horizontal, 12).padding(.vertical, 6).background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, showsControls ? 190 : 40)
                }
                VStack {
                    HStack {
                        circle("xmark", "Close", id: "jam-fullscreen-close") { controller.muted = true; close() }
                        Spacer()
                        circle(controller.muted ? "speaker.slash.fill" : "speaker.wave.2.fill", controller.muted ? "Sound off" : "Sound on", id: "jam-fullscreen-sound") { controller.muted.toggle(); show() }
                    }
                    .padding(.horizontal, 16).padding(.top, 8)
                    Spacer()
                }
                if showsControls {
                    HStack(spacing: 28) {
                        circle("gobackward.10", "Skip back 10 seconds", size: 56, id: "jam-fullscreen-back10") { controller.skip(by: -10); show() }
                        circle(controller.isPlaying ? "pause.fill" : "play.fill", controller.isPlaying ? "Pause" : "Play", size: 72, id: "jam-fullscreen-play") {
                            Task { await controller.toggle(data: { await store.jamAttachmentData(postID, file.attachmentId) }); show() }
                        }
                        circle("goforward.10", "Skip forward 10 seconds", size: 56, id: "jam-fullscreen-fwd10") { controller.skip(by: 10); show() }
                    }
                    .transition(.opacity)
                    VStack(alignment: .leading, spacing: 10) {
                        Spacer()
                        if let post = store.jamPost(postID) { info(post) }
                        progress
                    }
                    .padding(.horizontal, 20).padding(.bottom, 12).transition(.opacity)
                }
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .onAppear { show() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("jam-fullscreen")
    }

    @ViewBuilder private func picture(fills: Bool, ratio: CGFloat) -> some View {
        Group {
            if controller.simulated || controller.player == nil {
                if let poster = UIImage(data: file.poster) { Image(uiImage: poster).resizable().aspectRatio(contentMode: fills ? .fill : .fit) }
                else { Rectangle().fill(.white.opacity(0.08)).aspectRatio(ratio, contentMode: fills ? .fill : .fit) }
            } else {
                PlayerLayerView(player: controller.player, fill: fills)
            }
        }
    }

    /// The same block as under the stage: the cover on the left; the writer and date, a one-line title and a one-line subtitle on the right.
    private func info(_ post: JamPostInfo) -> some View {
        HStack(alignment: .top, spacing: 12) {
            PostCover(postID: post.postId).frame(width: 84, height: 84).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous)).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    AvatarView(person: store.teacher(post.author), size: 28).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(store.authorName(post)).font(Theme.font(.subheadline, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                        Text(JamDates.text(post.created)).font(Theme.caption).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                    }
                }
                if !post.title.isEmpty { Text(post.title).font(Theme.font(.subheadline, weight: .bold)).foregroundStyle(.white).lineLimit(1) }
                let subtitle = store.playerSubtitle(post.postId)
                if !subtitle.isEmpty { Text(subtitle).font(Theme.caption).foregroundStyle(.white.opacity(0.75)).lineLimit(1) }
            }
            Spacer(minLength: 0)
        }
    }

    /// A glass capsule with the timeline and elapsed / total.
    private var progress: some View {
        HStack(spacing: 10) {
            Text(VoiceFormat.clock(controller.position)).font(Theme.caption.monospacedDigit()).foregroundStyle(.white)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.3)).frame(height: 4)
                    Capsule().fill(.white).frame(width: geo.size.width * controller.fraction, height: 4)
                }
                .frame(maxHeight: .infinity).contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { controller.seek(to: Double(min(max($0.location.x / max(geo.size.width, 1), 0), 1)) * controller.duration); show() })
            }
            .frame(height: 28)
            .accessibilityElement().accessibilityLabel("Position")
            .accessibilityValue("\(PodcastFormat.spoken(controller.position)) of \(PodcastFormat.spoken(controller.duration))")
            .accessibilityAdjustableAction { controller.skip(by: $0 == .increment ? 10 : -10) }
            .accessibilityIdentifier("jam-fullscreen-timeline")
            Text(VoiceFormat.clock(controller.duration)).font(Theme.caption.monospacedDigit()).foregroundStyle(.white)
        }
        .padding(.horizontal, 16).frame(minHeight: 44).limeGlass(in: Capsule())
    }

    private func circle(_ symbol: String, _ label: String, size: CGFloat = 44, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: size > 50 ? 26 : 16, weight: .semibold)).foregroundStyle(.white).frame(width: size, height: size).limeGlass(in: Circle())
        }
        .buttonStyle(.plain).accessibilityLabel(label).accessibilityIdentifier(id)
    }

    private func toggle() {
        if showsControls { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { showsControls = false } } else { show() }
    }

    /// Shows the controls; while playing they go after 3 seconds.
    private func show() {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { showsControls = true }
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled, controller.isPlaying { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) { showsControls = false } }
        }
    }
}


enum JamVideoRatio {
    /// Width over height of a video file (16:9 when unknown).
    static func of(_ file: JamAttachmentInfo) -> CGFloat {
        guard let w = file.width, let h = file.height, h > 0 else { return 16.0 / 9 }
        return CGFloat(w) / CGFloat(h)
    }
}
