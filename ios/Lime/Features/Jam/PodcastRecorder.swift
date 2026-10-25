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
    let attach: (OutgoingAttachment) -> Void
    /// The studio's Post: hands the take back and posts it at once (when not set, Next only hands the take back).
    var post: ((OutgoingAttachment) -> Void)?
    init(title: Binding<String>, coauthors: Binding<[Person]>, camera: Bool, forArticle: Bool = false,
         subtitle: Binding<String> = .constant(""), details: Binding<String> = .constant(""), cover: Binding<OutgoingAttachment?> = .constant(nil),
         postAsJam: Binding<String?> = .constant(nil), post: ((OutgoingAttachment) -> Void)? = nil,
         attach: @escaping (OutgoingAttachment) -> Void) {
        _title = title; _coauthors = coauthors; self.camera = camera; self.forArticle = forArticle
        _subtitle = subtitle; _details = details; _cover = cover; _postAsJam = postAsJam; self.post = post; self.attach = attach
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

    var body: some View {
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
        .preferredColorScheme(.dark)
        .sheet(isPresented: $choosingHosts) { JamCoauthorPicker(selected: $coauthors, title: "Add co-hosts") }
        .sheet(isPresented: $postingAs) { PostAsSheet(selection: $postAsJam) }
        .fullScreenCover(isPresented: $pickingCover) {
            MediaLibraryPicker(limit: 1, onPick: { images, _ in
                pickingCover = false
                if let image = images.first, let made = AttachmentProcessing.photo(image, name: JamCover.name) { cover = made }
            }, onCancel: { pickingCover = false }).ignoresSafeArea()
        }
        .confirmSheet("Replace this recording?", isPresented: $confirmingRerecord) {
            Button("Re-record", role: .destructive) { again() }.accessibilityIdentifier("podcast-rerecord-confirm")
            Button("Keep it", role: .cancel) {}
        } message: { Text("The one you made is thrown away.") }
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
            if camera { Task { await turnCamera(on: true) } }
        }
        .onDisappear { teardown() }
        .onChange(of: voice.elapsed) { _, now in if !cameraOn, now >= VoiceRecorder.podcastSeconds { Task { await stop() } } }
        .onChange(of: seconds) { _, now in if cameraOn, now >= VideoProcessing.maxSeconds { Task { await stop() } } }
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
        CoverArt(image: coverImage, person: store.meProvider(), org: jamTitle)
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
                    Label(cover == nil ? "Add cover" : "Change cover", systemImage: "photo").font(Theme.secondary).foregroundStyle(.white).padding(.horizontal, 12).frame(minHeight: 44).background(.white.opacity(0.12), in: Capsule())
                }
                .accessibilityIdentifier("podcast-add-cover")
                if cover != nil {
                    Button { cover = nil } label: { Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).foregroundStyle(.white).frame(width: 44, height: 44) }
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
            if !forArticle { Button { Task { await turnCamera(on: !cameraOn) } } label: {
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
            if clip != nil {
                Button { confirmingRerecord = true } label: {
                    Label("Re-record", systemImage: "arrow.counterclockwise").font(Theme.font(.body, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 16).frame(minHeight: 50).background(.white.opacity(0.14), in: Capsule())
                }
                .accessibilityIdentifier("podcast-again")
            }
            Button { forArticle ? finishUp() : (post != nil ? postNow() : finishUp()) } label: {
                Text(preparing ? "Getting ready\u{2026}" : forArticle ? "Next" : "Post").font(Theme.title)
                    .foregroundStyle((forArticle ? clip != nil : canPost) ? Theme.accentInk : .white.opacity(0.5))
                    .frame(maxWidth: .infinity, minHeight: 50).background((forArticle ? clip != nil : canPost) ? Theme.accent : Color.white.opacity(0.12), in: Capsule())
            }
            .disabled(preparing || !(forArticle ? clip != nil : canPost)).accessibilityIdentifier(forArticle ? "podcast-next" : "podcast-post")
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
        seconds = 0
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

    var body: some View {
        Canvas { context, size in
            let count = 48
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
