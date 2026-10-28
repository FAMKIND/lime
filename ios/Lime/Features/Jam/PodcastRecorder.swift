@preconcurrency import AVFoundation
import SwiftUI

/// The camera for a video recording (LIME-188g): a capture session with the front or back camera and the microphone, writing one movie file.
@MainActor
@Observable
final class PodcastCapture: NSObject, AVCaptureFileOutputRecordingDelegate {
    nonisolated(unsafe) let session = AVCaptureSession()
    private let output = AVCaptureMovieFileOutput()
    private(set) var ready = false
    private(set) var front = true
    private(set) var recording = false
    private(set) var paused = false
    private var finished: CheckedContinuation<URL?, Never>?
    private var configured = false

    /// Asks for the camera and the microphone and sets the session up. `false` when either is not allowed or there is no camera.
    func prepare() async -> Bool {
        if ready { return true }
        guard await AVCaptureDevice.requestAccess(for: .video), await AVCaptureDevice.requestAccess(for: .audio) else { return false }
        if !configured {
            session.beginConfiguration()
            session.sessionPreset = .high
            guard let camera = Self.camera(front: front), let input = try? AVCaptureDeviceInput(device: camera), session.canAddInput(input) else { session.commitConfiguration(); return false }
            session.addInput(input)
            if let mic = AVCaptureDevice.default(for: .audio), let micInput = try? AVCaptureDeviceInput(device: mic), session.canAddInput(micInput) { session.addInput(micInput) }
            guard session.canAddOutput(output) else { session.commitConfiguration(); return false }
            session.addOutput(output)
            session.commitConfiguration()
            configured = true
        }
        let session = self.session
        DispatchQueue.global(qos: .userInitiated).async { session.startRunning() }
        ready = true
        return true
    }

    func stopSession() {
        let session = self.session
        DispatchQueue.global(qos: .userInitiated).async { if session.isRunning { session.stopRunning() } }
        ready = false
    }

    /// The torch (the flash light) for a dark room; the front camera has none.
    var hasTorch: Bool { session.inputs.compactMap { $0 as? AVCaptureDeviceInput }.first { $0.device.hasMediaType(.video) }?.device.hasTorch ?? false }

    func setTorch(_ on: Bool) {
        guard let device = session.inputs.compactMap({ $0 as? AVCaptureDeviceInput }).first(where: { $0.device.hasMediaType(.video) })?.device, device.hasTorch else { return }
        try? device.lockForConfiguration()
        device.torchMode = on ? .on : .off
        device.unlockForConfiguration()
    }

    func flip() {
        guard configured, !recording, let camera = Self.camera(front: !front), let input = try? AVCaptureDeviceInput(device: camera) else { return }
        session.beginConfiguration()
        for old in session.inputs.compactMap({ $0 as? AVCaptureDeviceInput }) where old.device.hasMediaType(.video) { session.removeInput(old) }
        if session.canAddInput(input) { session.addInput(input); front.toggle() }
        session.commitConfiguration()
    }

    private static func camera(front: Bool) -> AVCaptureDevice? {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: front ? .front : .back)
    }

    func start() {
        guard ready, !recording else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("lime-podcast-\(UUID().uuidString).mov")
        output.startRecording(to: url, recordingDelegate: self)
        recording = true
        paused = false
    }

    /// Pausing a movie needs iOS 18; before that the recorder shows no pause button for video.
    static var canPause: Bool { if #available(iOS 18, *) { true } else { false } }

    func pause() {
        guard recording, !paused else { return }
        if #available(iOS 18, *) { output.pauseRecording(); paused = true }
    }

    func resume() {
        guard recording, paused else { return }
        if #available(iOS 18, *) { output.resumeRecording(); paused = false }
    }

    func finish() async -> URL? {
        guard recording else { return nil }
        return await withCheckedContinuation { continuation in
            finished = continuation
            output.stopRecording()
        }
    }

    nonisolated func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        Task { @MainActor in
            self.recording = false
            self.paused = false
            // A recording that stopped on an error can still be a good file; use it if it exists.
            let usable = FileManager.default.fileExists(atPath: outputFileURL.path)
            self.finished?.resume(returning: usable ? outputFileURL : nil)
            self.finished = nil
        }
    }
}

/// The camera picture, edge to edge.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    final class Host: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> Host {
        let view = Host()
        view.preview.session = session
        view.preview.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ view: Host, context: Context) {}
}

/// Plays the take you just recorded, in the studio (LIME-227): audio or video, with a play button and a position you can drag.
@MainActor
@Observable
final class TakePlayer {
    private(set) var player: AVPlayer?
    private(set) var playing = false
    private(set) var position: Double = 0
    private(set) var duration: Double = 0
    private var observer: Any?
    private var file: URL?

    func load(_ clip: OutgoingAttachment) {
        unload()
        let ext = clip.mime.hasPrefix("video/") ? "mp4" : "m4a"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("lime-take-\(UUID().uuidString).\(ext)")
        guard (try? clip.bytes.write(to: url)) != nil else { return }
        file = url
        let player = AVPlayer(url: url)
        self.player = player
        duration = Double(clip.durationMs ?? 0) / 1000
        observer = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                self.position = time.seconds.isFinite ? time.seconds : 0
                if self.duration > 0, self.position >= self.duration - 0.05 { self.playing = false; self.player?.pause(); self.player?.seek(to: .zero); self.position = 0 }
            }
        }
    }

    func toggle() {
        guard let player else { return }
        if playing { player.pause() } else {
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try? AVAudioSession.sharedInstance().setActive(true)
            player.play()
        }
        playing.toggle()
    }

    func seek(_ seconds: Double) {
        position = seconds
        player?.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func unload() {
        if let observer { player?.removeTimeObserver(observer) }
        observer = nil
        player?.pause()
        player = nil
        playing = false
        position = 0
        if let file { try? FileManager.default.removeItem(at: file) }
        file = nil
    }
}

/// A player's picture with no controls (the studio draws its own).
struct TakeVideoView: UIViewRepresentable {
    let player: AVPlayer?

    final class Host: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    func makeUIView(context: Context) -> Host {
        let view = Host()
        view.playerLayer.videoGravity = .resizeAspectFill
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ view: Host, context: Context) { view.playerLayer.player = player }
}

