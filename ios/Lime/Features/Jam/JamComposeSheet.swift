import SwiftUI

/// The one unfinished post that survives closing the sheet (LIME-188b: one draft is enough for v1). Kept in memory for the session.
@MainActor
@Observable
final class JamDraft {
    static let shared = JamDraft()
    var article = false
    var title = ""
    var subtitle = ""
    var markdown = ""
    var isEmpty: Bool { title.isEmpty && subtitle.isEmpty && markdown.isEmpty }
    func clear() { article = false; title = ""; subtitle = ""; markdown = "" }
}

/// New post (LIME-188b): "What's on your mind?" with the chat's rich text field, photos, the camera and the formatting strip; **Write an article**
/// switches to a title, a subtitle and a long body; **Record** takes a video or a voice clip. Your jam is made on your first post.
struct JamComposeSheet: View {
    @Environment(ConversationStore.self) private var store
    @Environment(AccountSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var composer = RichComposerModel()
    @State private var sink = ComposerDraftSink()
    @State private var recorded: [OutgoingAttachment] = []
    @State private var recordTitle = ""
    @State private var recording = false
    @State private var article = JamDraft.shared.article
    @State private var title = JamDraft.shared.title
    @State private var subtitle = JamDraft.shared.subtitle
    @State private var posting = false
    @State private var problem: String?

    private var hasClip: Bool { recorded.contains { $0.mime.hasPrefix("video/") || $0.mime.hasPrefix("audio/") } }
    private var items: [OutgoingAttachment] { sink.items + recorded }
    private var hasWords: Bool { !composer.plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var canPost: Bool {
        guard !posting else { return false }
        if article { return !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (hasWords || !items.isEmpty) }
        return hasWords || !items.isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    AvatarView(person: store.meProvider(), size: 36).accessibilityHidden(true)
                    Text(store.meProvider().name).font(Theme.font(.body, weight: .semibold)).foregroundStyle(Theme.text)
                    Spacer()
                }
                .padding(.horizontal, 20).padding(.top, 12)
                if article {
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("Title", text: $title, axis: .vertical).font(Theme.font(.title2, weight: .bold)).lineLimit(1...3)
                            .accessibilityLabel("Title").accessibilityIdentifier("jam-article-title")
                        TextField("Add a subtitle\u{2026}", text: $subtitle, axis: .vertical).font(Theme.font(.body)).foregroundStyle(Theme.textSecondary).lineLimit(1...3)
                            .accessibilityLabel("Subtitle").accessibilityIdentifier("jam-article-subtitle")
                    }
                    .padding(.horizontal, 20).padding(.top, 12)
                }
                if let problem {
                    Text(problem).font(Theme.secondary).foregroundStyle(.red).padding(.horizontal, 20).padding(.top, 6).accessibilityIdentifier("jam-compose-problem")
                }
                if hasClip { recordedRow }
                Spacer(minLength: 0)
                chips
                ChatComposer(model: composer, onSend: { _ in }, onSendAttachments: { clips, _ in recorded.append(contentsOf: clips) }, draftSink: sink,
                             placeholder: article ? "Start writing\u{2026}" : "What\u{2019}s on your mind?")
            }
            .background(Theme.canvas)
            .navigationTitle(article ? "Article" : "New post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { close() }.accessibilityIdentifier("jam-compose-cancel") }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Post") { post() }.fontWeight(.semibold).disabled(!canPost).accessibilityIdentifier("jam-post")
                }
            }
            .sheet(isPresented: $recording) { JamRecorderSheet(title: $recordTitle) { recorded.append($0) } }
            .task {
                // The draft's words go back into the field once it exists.
                try? await Task.sleep(for: .milliseconds(300))
                if !JamDraft.shared.markdown.isEmpty { composer.textView?.attributedText = ComposerDocument.attributed(fromMarkdown: JamDraft.shared.markdown); composer.didEdit() }
            }
        }
    }

    private var chips: some View {
        HStack(spacing: 8) {
            if article {
                chip("Exit article mode", system: "chevron.left", id: "jam-exit-article") { article = false }
            } else {
                chip("Write an article", system: "doc.text", id: "jam-write-article") { article = true }
                chip("Record", system: "video", id: "jam-record") { recording = true }
            }
            Spacer()
        }
        .padding(.horizontal, 16).padding(.bottom, 4)
    }

    private func chip(_ label: String, system: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: system).font(Theme.secondary).foregroundStyle(Theme.text)
                .padding(.horizontal, 12).frame(minHeight: 40).background(Theme.surface, in: Capsule())
        }
        .buttonStyle(.plain).accessibilityIdentifier(id)
    }

    private var recordedRow: some View {
        HStack {
            ForEach(Array(recorded.enumerated()), id: \.offset) { index, clip in
                Button { recorded.remove(at: index) } label: {
                    Label(clip.mime.hasPrefix("video/") ? "Video" : clip.mime.hasPrefix("audio/") ? "Voice" : "Photo", systemImage: "xmark.circle.fill")
                        .font(Theme.secondary).foregroundStyle(Theme.text).padding(.horizontal, 12).frame(minHeight: 36).background(Theme.surface, in: Capsule())
                }
                .accessibilityLabel("Remove \(clip.mime.hasPrefix("video/") ? "video" : "recording")").accessibilityIdentifier("jam-recorded-\(index)")
            }
            Spacer()
        }
        .padding(.horizontal, 20).padding(.top, 8)
    }

    private func close() {
        let draft = JamDraft.shared
        draft.article = article; draft.title = title; draft.subtitle = subtitle; draft.markdown = hasWords ? composer.markdown() : ""
        dismiss()
    }

    private func post() {
        let markdown = composer.markdown()
        let kind = hasClip ? "record" : article ? "article" : "quick"
        let headline = article ? title : recordTitle
        guard items.allSatisfy({ $0.bytes.count <= 24 * 1024 * 1024 }) else { problem = "A file is too large for a post (24 MB)."; return }
        problem = nil
        posting = true
        Task {
            let ok = await store.publishJamPost(kind: kind, title: headline, subtitle: article ? subtitle : "", markdown: markdown, items: items, about: session.profile?.aboutText ?? "")
            posting = false
            if ok { JamDraft.shared.clear(); dismiss() } else { problem = "Could not post. Try again." }
        }
    }
}

