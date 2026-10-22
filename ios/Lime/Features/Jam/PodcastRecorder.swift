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

/// Record (LIME-188g): a podcast. Full screen and dark. By default **audio**: your picture in the centre and the sound drawn as you talk. The camera
/// button (top right) turns the **camera** on, edge to edge, with the controls over it on a soft scrim; off, your picture comes back. Record, pause and
/// stop, a timer, a title and who it is shared with. **Next** asks for co-hosts (optional) and hands the recording back to the post.
struct PodcastRecorder: View {
    @Binding var title: String
    @Binding var coauthors: [Person]
    let camera: Bool
    /// Audio for an article (LIME-188n): no title, sharing line or co-hosts; Next puts the clip in the text.
    var forArticle = false
    /// A recording's subtitle, description and cover (LIME-188k), asked after Next, before the co-hosts.
    @Binding var subtitle: String
    @Binding var details: String
    @Binding var cover: OutgoingAttachment?
    let attach: (OutgoingAttachment) -> Void
    init(title: Binding<String>, coauthors: Binding<[Person]>, camera: Bool, forArticle: Bool = false,
         subtitle: Binding<String> = .constant(""), details: Binding<String> = .constant(""), cover: Binding<OutgoingAttachment?> = .constant(nil),
         attach: @escaping (OutgoingAttachment) -> Void) {
        _title = title; _coauthors = coauthors; self.camera = camera; self.forArticle = forArticle
        _subtitle = subtitle; _details = details; _cover = cover; self.attach = attach
    }