/// The studio (LIME-227): a podcast or video recorded on the black player's own layout, as a viewer will see it. The stage (the cover for audio, the camera
/// for video) at the top with the record button where the play button will be, the sound drawn **under** it and never over it, the timer, and under that
/// where viewers read them the title, subtitle and description, each a line with a pencil. After a take the stage plays it; Re-record asks first.
/// For audio inside an article (`forArticle`) it is just the stage and the controls, and Next puts the clip in the text.
struct PodcastRecorder: View {
    @Binding var title: String
    @Binding var coauthors: [Person]
    let camera: Bool
    /// Audio for an article (LIME-188n): no title, sharing line or co-hosts; Next puts the clip in the text.
    var forArticle = false
    @Binding var subtitle: String
    @Binding var details: String
    @Binding var cover: OutgoingAttachment?
    /// Who the post is from (you, or a jam of yours).
    @Binding var postAsJam: String?
    /// The series the podcast belongs to, if any (LIME-210h).
    @Binding var series: SeriesInfo?
    let attach: (OutgoingAttachment) -> Void
    /// The studio's Post: hands the take back and posts it at once (when not set, Next only hands the take back).
    var post: ((OutgoingAttachment) -> Void)?
    /// A podcast of mine being edited (LIME-227): the same studio with a pencil by each line, a camera badge on the cover and Re-record; Cancel · Update on top.
    var editing: JamPostInfo?
    init(title: Binding<String>, coauthors: Binding<[Person]>, camera: Bool, forArticle: Bool = false,
         subtitle: Binding<String> = .constant(""), details: Binding<String> = .constant(""), cover: Binding<OutgoingAttachment?> = .constant(nil),
         postAsJam: Binding<String?> = .constant(nil), series: Binding<SeriesInfo?> = .constant(nil), post: ((OutgoingAttachment) -> Void)? = nil, editing: JamPostInfo? = nil,
         attach: @escaping (OutgoingAttachment) -> Void = { _ in }) {
        _title = title; _coauthors = coauthors; self.camera = camera; self.forArticle = forArticle
        _subtitle = subtitle; _details = details; _cover = cover; _postAsJam = postAsJam; _series = series; self.post = post; self.editing = editing; self.attach = attach
    }

    @Environment(ConversationStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var cameraOn = false
    @State private var voice = VoiceRecorder()
    @State private var capture = PodcastCapture()
    @State private var take = TakePlayer()
    @State private var clip: OutgoingAttachment?
    @State private var shown = false
    @State private var preparing = false
    @State private var seconds: TimeInterval = 0
    @State private var simulatedPaused = false
    @State private var simulatedVideo: TimeInterval?
    @State private var ticker: Task<Void, Never>?
    @State private var problem: String?
    @State private var choosingHosts = false
    @State private var postingAs = false
    @State private var pickingCover = false
    @State private var confirmingRerecord = false
    @State private var confirmingDiscard = false
    @State private var torchOn = false
    // The details page (LIME-239b)
    @State private var descModel = RichComposerModel()
    @State private var trimStart: Double = 0
    @State private var trimEnd: Double = 0
    @State private var editClip: OutgoingAttachment?
    @State private var headingOpen = false
    // Edit mode (LIME-227)
    @State private var reRecording = false
    @State private var removeCover = false
    @State private var saving = false
    @State private var initialHosts: [String] = []
    @FocusState private var focus: Line?
    private enum Line: Hashable { case title, subtitle, details }

    /// A video is kept to chats' three minutes so it fits a jam file (24 MB); audio can run an hour (32 kbps is about 14 MB).
    private var limit: TimeInterval { cameraOn ? VideoProcessing.maxSeconds : VoiceRecorder.podcastSeconds }
    private var demo: Bool {
        #if DEBUG
        store.isDemo
        #else
        false
        #endif
    }
    private var isRecording: Bool { cameraOn ? (demo ? simulatedVideo != nil : capture.recording) : voice.phase != .idle }
    private var isPaused: Bool { cameraOn ? (demo ? simulatedPaused : capture.paused) : voice.paused }
    private var canPause: Bool { !cameraOn || demo || PodcastCapture.canPause }
    private var elapsed: TimeInterval { cameraOn ? seconds : voice.elapsed }
    private var coverImage: UIImage? { cover.flatMap { UIImage(data: $0.bytes) } }
    private var jamTitle: String? { postAsJam.flatMap { id in store.jamsMine.first { $0.jamId == id }?.title } }
    private var canPost: Bool { clip != nil && !title.trimmingCharacters(in: .whitespaces).isEmpty }
    /// The stage's height: about a third of the screen, never more, so the words under it are never pushed off.
    private var stageHeight: CGFloat { min(UIScreen.main.bounds.height * 0.34, 300) }

    /// The recorder screen (LIME-239a) is shown until there is a take; an article's audio, a take and an edit of a post use the words page.
    private var showsDetails: Bool { !forArticle && (clip != nil || (editing != nil && !reRecording)) }

    var body: some View {
        Group {
            if forArticle { wordsPage } else if showsDetails { detailsPage } else { recordScreen }
        }
        .preferredColorScheme(showsDetails ? nil : .dark)
        .sheet(isPresented: $choosingHosts) { JamCoauthorPicker(selected: $coauthors, title: "Add co-hosts") }
        .sheet(isPresented: $postingAs) { PostAsSheet(selection: $postAsJam) }
        .fullScreenCover(isPresented: $pickingCover) {
            MediaLibraryPicker(limit: 1, onPick: { images, _ in
                pickingCover = false
                if let image = images.first, let made = AttachmentProcessing.photo(image, name: JamCover.name) { cover = made; removeCover = false }
            }, onCancel: { pickingCover = false }).ignoresSafeArea()
        }
        .confirmSheet("Record again?", isPresented: $confirmingRerecord) {
            Button("Record again", role: .destructive) { again() }.accessibilityIdentifier("podcast-rerecord-confirm")
            Button("Keep it", role: .cancel) {}
        } message: { Text("This take will be discarded.") }
        .confirmSheet("Discard this recording?", isPresented: $confirmingDiscard) {
            Button("Discard", role: .destructive) { cancel() }.accessibilityIdentifier("podcast-discard-confirm")
            Button("Keep recording", role: .cancel) {}
        } message: { Text("What you recorded is thrown away.") }
        .alert("Can\u{2019}t record", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(problem ?? "") }
        .onAppear {
            guard !shown else { return }
            shown = true
            voice.podcast = true
            #if DEBUG
            voice.simulated = store.isDemo
            #endif
            if let editing { prefill(editing); return }
            if camera { Task { await turnCamera(on: true) } }
        }
        .onDisappear { teardown() }
        .onChange(of: voice.elapsed) { _, now in if !cameraOn, now >= VoiceRecorder.podcastSeconds { Task { await stop() } } }
        .onChange(of: seconds) { _, now in if cameraOn, now >= VideoProcessing.maxSeconds { Task { await stop() } } }
    }

    // MARK: The recorder (LIME-239a)

    /// Video: the camera full screen. Audio: a soft blur of the avatar's colours with the lime-shaped avatar in the middle and the sound on both sides.
    private var recordScreen: some View {
        ZStack {
            if !cameraOn { audioCentre }
            VStack(spacing: 0) {
                recordTop
                Spacer(minLength: 0)
                recordBottom
            }
        }
        // The picture behind is a background, so a photo that fills never changes the size of what is laid over it.
        .background { recordBackground }
        .accessibilityElement(children: .contain).accessibilityIdentifier("podcast-recorder")
    }

    @ViewBuilder private var recordBackground: some View {
        if cameraOn {
            cameraLayer.ignoresSafeArea()
        } else {
            ZStack {
                Color.black
                Image(uiImage: HeroDefault.tone(store.meProvider().tone, dark: true)).resizable().scaledToFill().blur(radius: 50).opacity(0.85)
                Color.black.opacity(0.35)
            }
            .ignoresSafeArea()
        }
    }

    /// The avatar with the sound on both sides: bars from the microphone level (a plain level meter with Reduce Motion).
    private var audioCentre: some View {
        HStack(spacing: 14) {
            sound(mirrored: false)
            LimeShapedAvatar(person: store.meProvider(), size: 150).accessibilityHidden(true).accessibilityIdentifier("podcast-avatar")
            sound(mirrored: true)
        }
        .padding(.horizontal, 16)
        .accessibilityHidden(true)
    }

    @ViewBuilder private func sound(mirrored: Bool) -> some View {
        let active = voice.phase != .idle && !voice.paused
        if reduceMotion {
            let level = CGFloat(voice.levels.last ?? 0)
            Capsule().fill(.white.opacity(0.6)).frame(width: 8, height: 8 + 70 * (active ? level : 0)).frame(width: 60, height: 90)
        } else {
            LiveBars(levels: voice.levels, active: active, count: 12).frame(width: 78, height: 90).scaleEffect(x: mirrored ? -1 : 1)
        }
    }

    /// ✕ · "Preview mode" (a red timer while recording) · ⚡ (video only).
    private var recordTop: some View {
        HStack {
            glass("xmark", "Close", id: "podcast-cancel") { if isRecording || elapsed > 0 { confirmingDiscard = true } else { cancel() } }
            Spacer()
            Group {
                if isRecording {
                    Text(VoiceFormat.clock(elapsed)).font(Theme.font(.subheadline, weight: .semibold).monospacedDigit()).foregroundStyle(.white)
                        .padding(.horizontal, 16).frame(minHeight: 36).background(.red, in: Capsule())
                        .accessibilityLabel("Recording").accessibilityValue(PodcastFormat.spoken(elapsed)).accessibilityIdentifier("podcast-timer")
                } else {
                    Text("Preview mode").font(Theme.font(.subheadline, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 16).frame(minHeight: 36).limeGlass(in: Capsule()).accessibilityIdentifier("podcast-mode-pill")
                }
            }
            Spacer()
            if cameraOn {
                glass(torchOn ? "bolt.fill" : "bolt.slash.fill", torchOn ? "Flash on" : "Flash off", id: "podcast-torch") { torchOn.toggle(); capture.setTorch(torchOn) }
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, 16).padding(.top, 8)
    }

    /// Switch to the other mode · the shutter · flip (video only).
    private var recordBottom: some View {
        HStack {
            glass(cameraOn ? "video.fill" : "waveform", cameraOn ? "Switch to audio" : "Switch to video", id: "podcast-camera", size: 52) { Task { await turnCamera(on: !cameraOn) } }
                .disabled(isRecording || preparing).opacity(isRecording ? 0.35 : 1)
            Spacer()
            shutter
            Spacer()
            if cameraOn {
                glass("arrow.triangle.2.circlepath.camera", "Flip camera", id: "podcast-flip", size: 52) { capture.flip() }
                    .disabled(isRecording).opacity(isRecording ? 0.35 : 1)
            } else {
                Color.clear.frame(width: 52, height: 52)
            }
        }
        .padding(.horizontal, 28).padding(.bottom, 20).padding(.top, 8)
    }

    /// The big white shutter; while recording a red circle with a white stop square.
    private var shutter: some View {
        Button { Task { if isRecording { await stop() } else { await begin() } } } label: {
            ZStack {
                Circle().strokeBorder(.white, lineWidth: 4).frame(width: 84, height: 84)
                if isRecording {
                    Circle().fill(.red).frame(width: 68, height: 68)
                    RoundedRectangle(cornerRadius: 5).fill(.white).frame(width: 26, height: 26)
                } else {
                    Circle().fill(.white).frame(width: 68, height: 68)
                }
            }
        }
        .disabled(preparing).accessibilityLabel(isRecording ? "Stop recording" : "Record").accessibilityIdentifier(isRecording ? "podcast-stop" : "podcast-record")
    }

    private func glass(_ symbol: String, _ label: String, id: String, size: CGFloat = 44, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: size > 48 ? 22 : 18, weight: .semibold)).foregroundStyle(.white).frame(width: size, height: size).limeGlass(in: Circle())
        }
        .buttonStyle(.plain).accessibilityLabel(label).accessibilityIdentifier(id)
    }