/// Record (LIME-188b): a video from the camera, or a voice clip, with an optional title; **Next** hands it back to the post.
struct JamRecorderSheet: View {
    @Binding var title: String
    let attach: (OutgoingAttachment) -> Void
    @Environment(ConversationStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var mode = 0
    @State private var camera = false
    @State private var voice = VoiceRecorder()
    @State private var clip: OutgoingAttachment?
    @State private var preparing = false
    @State private var micDenied = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Picker("Kind", selection: $mode) {
                    Text("Video").tag(0)
                    Text("Voice").tag(1)
                }
                .pickerStyle(.segmented).accessibilityIdentifier("jam-record-mode")
                TextField("Title (optional)", text: $title).font(Theme.body).padding(14)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous)).accessibilityIdentifier("jam-record-title")
                Spacer()
                if mode == 0 { videoControls } else { voiceControls }
                Spacer()
                if clip != nil {
                    Label(mode == 0 ? "Video ready" : "Recording ready", systemImage: "checkmark.circle.fill").font(Theme.secondary).foregroundStyle(Theme.text)
                        .accessibilityIdentifier("jam-record-ready")
                }
            }
            .padding(20)
            .background(Theme.canvas)
            .navigationTitle("Record")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { voice.cancel(); dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Next") { if let clip { attach(clip) }; dismiss() }.fontWeight(.semibold).disabled(clip == nil || preparing).accessibilityIdentifier("jam-record-next")
                }
            }
            .fullScreenCover(isPresented: $camera) {
                CameraCapturePicker(onPhoto: { _ in camera = false }, onVideo: { url in camera = false; prepare(url) }, onCancel: { camera = false }).ignoresSafeArea()
            }
            .alert("Microphone is off", isPresented: $micDenied) { Button("OK", role: .cancel) {} } message: { Text("Turn on the microphone for lime in Settings to record.") }
            .onAppear {
                #if DEBUG
                voice.simulated = store.isDemo
                #endif
            }
        }
        .presentationDetents([.large])
    }

    private var videoControls: some View {
        VStack(spacing: 12) {
            Button { openCamera() } label: {
                Image(systemName: preparing ? "hourglass" : "video.fill").font(.system(size: 34)).foregroundStyle(Theme.accentInk)
                    .frame(width: 88, height: 88).background(Theme.accent, in: Circle())
            }
            .buttonStyle(.plain).disabled(preparing).accessibilityLabel(clip == nil ? "Record a video" : "Record again").accessibilityIdentifier("jam-record-video")
            Text("Up to a few minutes. Front or back camera.").font(Theme.caption).foregroundStyle(Theme.textSecondary)
        }
    }

    private var voiceControls: some View {
        VStack(spacing: 12) {
            Button { toggleVoice() } label: {
                Image(systemName: voice.phase == .idle ? "mic.fill" : "stop.fill").font(.system(size: 34)).foregroundStyle(Theme.accentInk)
                    .frame(width: 88, height: 88).background(Theme.accent, in: Circle())
            }
            .buttonStyle(.plain).accessibilityLabel(voice.phase == .idle ? "Start recording" : "Stop recording").accessibilityValue(voice.phase == .idle ? "" : "Recording")
            .accessibilityIdentifier("jam-record-voice")
            Text(voice.phase == .idle ? "Tap to record." : "\(Int(voice.elapsed)) s").font(Theme.secondary).foregroundStyle(Theme.textSecondary)
        }
    }

    private func openCamera() {
        #if DEBUG
        if store.isDemo { clip = ChatComposer.demoVideoDraft.outgoing; return }
        #endif
        camera = true
    }

    private func prepare(_ url: URL) {
        preparing = true
        Task {
            defer { preparing = false; try? FileManager.default.removeItem(at: url) }
            if let made = try? await VideoProcessing.prepare(url, progress: { _ in }) { clip = made.item }
        }
    }

    private func toggleVoice() {
        Task {
            if voice.phase == .idle {
                clip = nil
                if !(await voice.start()) { micDenied = true }
            } else if let note = voice.finish() {
                clip = OutgoingAttachment(bytes: note.bytes, name: "Voice message.m4a", mime: "audio/mp4", width: nil, height: nil,
                                          durationMs: UInt32(note.durationMs), thumb: Data(note.waveform), poster: Data())
            }
        }
    }
}