    @Environment(ConversationStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var choosingDetails = false
    @State private var cameraOn = false
    @State private var voice = VoiceRecorder()
    @State private var capture = PodcastCapture()
    @State private var clip: OutgoingAttachment?
    @State private var shown = false
    @State private var preparing = false
    @State private var started = false
    @State private var seconds: TimeInterval = 0
    @State private var simulatedPaused = false
    @State private var simulatedVideo: TimeInterval?
    @State private var ticker: Task<Void, Never>?
    @State private var problem: String?
    @State private var choosingHosts = false

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

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if cameraOn { cameraLayer } else { audioLayer }
            VStack(spacing: 0) {
                topBar
                Spacer()
                bottom
            }
            .background(alignment: .bottom) {
                LinearGradient(colors: [.clear, .black.opacity(cameraOn ? 0.7 : 0)], startPoint: .top, endPoint: .bottom).frame(height: 320).ignoresSafeArea().allowsHitTesting(false)
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $choosingDetails, onDismiss: { choosingHosts = true }) { PodcastDetailsSheet(subtitle: $subtitle, details: $details, cover: $cover) }
        .sheet(isPresented: $choosingHosts, onDismiss: finishUp) { JamCoauthorPicker(selected: $coauthors, title: "Add co-hosts") }
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

    // MARK: Layers

    /// Audio: your picture, and the sound behind it as vertical bars that move while you talk.
    private var audioLayer: some View {
        ZStack {
            LiveBars(levels: voice.levels, active: voice.phase != .idle && !voice.paused)
                .frame(height: 220).padding(.horizontal, 12)
                .accessibilityHidden(true)
            AvatarView(person: store.meProvider(), size: 148).accessibilityHidden(true)
                .overlay(Circle().strokeBorder(.white.opacity(0.2), lineWidth: 1))
        }
        .accessibilityElement(children: .ignore).accessibilityLabel("Your picture, and the sound as you speak").accessibilityIdentifier("podcast-audio-layer")
    }

    /// Camera: the preview fills the screen (a made-up frame in the demo, which has no camera).
    private var cameraLayer: some View {
        ZStack {
            if demo {
                LinearGradient(colors: [Color(white: 0.28), Color(white: 0.1)], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
                Image(systemName: "person.fill").font(.system(size: 120)).foregroundStyle(.white.opacity(0.25))
            } else {
                CameraPreview(session: capture.session).ignoresSafeArea()
            }
        }
        .accessibilityLabel("Camera preview").accessibilityIdentifier("podcast-camera-layer")
    }

    // MARK: Controls

    private var topBar: some View {
        HStack {
            Button { cancel() } label: { Text("Cancel").font(Theme.body).foregroundStyle(.white).frame(minWidth: 60, minHeight: 44, alignment: .leading) }
                .accessibilityIdentifier("podcast-cancel")
            Spacer()
            if cameraOn && !isRecording && !forArticle {
                Button { Task { capture.flip() } } label: {
                    Image(systemName: "arrow.triangle.2.circlepath.camera").font(.system(size: 20)).foregroundStyle(.white).frame(width: 44, height: 44).background(.black.opacity(0.35), in: Circle())
                }
                .accessibilityLabel("Flip camera").accessibilityIdentifier("podcast-flip")
            }
            if !forArticle { Button { Task { await turnCamera(on: !cameraOn) } } label: {
                Image(systemName: cameraOn ? "video.fill" : "video.slash.fill").font(.system(size: 20)).foregroundStyle(.white).frame(width: 44, height: 44)
                    .background(cameraOn ? Theme.accent.opacity(0.9) : .black.opacity(0.35), in: Circle())
            }
            .disabled(isRecording || clip != nil || preparing)
            .accessibilityLabel("Camera").accessibilityValue(cameraOn ? "On" : "Off").accessibilityHint(cameraOn ? "Turns the camera off" : "Turns the camera on")
            .accessibilityIdentifier("podcast-camera") }
        }
        .padding(.horizontal, 16).padding(.top, 8)
    }

    private var bottom: some View {
        VStack(spacing: 14) {
            Text(VoiceFormat.clock(clip != nil ? seconds : elapsed)).font(Theme.font(.largeTitle, weight: .semibold).monospacedDigit()).foregroundStyle(.white)
                .accessibilityLabel("Time").accessibilityValue(PodcastFormat.spoken(clip != nil ? seconds : elapsed)).accessibilityIdentifier("podcast-time")
            if !forArticle { TextField("", text: $title, prompt: Text("Add a title\u{2026}").foregroundColor(.white.opacity(0.6)))
                .font(Theme.font(.title3, weight: .semibold)).foregroundStyle(.white).multilineTextAlignment(.center).submitLabel(.done)
                .onChange(of: title) { _, now in if now.count > 120 { title = String(now.prefix(120)) } }
                .accessibilityLabel("Title").accessibilityIdentifier("podcast-title")
            Label("Shared with your subscribers", systemImage: "person.2").font(Theme.secondary).foregroundStyle(.white.opacity(0.85)).accessibilityElement(children: .ignore).accessibilityLabel("Shared with your subscribers")
                .accessibilityIdentifier("podcast-sharing") }
            controls
            Button { next() } label: {
                Text(preparing ? "Getting ready\u{2026}" : "Next").font(Theme.title).foregroundStyle(clip == nil ? .white.opacity(0.5) : Theme.accentInk)
                    .frame(maxWidth: .infinity, minHeight: 50).background(clip == nil ? Color.white.opacity(0.12) : Theme.accent, in: Capsule())
            }
            .disabled(clip == nil || preparing).accessibilityIdentifier("podcast-next")
        }
        .padding(.horizontal, 24).padding(.bottom, 16)
    }

    private var controls: some View {
        HStack(spacing: 36) {
            if clip != nil {
                circle("arrow.counterclockwise", "Record again", id: "podcast-again", size: 56) { again() }
                Color.clear.frame(width: 76, height: 76)
                Color.clear.frame(width: 56, height: 56)
            } else if isRecording {
                if canPause { circle(isPaused ? "mic.fill" : "pause.fill", isPaused ? "Resume recording" : "Pause recording", id: "podcast-pause", size: 56) { togglePause() } }
                else { Color.clear.frame(width: 56, height: 56) }
                Button { Task { await stop() } } label: {
                    ZStack {
                        Circle().strokeBorder(.white, lineWidth: 4).frame(width: 76, height: 76)
                        RoundedRectangle(cornerRadius: 6).fill(.red).frame(width: 30, height: 30)
                    }
                }
                .accessibilityLabel("Stop recording").accessibilityIdentifier("podcast-stop")
                Color.clear.frame(width: 56, height: 56)
            } else {
                Color.clear.frame(width: 56, height: 56)
                Button { Task { await begin() } } label: {
                    ZStack {
                        Circle().strokeBorder(.white, lineWidth: 4).frame(width: 76, height: 76)
                        Circle().fill(.red).frame(width: 60, height: 60)
                    }
                }
                .disabled(preparing).accessibilityLabel("Start recording").accessibilityIdentifier("podcast-record")
                Color.clear.frame(width: 56, height: 56)
            }
        }
        .frame(minHeight: 80)
    }

    private func circle(_ symbol: String, _ label: String, id: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 22)).foregroundStyle(.white).frame(width: size, height: size).background(.white.opacity(0.16), in: Circle())
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
        } else if let note = voice.finish() {
            seconds = Double(note.durationMs) / 1000
            clip = OutgoingAttachment(bytes: note.bytes, name: "Recording.m4a", mime: "audio/mp4", width: nil, height: nil,
                                      durationMs: UInt32(note.durationMs), thumb: Data(note.waveform), poster: Data())
        }
    }

    private func again() {
        clip = nil
        seconds = 0
    }

    private func next() {
        guard clip != nil else { return }
        if forArticle { finishUp(); return }
        choosingDetails = true
    }

    /// After the co-host list (or Skip), the recording goes back to the post.
    private func finishUp() {
        guard let clip else { return }
        attach(clip)
        dismiss()
    }

    private func cancel() {
        voice.cancel()
        ticker?.cancel()
        dismiss()
    }

    private func teardown() {
        ticker?.cancel()
        capture.stopSession()
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

/// After Next: a cover, a subtitle and a short description for the recording's post (all optional; with no cover the card shows your picture).
struct PodcastDetailsSheet: View {
    @Binding var subtitle: String
    @Binding var details: String
    @Binding var cover: OutgoingAttachment?
    @Environment(\.dismiss) private var dismiss
    @State private var picking = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button { picking = true } label: {
                        HStack(spacing: 12) {
                            if let cover, let image = UIImage(data: cover.bytes) { Image(uiImage: image).resizable().scaledToFill().frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous)) }
                            else { Image(systemName: "photo").frame(width: 64, height: 64).background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous)) }
                            Text(cover == nil ? "Add cover" : "Change cover").font(Theme.body).foregroundStyle(Theme.text)
                            Spacer()
                        }
                        .frame(minHeight: 44)
                    }
                    .accessibilityIdentifier("podcast-add-cover")
                    if cover != nil { Button("Remove cover", role: .destructive) { cover = nil } }
                } footer: { Text("Without a cover the card shows your picture.") }
                Section {
                    TextField("Subtitle", text: $subtitle).onChange(of: subtitle) { _, now in if now.count > 160 { subtitle = String(now.prefix(160)) } }.accessibilityIdentifier("podcast-subtitle")
                    TextField("Description", text: $details, axis: .vertical).lineLimit(3...8).accessibilityIdentifier("podcast-description")
                }
            }
            .navigationTitle("Details").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Next") { dismiss() }.fontWeight(.semibold).accessibilityIdentifier("podcast-details-next") } }
            .fullScreenCover(isPresented: $picking) {
                MediaLibraryPicker(limit: 1, onPick: { images, _ in
                    picking = false
                    if let image = images.first, let made = AttachmentProcessing.photo(image, name: JamCover.name) { cover = made }
                }, onCancel: { picking = false }).ignoresSafeArea()
            }
        }
        .presentationDetents([.large])
    }
}