    // MARK: The details page (LIME-239b)

    /// What the preview and the trim bar work on: the new take, or (editing) the recording the post already has.
    private var previewClip: OutgoingAttachment? { clip ?? editClip }
    private var isVideoTake: Bool { previewClip?.mime.hasPrefix("video/") ?? cameraOn }
    private var previewDuration: Double { take.duration > 0 ? take.duration : Double(previewClip?.durationMs ?? 0) / 1000 }
    private var trimmed: Bool { previewDuration > 0 && (trimStart > 0.05 || trimEnd < previewDuration - 0.05) }
    private var canSend: Bool { editing != nil ? canUpdate : canPost && !saving }

    private var detailsPage: some View {
        VStack(spacing: 0) {
            detailsTop
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        preview.frame(maxWidth: .infinity)
                        trimBar
                        detailsPostRow
                        SeriesChip(series: $series)
                        detailsWords
                    }
                    .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 24)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: focus) { _, line in
                    guard let line else { return }
                    withAnimation { proxy.scrollTo(line, anchor: .center) }
                }
            }
            detailsBar
        }
        .background(Theme.canvas.ignoresSafeArea())
        .task(id: previewClip?.durationMs ?? 0) {
            if let c = previewClip, take.player == nil { take.load(c) }
            if trimEnd == 0 || trimEnd > previewDuration { trimEnd = previewDuration }
        }
        .task {
            // Editing: the recording the post already has, for the preview and the trim.
            guard let editing, editClip == nil, clip == nil else { return }
            let files = store.jamAttachments(editing.postId)
            if let media = files.first(where: { $0.kind == "video" || $0.kind == "audio" }), let data = await store.jamAttachmentData(editing.postId, media.attachmentId) {
                editClip = OutgoingAttachment(bytes: data, name: media.name, mime: media.mime, width: media.width, height: media.height, durationMs: media.durationMs, thumb: media.thumb, poster: media.poster)
            }
            try? await Task.sleep(for: .milliseconds(300))
            if !details.isEmpty { descModel.textView?.attributedText = ComposerDocument.attributed(fromMarkdown: details, post: true); descModel.didEdit() }
        }
        .onChange(of: descModel.plainText) { _, _ in details = descModel.markdown() }
    }

    /// ‹ (back to the recorder, asking first; when editing, closes) · Post or Update, both glass.
    private var detailsTop: some View {
        HStack {
            Button { if editing != nil { cancel() } else { confirmingRerecord = true } } label: {
                Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.text).frame(width: 44, height: 44).limeGlass(in: Circle())
            }
            .buttonStyle(.plain).accessibilityLabel(editing != nil ? "Close" : "Back to the recorder").accessibilityIdentifier("podcast-back")
            Spacer()
            if editing != nil {
                Menu {
                    Button { confirmingRerecord = true } label: { Label("Record again", systemImage: "arrow.counterclockwise") }.accessibilityIdentifier("podcast-again")
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.text).frame(width: 44, height: 44).limeGlass(in: Circle())
                }
                .accessibilityLabel("More").accessibilityIdentifier("podcast-more")
            }
            Button { Task { editing != nil ? await update() : await sendNow() } } label: {
                Text(editing != nil ? (saving ? "Saving\u{2026}" : "Update") : (preparing ? "Getting ready\u{2026}" : "Post")).font(Theme.font(.body, weight: .semibold)).foregroundStyle(Theme.text)
                    .padding(.horizontal, 18).frame(minHeight: 44).limeGlass(in: Capsule()).opacity(canSend ? 1 : 0.45)
            }
            .buttonStyle(.plain).disabled(!canSend || preparing).accessibilityIdentifier(editing != nil ? "podcast-update" : "podcast-post")
        }
        .padding(.horizontal, 16).padding(.top, 8)
    }

    /// The recording as a rounded preview (a video at its own shape; audio: the cover or the avatar with a small play button); a tap plays or pauses it.
    private var preview: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        let ratio: CGFloat = {
            guard isVideoTake, let w = previewClip?.width, let h = previewClip?.height, h > 0 else { return isVideoTake ? 3.0 / 4 : 1 }
            return CGFloat(w) / CGFloat(h)
        }()
        return Button { take.toggle() } label: {
            ZStack {
                if isVideoTake {
                    if take.player != nil, !demo { TakeVideoView(player: take.player) }
                    else {
                        LinearGradient(colors: [Color(white: 0.28), Color(white: 0.1)], startPoint: .top, endPoint: .bottom)
                        Image(systemName: "person.fill").font(.system(size: 70)).foregroundStyle(.white.opacity(0.25))
                    }
                } else {
                    if let editing, coverImage == nil, !removeCover { PostCover(postID: editing.postId) } else { CoverArt(image: coverImage, person: store.meProvider(), org: jamTitle) }
                }
                Image(systemName: take.playing ? "pause.fill" : "play.fill").font(.system(size: 22)).foregroundStyle(.white)
                    .frame(width: 52, height: 52).background(.black.opacity(0.45), in: Circle()).opacity(take.playing ? 0.0 : 1)
            }
            .aspectRatio(ratio, contentMode: .fit)
            .frame(maxWidth: isVideoTake ? 260 : 240)
            .clipShape(shape)
        }
        .buttonStyle(.plain).accessibilityLabel(take.playing ? "Pause recording" : "Play recording").accessibilityIdentifier("podcast-play")
    }

    /// A glass capsule with the recording's waveform (or frames) and a handle at each end to set where it starts and ends.
    private var trimBar: some View {
        let duration = max(previewDuration, 0.1)
        return VStack(spacing: 6) {
            GeometryReader { geo in trimTrack(width: geo.size.width, height: geo.size.height, duration: duration) }
                .frame(height: 48)
            HStack {
                Text(VoiceFormat.clock(trimStart)).accessibilityHidden(true)
                Spacer()
                Text(VoiceFormat.clock(max(trimEnd - trimStart, 0))).accessibilityLabel("Length").accessibilityValue(PodcastFormat.spoken(max(trimEnd - trimStart, 0))).accessibilityIdentifier("podcast-trim-length")
                Spacer()
                Text(VoiceFormat.clock(trimEnd)).accessibilityHidden(true)
            }
            .font(Theme.caption.monospacedDigit()).foregroundStyle(Theme.textSecondary)
        }
    }

    private func trimSpan(_ width: CGFloat) -> CGFloat { max(width - 32, 1) }

    private func moveStart(toX x: CGFloat, width: CGFloat, duration: Double) {
        let seconds = Double((x - 8) / trimSpan(width)) * duration
        trimStart = min(max(seconds, 0), max(trimEnd - 1, 0))
    }

    private func moveEnd(toX x: CGFloat, width: CGFloat, duration: Double) {
        let seconds = Double((x - 24) / trimSpan(width)) * duration
        trimEnd = max(min(seconds, duration), min(trimStart + 1, duration))
    }

    private func trimTrack(width: CGFloat, height: CGFloat, duration: Double) -> some View {
        let span = trimSpan(width)
        let x0 = CGFloat(trimStart / duration) * span
        let x1 = 16 + CGFloat(trimEnd / duration) * span
        let kept = max(x1 + 16 - x0, 32)
        return ZStack(alignment: .leading) {
            Capsule().fill(.clear).limeGlass(in: Capsule())
            waveform(width: width).padding(.horizontal, 16).opacity(0.55)
            RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.text, lineWidth: 2.5).frame(width: kept, height: height - 4).offset(x: x0).allowsHitTesting(false)
            trimHandle("chevron.left", "Start", value: trimStart, id: "podcast-trim-start", x: x0,
                       drag: { moveStart(toX: $0, width: width, duration: duration) }, step: { trimStart = min(max(trimStart + $0, 0), max(trimEnd - 1, 0)) })
            trimHandle("chevron.right", "End", value: trimEnd, id: "podcast-trim-end", x: x1,
                       drag: { moveEnd(toX: $0, width: width, duration: duration) }, step: { trimEnd = max(min(trimEnd + $0, duration), min(trimStart + 1, duration)) })
        }
        .coordinateSpace(name: "trim")
    }

    private func trimHandle(_ symbol: String, _ label: String, value: Double, id: String, x: CGFloat, drag: @escaping (CGFloat) -> Void, step: @escaping (Double) -> Void) -> some View {
        handleView(symbol).offset(x: x)
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("trim")).onChanged { drag($0.location.x) })
            .accessibilityElement().accessibilityLabel(label).accessibilityValue(VoiceFormat.clock(value)).accessibilityIdentifier(id)
            .accessibilityAdjustableAction { step($0 == .increment ? 1 : -1) }
    }

    private func handleView(_ symbol: String) -> some View {
        Image(systemName: symbol).font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.canvas).frame(width: 16, height: 44)
            .background(Theme.text, in: RoundedRectangle(cornerRadius: 6, style: .continuous)).contentShape(Rectangle().inset(by: -8))
    }

    /// Bars from the recording's own waveform (audio); a plain strip for video.
    private func waveform(width: CGFloat) -> some View {
        let samples = previewClip.map { Array($0.thumb) } ?? []
        return Canvas { context, size in
            let count = 60
            let gap: CGFloat = 3
            let barWidth = max(2, (size.width - gap * CGFloat(count - 1)) / CGFloat(count))
            for i in 0..<count {
                let level: CGFloat = samples.isEmpty || isVideoTake ? 0.35 : CGFloat(samples[min(samples.count - 1, i * samples.count / count)]) / 255
                let h = max(4, size.height * (0.15 + 0.7 * level))
                context.fill(Path(roundedRect: CGRect(x: CGFloat(i) * (barWidth + gap), y: (size.height - h) / 2, width: barWidth, height: h), cornerRadius: barWidth / 2), with: .color(Theme.text))
            }
        }
        .frame(height: 30)
    }

    /// Who it is from, the co-hosts and the cover, on the light page.
    private var detailsPostRow: some View {
        HStack(spacing: 8) {
            Button { postingAs = true } label: {
                HStack(spacing: 8) {
                    if let jamTitle { BylineAvatar(people: [store.meProvider()] + coauthors, jam: jamTitle, size: 32).frame(width: 42, height: 32, alignment: .leading) } else { AvatarView(person: store.meProvider(), size: 30).accessibilityHidden(true) }
                    Text(jamTitle ?? store.meProvider().name).font(Theme.font(.subheadline, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                    Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.textSecondary)
                }
                .frame(minHeight: 44)
            }
            .buttonStyle(.plain).accessibilityLabel("Posting as \(jamTitle ?? store.meProvider().name)").accessibilityIdentifier("podcast-post-as")
            Button { choosingHosts = true } label: {
                Image(systemName: "person.badge.plus").font(.system(size: 18)).foregroundStyle(Theme.textSecondary).frame(width: 44, height: 44)
            }
            .accessibilityLabel(coauthors.isEmpty ? "Add co-host" : "Co-hosts: \(coauthors.map(\.name).joined(separator: ", "))").accessibilityIdentifier("podcast-hosts")
            Spacer(minLength: 0)
            let hasCover = cover != nil || (editing != nil && !removeCover && store.jamAttachments(editing?.postId ?? "").contains(where: JamCover.isCover))
            Button { pickingCover = true } label: {
                Label(hasCover ? "Edit cover" : "Add cover", systemImage: "photo").font(Theme.secondary).foregroundStyle(Theme.text).lineLimit(1).fixedSize()
                    .padding(.horizontal, 14).frame(minHeight: 44).background(Theme.surface, in: Capsule())
            }
            .accessibilityIdentifier("podcast-add-cover")
        }
    }

    /// Title, subtitle and the description (the article editor's styles: headings, bold, links).
    private var detailsWords: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("", text: $title, prompt: Text("Add a title").foregroundColor(Theme.placeholderLarge), axis: .vertical)
                .font(Theme.font(.title2, weight: .bold)).foregroundStyle(Theme.text).lineLimit(1...3)
                .focused($focus, equals: .title).submitLabel(.next).onSubmit { focus = .subtitle }
                .onChange(of: title) { _, now in if now.count > 120 { title = String(now.prefix(120)) } }
                .accessibilityLabel("Title").accessibilityIdentifier("podcast-title").id(Line.title)
            TextField("", text: $subtitle, prompt: Text("Add a subtitle").foregroundColor(Theme.placeholder), axis: .vertical)
                .font(Theme.font(.body)).foregroundStyle(Theme.textSecondary).lineLimit(1...2)
                .focused($focus, equals: .subtitle).submitLabel(.next).onSubmit { descModel.focus() }
                .onChange(of: subtitle) { _, now in if now.count > 160 { subtitle = String(now.prefix(160)) } }
                .accessibilityLabel("Subtitle").accessibilityIdentifier("podcast-subtitle").id(Line.subtitle)
            ZStack(alignment: .topLeading) {
                RichComposerField(model: descModel, selfSizing: true)
                    .onAppear { descModel.hasText = false; descModel.isPost = true }
                if !descModel.hasText {
                    Text("Write a description\u{2026}").font(Theme.body).foregroundStyle(Theme.placeholder).padding(.leading, 4).padding(.top, 8).allowsHitTesting(false).accessibilityHidden(true)
                }
            }
            .frame(minHeight: 120).accessibilityIdentifier("podcast-description").id(Line.details)
        }
    }

    /// Aa · H · undo · redo … keyboard, above the keyboard.
    private var detailsBar: some View {
        VStack(spacing: 0) {
            if descModel.showsStrip { FormattingToolbar(model: descModel).transition(.opacity) }
            HStack(spacing: 0) {
                barButton("Aa", "Formatting", id: "podcast-format") { descModel.formattingTapped() }
                let level = descModel.format.heading
                barButton(level == 0 ? "H" : "H\(level)", "Heading", id: "podcast-heading") { headingOpen = true }
                    .popover(isPresented: $headingOpen, arrowEdge: .bottom) {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(0...6, id: \.self) { n in
                                Button { descModel.setHeading(n == 0 ? nil : n); headingOpen = false } label: {
                                    Text(n == 0 ? "Normal text" : "Heading \(n)").foregroundStyle(Theme.text).padding(.horizontal, 14).frame(minHeight: 44, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .accessibilityIdentifier("podcast-heading-\(n)")
                            }
                        }
                        .frame(width: 200).presentationCompactAdaptation(.popover)
                    }
                barIcon("arrow.uturn.backward", "Undo", id: "podcast-undo") { descModel.undo() }.disabled(!descModel.format.canUndo).opacity(descModel.format.canUndo ? 1 : 0.35)
                barIcon("arrow.uturn.forward", "Redo", id: "podcast-redo") { descModel.redo() }.disabled(!descModel.format.canRedo).opacity(descModel.format.canRedo ? 1 : 0.35)
                Spacer(minLength: 0)
                barIcon(descModel.editing ? "keyboard.chevron.compact.down" : "keyboard", descModel.editing ? "Hide keyboard" : "Show keyboard", id: "podcast-keyboard") { descModel.toggleKeyboard() }
            }
            .padding(.horizontal, 16).frame(minHeight: 48).background(.bar)
        }
    }

    private func barButton(_ text: String, _ label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(text).font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.text).frame(width: 44, height: 44) }
            .accessibilityLabel(label).accessibilityIdentifier(id)
    }

    private func barIcon(_ symbol: String, _ label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 19)).foregroundStyle(Theme.text).frame(width: 44, height: 44) }
            .accessibilityLabel(label).accessibilityIdentifier(id)
    }

    /// Post: the take is trimmed to the chosen range first (a re-export of that part only), then handed back and posted.
    private func sendNow() async {
        guard var current = clip, canPost else { return }
        if trimmed {
            preparing = true
            if !demo, let cut = await TrimExport.trim(current, start: trimStart, end: trimEnd) { current = cut }
            else if demo { current.durationMs = UInt32(max(trimEnd - trimStart, 0) * 1000) }
            preparing = false
            clip = current
        }
        details = descModel.markdown()
        if post != nil { post?(current); dismiss() } else { attach(current); dismiss() }
    }

    // MARK: The words page (the article's audio keeps this)


    private var wordsPage: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                if forArticle { stage; Spacer(minLength: 0) }
                else {
                    // The stage and the words scroll together: with the keyboard up the page scrolls the line being edited into view, above the keyboard,
                    // and the stage just scrolls up under the top bar; nothing is ever laid over it.
                    ScrollViewReader { proxy in
                        ScrollView {
                            stage
                            words.padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 24)
                        }
                        .scrollDismissesKeyboard(.interactively)
                        .onChange(of: focus) { _, line in
                            guard let line else { return }
                            withAnimation { proxy.scrollTo(line, anchor: .center) }
                        }
                    }
                }
                bottom
            }
        }
    }

    // MARK: The stage

    /// Where the cover or the camera is, as in the player: the record button sits where the play button will be; after a take it plays it.
    private var stage: some View {
        VStack(spacing: 10) {
            ZStack {
                if cameraOn { cameraLayer } else { coverLayer }
                stageButton
            }
            .frame(width: cameraOn ? stageHeight * 0.75 : stageHeight, height: stageHeight)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .onTapGesture { focus = nil }   // a tap on the stage puts the keyboard away
            .accessibilityElement(children: .contain)
            // Under the stage, never over it: the sound while recording, the position while playing the take.
            if clip != nil { scrubber } else if !cameraOn { LiveBars(levels: voice.levels, active: voice.phase != .idle && !voice.paused).frame(height: 56).padding(.horizontal, 24).accessibilityHidden(true) }
            Text(VoiceFormat.clock(clip != nil ? take.position : elapsed)).font(Theme.font(.title2, weight: .semibold).monospacedDigit()).foregroundStyle(.white)
                .accessibilityLabel("Time").accessibilityValue(PodcastFormat.spoken(clip != nil ? take.position : elapsed)).accessibilityIdentifier("podcast-time")
        }
        .padding(.top, 8)
    }

    /// Audio: the cover you chose, or your picture on a soft tone (the card's default), as a viewer will see it.
    private var coverLayer: some View {
        Group {
            if let editing, coverImage == nil, !removeCover { PostCover(postID: editing.postId) }
            else { CoverArt(image: coverImage, person: store.meProvider(), org: jamTitle) }
        }
            .accessibilityHidden(true)
            // A marker of exactly the stage's box (a picture that fills reports its own, larger, frame).
            .overlay { Color.clear.accessibilityElement().accessibilityLabel("Cover").accessibilityIdentifier("podcast-audio-layer") }
    }

    /// Video: the camera in the video frame (a made-up picture in the demo, which has no camera); after the take, the take.
    private var cameraLayer: some View {
        ZStack {
            if clip != nil, take.player != nil { TakeVideoView(player: take.player) }
            else if demo {
                LinearGradient(colors: [Color(white: 0.28), Color(white: 0.1)], startPoint: .top, endPoint: .bottom)
                Image(systemName: "person.fill").font(.system(size: 80)).foregroundStyle(.white.opacity(0.25))
            } else {
                CameraPreview(session: capture.session)
            }
        }
        .accessibilityLabel("Camera preview").accessibilityIdentifier("podcast-camera-layer")
    }

    /// Record, pause/stop, or (after a take) play: on the stage where the player's play button is.
    @ViewBuilder
    private var stageButton: some View {
        if clip != nil {
            Button { take.toggle() } label: {
                Image(systemName: take.playing ? "pause.fill" : "play.fill").font(.system(size: 30)).foregroundStyle(.white).frame(width: 72, height: 72).background(.black.opacity(0.45), in: Circle())
            }
            .accessibilityLabel(take.playing ? "Pause" : "Play").accessibilityIdentifier("podcast-play")
        } else if editing != nil && !reRecording {
            EmptyView()
        } else if isRecording {
            HStack(spacing: 24) {
                if canPause { circle(isPaused ? "mic.fill" : "pause.fill", isPaused ? "Resume recording" : "Pause recording", id: "podcast-pause", size: 52) { togglePause() } }
                Button { Task { await stop() } } label: {
                    ZStack {
                        Circle().strokeBorder(.white, lineWidth: 4).frame(width: 72, height: 72)
                        RoundedRectangle(cornerRadius: 6).fill(.red).frame(width: 28, height: 28)
                    }
                    .background(.black.opacity(0.35), in: Circle())
                }
                .accessibilityLabel("Stop recording").accessibilityIdentifier("podcast-stop")
            }
        } else {
            Button { Task { await begin() } } label: {
                ZStack {
                    Circle().strokeBorder(.white, lineWidth: 4).frame(width: 72, height: 72)
                    Circle().fill(.red).frame(width: 56, height: 56)
                }
                .background(.black.opacity(0.35), in: Circle())
            }
            .disabled(preparing).accessibilityLabel("Record").accessibilityIdentifier("podcast-record")
        }
    }

    /// The take's position: a slider and its length.
    private var scrubber: some View {
        HStack(spacing: 10) {
            Slider(value: Binding(get: { take.position }, set: { take.seek($0) }), in: 0...max(take.duration, 0.1))
                .tint(.white).accessibilityLabel("Position").accessibilityIdentifier("podcast-scrubber")
            Text(VoiceFormat.clock(take.duration)).font(Theme.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.7))
        }
        .padding(.horizontal, 24).frame(height: 56)
    }

    // MARK: The words

    /// Under the stage, where viewers read them: the title, the subtitle and the description, each a line with a pencil; who it is from; the cover.
    private var words: some View {
        VStack(alignment: .leading, spacing: 14) {
            line($title, prompt: "Add a title", label: "title", focus: .title, weight: .bold, size: .title3, limit: 120, id: "podcast-title")
            line($subtitle, prompt: "Add a subtitle", label: "subtitle", focus: .subtitle, weight: .regular, size: .body, limit: 160, id: "podcast-subtitle")
            line($details, prompt: "Add a description", label: "description", focus: .details, weight: .regular, size: .callout, limit: 2000, id: "podcast-description", multiline: true)
            postRow
            Label("Shared with your subscribers", systemImage: "person.2").font(Theme.secondary).foregroundStyle(.white.opacity(0.85))
                .accessibilityElement(children: .ignore).accessibilityLabel("Shared with your subscribers").accessibilityIdentifier("podcast-sharing")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func line(_ text: Binding<String>, prompt: String, label: String, focus line: Line, weight: Font.Weight, size: Font.TextStyle, limit: Int, id: String, multiline: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 8) {
            TextField("", text: text, prompt: Text(prompt).foregroundColor(.white.opacity(0.55)), axis: multiline ? .vertical : .horizontal)
                .font(Theme.font(size, weight: weight)).foregroundStyle(.white).lineLimit(multiline ? 1...8 : 1...3)
                .focused($focus, equals: line).submitLabel(multiline ? .return : .next)
                .onChange(of: text.wrappedValue) { _, now in if now.count > limit { text.wrappedValue = String(now.prefix(limit)) } }
                .accessibilityLabel(label.capitalized).accessibilityIdentifier(id).id(line)
            Button { focus = line } label: {
                Image(systemName: "pencil").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white.opacity(0.75)).frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .accessibilityLabel("Edit \(label)").accessibilityIdentifier("\(id)-edit")
        }
        .frame(minHeight: 44)
    }

    /// Who it is from, the co-hosts and (for audio) the cover.
    private var postRow: some View {
        HStack(spacing: 8) {
            Button { postingAs = true } label: {
                HStack(spacing: 8) {
                    if let jamTitle { BylineAvatar(people: [store.meProvider()] + coauthors, jam: jamTitle, size: 32).frame(width: 42, height: 32, alignment: .leading) } else { AvatarView(person: store.meProvider(), size: 30).accessibilityHidden(true) }
                    Text(jamTitle ?? store.meProvider().name).font(Theme.font(.subheadline, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                    Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
                }
                .padding(.horizontal, 10).frame(minHeight: 44).background(.white.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain).accessibilityLabel("Posting as \(jamTitle ?? store.meProvider().name)").accessibilityIdentifier("podcast-post-as")
            Button { choosingHosts = true } label: {
                Image(systemName: "person.badge.plus").font(.system(size: 17)).foregroundStyle(.white).frame(width: 44, height: 44).background(.white.opacity(0.12), in: Circle())
            }
            .accessibilityLabel(coauthors.isEmpty ? "Add co-host" : "Co-hosts: \(coauthors.map(\.name).joined(separator: ", "))").accessibilityIdentifier("podcast-hosts")
            if !cameraOn {
                Button { pickingCover = true } label: {
                    Label(cover == nil && (editing == nil || removeCover || !store.jamAttachments(editing?.postId ?? "").contains(where: JamCover.isCover)) ? "Add cover" : "Edit cover", systemImage: "photo").font(Theme.secondary).lineLimit(1).fixedSize().foregroundStyle(.white).padding(.horizontal, 12).frame(minHeight: 44).background(.white.opacity(0.12), in: Capsule())
                }
                .accessibilityIdentifier("podcast-add-cover")
                if cover != nil {
                    Button { cover = nil } label: { Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).foregroundStyle(.white).frame(width: 44, height: 44) }
                        .accessibilityLabel("Remove cover").accessibilityIdentifier("podcast-remove-cover")
                } else if editing != nil, !removeCover, store.jamAttachments(editing?.postId ?? "").contains(where: JamCover.isCover) {
                    Button { removeCover = true } label: { Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).foregroundStyle(.white).frame(width: 44, height: 44) }
                        .accessibilityLabel("Remove cover").accessibilityIdentifier("podcast-remove-cover")
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Controls

    private var topBar: some View {
        HStack {
            Button { cancel() } label: { Text("Cancel").font(Theme.body).foregroundStyle(.white).frame(minWidth: 60, minHeight: 44, alignment: .leading) }
                .accessibilityIdentifier("podcast-cancel")
            Spacer()
            if cameraOn && !isRecording && clip == nil && !forArticle {
                Button { Task { capture.flip() } } label: {
                    Image(systemName: "arrow.triangle.2.circlepath.camera").font(.system(size: 20)).foregroundStyle(.white).frame(width: 44, height: 44).background(.white.opacity(0.14), in: Circle())
                }
                .accessibilityLabel("Flip camera").accessibilityIdentifier("podcast-flip")
            }
            if editing != nil {
                Button { Task { await update() } } label: {
                    Text(saving ? "Saving\u{2026}" : "Update").font(Theme.font(.body, weight: .semibold)).foregroundStyle(canUpdate ? Theme.accentInk : .white.opacity(0.5))
                        .padding(.horizontal, 16).frame(minHeight: 44).background(canUpdate ? Theme.accent : Color.white.opacity(0.12), in: Capsule())
                }
                .disabled(!canUpdate).accessibilityIdentifier("podcast-update")
            } else if !forArticle { Button { Task { await turnCamera(on: !cameraOn) } } label: {
                Image(systemName: cameraOn ? "video.fill" : "video.slash.fill").font(.system(size: 20)).foregroundStyle(.white).frame(width: 44, height: 44)
                    .background(cameraOn ? Theme.accent.opacity(0.9) : .white.opacity(0.14), in: Circle())
            }
            .disabled(isRecording || clip != nil || preparing)
            .accessibilityLabel("Camera").accessibilityValue(cameraOn ? "On" : "Off").accessibilityHint(cameraOn ? "Turns the camera off" : "Turns the camera on")
            .accessibilityIdentifier("podcast-camera") }
        }
        .padding(.horizontal, 16).padding(.top, 8)
    }

    /// Post (lime) once there is a take and a title; Re-record beside it (it asks first). In an article, Next.
    private var bottom: some View {
        HStack(spacing: 10) {
            if editing != nil {
                Button { confirmingRerecord = true } label: {
                    Label(reRecording || clip != nil ? "Re-record again" : "Re-record", systemImage: "arrow.counterclockwise").font(Theme.font(.body, weight: .semibold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 50).background(.white.opacity(0.14), in: Capsule())
                }
                .accessibilityIdentifier("podcast-again")
            } else if clip != nil {
                Button { confirmingRerecord = true } label: {
                    Label("Re-record", systemImage: "arrow.counterclockwise").font(Theme.font(.body, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 16).frame(minHeight: 50).background(.white.opacity(0.14), in: Capsule())
                }
                .accessibilityIdentifier("podcast-again")
            }
            if editing == nil { Button { forArticle ? finishUp() : (post != nil ? postNow() : finishUp()) } label: {
                Text(preparing ? "Getting ready\u{2026}" : forArticle ? "Next" : "Post").font(Theme.title)
                    .foregroundStyle((forArticle ? clip != nil : canPost) ? Theme.accentInk : .white.opacity(0.5))
                    .frame(maxWidth: .infinity, minHeight: 50).background((forArticle ? clip != nil : canPost) ? Theme.accent : Color.white.opacity(0.12), in: Capsule())
            }
            .disabled(preparing || !(forArticle ? clip != nil : canPost)).accessibilityIdentifier(forArticle ? "podcast-next" : "podcast-post") }
        }
        .padding(.horizontal, 24).padding(.vertical, 10)
        .background(Color.black)
    }

    private func circle(_ symbol: String, _ label: String, id: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 22)).foregroundStyle(.white).frame(width: size, height: size).background(.black.opacity(0.45), in: Circle())
        }
        .accessibilityLabel(label).accessibilityIdentifier(id)
    }

    // MARK: Doing it

    private func turnCamera(on: Bool) async {
        guard !isRecording else { return }
        if on {
            if demo { cameraOn = true; return }
            preparing = true
            defer { preparing = false }
            if await capture.prepare() { cameraOn = true }
            else { problem = "Turn on the camera and microphone for lime in Settings to record video." }
        } else {
            cameraOn = false
            capture.stopSession()
        }
    }

    private func begin() async {
        problem = nil
        seconds = 0
        focus = nil
        if cameraOn {
            if demo { simulatedVideo = 0; simulatedPaused = false; startClock(); return }
            capture.start()
            startClock()
        } else if !(await voice.start()) {
            problem = "Turn on the microphone for lime in Settings to record."
        }
    }

    private func togglePause() {
        if cameraOn {
            if demo { simulatedPaused.toggle() } else if capture.paused { capture.resume() } else { capture.pause() }
        } else if voice.paused { voice.resume() } else { voice.pause() }
    }

    /// The camera's timer (the voice recorder keeps its own).
    private func startClock() {
        ticker?.cancel()
        ticker = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                if !isPaused { seconds += 0.2 }
            }
        }
    }

    private func stop() async {
        ticker?.cancel()
        if cameraOn {
            if demo {
                simulatedVideo = nil
                #if DEBUG
                clip = ChatComposer.demoVideoDraft.outgoing
                #endif
                if let clip { take.load(clip) }
                return
            }
            guard let url = await capture.finish() else { problem = "That recording didn\u{2019}t work. Try again."; return }
            preparing = true
            defer { preparing = false; try? FileManager.default.removeItem(at: url) }
            guard let made = try? await VideoProcessing.prepare(url, maxBytes: ConversationStore.jamFileLimit - 256 * 1024, progress: { _ in }) else {
                problem = "That video is too large for a post. Try a shorter one."
                return
            }
            clip = made.item
            take.load(made.item)
        } else if let note = voice.finish() {
            seconds = Double(note.durationMs) / 1000
            let made = OutgoingAttachment(bytes: note.bytes, name: "Recording.m4a", mime: "audio/mp4", width: nil, height: nil,
                                          durationMs: UInt32(note.durationMs), thumb: Data(note.waveform), poster: Data())
            clip = made
            take.load(made)
        }
    }

    private func again() {
        take.unload()
        clip = nil
        editClip = nil
        trimStart = 0; trimEnd = 0
        seconds = 0
        if editing != nil { reRecording = true }
    }

    // MARK: Editing a podcast (LIME-227)

    private var canUpdate: Bool {
        !saving && !title.trimmingCharacters(in: .whitespaces).isEmpty && !(reRecording && clip == nil)
    }

    /// The post's own words and people go in once; the stage shows its own cover (or poster) and the shape of what it holds.
    private func prefill(_ post: JamPostInfo) {
        let files = store.jamAttachments(post.postId)
        cameraOn = files.contains { $0.kind == "video" }
        title = post.title; subtitle = post.subtitle; series = post.series
        // The description is the post's text without the picture block of its own cover (which the stage already shows).
        var text = post.markdown
        if let at = files.firstIndex(where: JamCover.isCover) { text = text.replacingOccurrences(of: "![](attachment:\(at))", with: "").trimmingCharacters(in: .whitespacesAndNewlines) }
        details = text
        initialHosts = post.coauthors
        coauthors = Array(store.bylinePeople(post).dropFirst())
        postAsJam = post.displayAs == "jam" ? post.jamId : nil
    }

    /// Update: the words, the cover and, after a Re-record, the new recording with its captions (made on this phone); the post is replaced in place.
    private func update() async {
        guard let editing, canUpdate else { return }
        saving = true
        // A trim of the recording the post already has replaces it with the cut part (the same path as recording again).
        if clip == nil, trimmed, let edit = editClip, !demo, let cut = await TrimExport.trim(edit, start: trimStart, end: trimEnd) { clip = cut }
        details = descModel.markdown().isEmpty ? details : descModel.markdown()
        var added: [OutgoingAttachment] = []
        if let clip {
            added.append(clip)
            if clip.mime.hasPrefix("video/") || clip.mime.hasPrefix("audio/"), clip.durationMs.map({ Int($0) / 1000 <= CaptionMaker.maxSeconds }) ?? true {
                let ext = clip.mime.hasPrefix("video/") ? "mp4" : "m4a"
                if let cues = await CaptionMaker.make(bytes: clip.bytes, fileExtension: ext, demo: demo), !cues.isEmpty {
                    // Named for the recording's place among the added files; the core renames it for the recording's real number.
                    added.append(OutgoingAttachment(bytes: Data(captionsToVtt(cues: cues).utf8), name: captionFileName(index: 0), mime: "text/vtt", width: nil, height: nil, durationMs: nil, thumb: Data(), poster: Data()))
                }
            }
        }
        if let cover { added.append(cover) }
        let hosts = coauthors.map(\.id)
        let ok = await store.editJamPost(editing, title: title, subtitle: subtitle, markdown: details, added: added, displayAs: postAsJam == nil ? "person" : "jam",
                                         removeCover: removeCover && cover == nil, coauthors: Set(hosts) == Set(initialHosts) ? nil : hosts)
        // Joining or leaving a series is a change of its own (the core seals the post again).
        let seriesOK = ok && series != editing.series ? await store.setPostSeries(editing, to: series) : true
        saving = false
        if ok && seriesOK { dismiss() } else { problem = "Could not update the podcast." }
    }

    /// The take goes back to the post (an article's audio, or Next without the studio's own Post).
    private func finishUp() {
        guard let clip else { return }
        attach(clip)
        dismiss()
    }

    /// The studio's Post: the take, its words, who it is from and the co-hosts go back and the post is made.
    private func postNow() {
        guard let clip, let post else { return }
        post(clip)
        dismiss()
    }

    private func cancel() {
        voice.cancel()
        ticker?.cancel()
        take.unload()
        dismiss()
    }

    private func teardown() {
        ticker?.cancel()
        capture.stopSession()
        take.unload()
    }
}

/// The sound drawn live behind the speaker: bars that grow from the middle, newest at the right.
private struct LiveBars: View {
    let levels: [Float]
    let active: Bool
    var count = 48

    var body: some View {
        Canvas { context, size in
            let gap: CGFloat = 4
            let width = max(2, (size.width - gap * CGFloat(count - 1)) / CGFloat(count))
            let shown = Array(levels.suffix(count))
            for index in 0..<count {
                let level = index >= count - shown.count ? CGFloat(shown[index - (count - shown.count)]) : 0
                let height = max(4, size.height * (active || level > 0 ? level : 0.04))
                let rect = CGRect(x: CGFloat(index) * (width + gap), y: (size.height - height) / 2, width: width, height: height)
                context.fill(Path(roundedRect: rect, cornerRadius: width / 2), with: .color(.white.opacity(0.35 + 0.4 * Double(level))))
            }
        }
    }
}


/// Cuts a recording to a range with AVFoundation, without re-encoding what is kept (passthrough); the waveform bytes are cut to the same range.
enum TrimExport {
    static func trim(_ clip: OutgoingAttachment, start: Double, end: Double) async -> OutgoingAttachment? {
        let video = clip.mime.hasPrefix("video/")
        let ext = video ? "mp4" : "m4a"
        let dir = FileManager.default.temporaryDirectory
        let input = dir.appendingPathComponent("lime-trim-in-\(UUID().uuidString).\(ext)")
        let output = dir.appendingPathComponent("lime-trim-out-\(UUID().uuidString).\(ext)")
        defer { try? FileManager.default.removeItem(at: input); try? FileManager.default.removeItem(at: output) }
        guard end > start, (try? clip.bytes.write(to: input)) != nil else { return nil }
        let asset = AVURLAsset(url: input)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else { return nil }
        session.outputURL = output
        session.outputFileType = video ? .mp4 : .m4a
        session.timeRange = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600), duration: CMTime(seconds: end - start, preferredTimescale: 600))
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in session.exportAsynchronously { done.resume() } }
        guard session.status == .completed, let data = try? Data(contentsOf: output), !data.isEmpty else { return nil }
        let total = Double(clip.durationMs ?? 0) / 1000
        var thumb = clip.thumb
        if !video, total > 0, !thumb.isEmpty {
            let from = min(thumb.count - 1, Int(start / total * Double(thumb.count))), to = max(from + 1, min(thumb.count, Int(end / total * Double(thumb.count))))
            thumb = Data(thumb[from..<to])
        }
        return OutgoingAttachment(bytes: data, name: clip.name, mime: clip.mime, width: clip.width, height: clip.height, durationMs: UInt32((end - start) * 1000), thumb: thumb, poster: clip.poster)
    }
}
