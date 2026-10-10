import SwiftUI

/// The composer (design 04): the text above, and under it `+`, emoji and Aa on the left, mic or send on
/// the right. Select text, or tap Aa, and the formatting toolbar appears above the keyboard. The chat and
/// a thread both use it; `onSend` gets the message as Markdown.
struct ChatComposer: View {
    @Environment(ConversationStore.self) private var store
    @Bindable var model: RichComposerModel
    let onSend: (String) -> Void
    /// Sends the waiting pictures and files with the written text as their caption. `nil`: this composer cannot send attachments.
    var onSendAttachments: (([OutgoingAttachment], String) -> Void)? = nil
    /// Sends the written text with its link card. `nil`: this composer sends no cards.
    var onSendPreview: ((String, OutgoingPreview) -> Void)? = nil
    /// Settings → Privacy → "Generate link previews".
    @AppStorage(LinkPreviewSetting.key) private var previewsOn = true
    @State private var previewDraft: PreviewDraft?
    @State private var dismissedURL: URL?
    @State private var previewTask: Task<Void, Never>?
    @State private var pickingEmoji = false
    @State private var drafts: [DraftAttachment] = []
    @State private var chooser: Chooser?
    @State private var tooLarge = false
    @State private var choosing = false
    @State private var recorder = VoiceRecorder()
    @State private var dragX: CGFloat = 0
    @State private var released = true
    @State private var micDenied = false
    /// 0...1 while a video is being prepared (compressed), else nil.
    @State private var preparingVideo: Double?
    @State private var videoProblem: String?

    private enum Chooser: String, Identifiable { case album, camera, files, videoLibrary, videoCamera; var id: String { rawValue } }
    private var canSend: Bool { model.canSend || !drafts.isEmpty }
    private var voiceEnabled: Bool { onSendAttachments != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let fraction = preparingVideo {
                HStack(spacing: 10) {
                    ProgressView(value: fraction).tint(Theme.text).frame(width: 90)
                    Text("Preparing video… \(Int(fraction * 100))%").font(Theme.secondary).foregroundStyle(Theme.textSecondary)
                }
                .padding(.horizontal, 6).padding(.top, 8).accessibilityIdentifier("video-preparing")
            }
            if !drafts.isEmpty { DraftStrip(drafts: drafts) { draft in drafts.removeAll { $0.id == draft.id } } }
            if let previewDraft { previewCard(previewDraft) }
            if recorder.isRecording {
                RecordingBar(recorder: recorder, dragX: dragX)
            } else {
                ZStack(alignment: .topLeading) {
                    RichComposerField(model: model)
                        .onAppear { model.hasText = false }
                    if !model.hasText {
                        Text("Send message…").font(Theme.body).foregroundStyle(Theme.textSecondary)
                            .padding(.leading, 4).padding(.top, 8).allowsHitTesting(false).accessibilityHidden(true)
                    }
                }
            }
            if recorder.phase == .locked {
                lockedRow
            } else {
            HStack(spacing: 2) {
                HStack(spacing: 2) {
                    button("plus", label: "Add attachment", id: "composer-plus") {
                        if onSendAttachments == nil { store.comingSoon("Attachments") } else { choosing = true }
                    }
                    button("face.smiling", label: "Emoji", id: "composer-emoji") { pickingEmoji = true }
                    Button { model.toggleToolbar() } label: {
                        Text("Aa").font(.system(size: 17, weight: model.toolbarVisible ? .bold : .medium)).foregroundStyle(Theme.text)
                            .frame(width: 44, height: 40)
                            .background(model.toolbarVisible ? Theme.pressed : Color.clear, in: Capsule())
                    }
                    .accessibilityLabel("Formatting").accessibilityIdentifier("composer-aa")
                    .accessibilityAddTraits(model.toolbarVisible ? [.isSelected] : [])
                }
                .opacity(recorder.isRecording ? 0 : 1).allowsHitTesting(!recorder.isRecording)
                Spacer(minLength: 0)
                if canSend && !recorder.isRecording {
                    Button { send() } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Theme.primaryInk)
                            .frame(width: 36, height: 36)
                            .background(Theme.primary, in: Circle())
                            .frame(width: 44, height: 40)
                    }
                    .accessibilityLabel("Send")
                    .accessibilityIdentifier("send-button")
                } else if voiceEnabled {
                    micButton
                } else {
                    button("mic", label: "Voice message", id: "composer-mic") { store.comingSoon("Voice messages") }
                }
            }
            }
        }
        .padding(.horizontal, 12).padding(.top, 2).padding(.bottom, 4)
        .limeGlass(in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
        .overlay { EmojiKeyboardField(isActive: $pickingEmoji) { model.insertEmoji($0) }.frame(width: 1, height: 1).opacity(0.01) }
        .sheet(item: $model.linkRequest) { request in LinkSheet(request: request, composer: model) }
        .confirmationDialog("Add to your message", isPresented: $choosing, titleVisibility: .visible) {
            Button("Photo Library") { chooser = .album }.accessibilityIdentifier("composer-photo-library")
            if CameraPicker.isAvailable { Button("Take Photo") { chooser = .camera }.accessibilityIdentifier("composer-take-photo") }
            Button("Choose Video") { chooser = .videoLibrary }.accessibilityIdentifier("composer-video-library")
            if CameraPicker.isAvailable { Button("Record Video") { chooser = .videoCamera }.accessibilityIdentifier("composer-record-video") }
            Button("Files") { chooser = .files }.accessibilityIdentifier("composer-files")
            Button("Cancel", role: .cancel) {}
        }
        .fullScreenCover(item: $chooser) { which in
            switch which {
            case .album:
                AlbumPicker(limit: max(1, AttachmentProcessing.maxPerMessage - drafts.count), onPick: { images in chooser = nil; add(images: images) }, onCancel: { chooser = nil }).ignoresSafeArea()
            case .camera:
                CameraPicker(onPick: { image in chooser = nil; add(images: [image]) }, onCancel: { chooser = nil }).ignoresSafeArea()
            case .files:
                DocumentPicker(onPick: { urls in chooser = nil; add(files: urls) }, onCancel: { chooser = nil }).ignoresSafeArea()
            case .videoLibrary:
                VideoLibraryPicker(onPick: { url in chooser = nil; add(video: url) }, onCancel: { chooser = nil }).ignoresSafeArea()
            case .videoCamera:
                VideoCameraPicker(onPick: { url in chooser = nil; add(video: url) }, onCancel: { chooser = nil }).ignoresSafeArea()
            }
        }
        .alert("The microphone is off", isPresented: $micDenied) {
            Button("Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Turn on the microphone for Lime in Settings to record voice messages.") }
        .alert("That video can't be sent", isPresented: Binding(get: { videoProblem != nil }, set: { if !$0 { videoProblem = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(videoProblem ?? "") }
        .alert("That file is too large", isPresented: $tooLarge) { Button("OK", role: .cancel) {} } message: { Text("Files can be up to 50 MB.") }
        .onChange(of: model.plainText) { refreshPreview() }
        .onChange(of: previewsOn) { refreshPreview() }
        .onChange(of: drafts.count) { refreshPreview() }
        #if DEBUG
        .task { if store.demoDrafts { drafts = ChatComposer.demoDrafts }; recorder.simulated = store.isDemo }
        #endif
    }

    // MARK: Voice messages

    /// The mic: hold to record, release to send, slide left to cancel, slide up to lock and go hands-free.
    private var micButton: some View {
        Image(systemName: "mic").font(.system(size: 20)).foregroundStyle(recorder.isRecording ? Color.white : Theme.text)
            .frame(width: 44, height: 40)
            .background(recorder.isRecording ? Color.red : Color.clear, in: Circle())
            .scaleEffect(recorder.isRecording ? 1.35 : 1)
            .overlay(alignment: .top) {
                if recorder.phase == .recording {
                    Image(systemName: "lock").font(.system(size: 15)).foregroundStyle(Theme.text)
                        .frame(width: 34, height: 34).background(Theme.surface, in: Circle())
                        .offset(y: -64).accessibilityIdentifier("voice-lock-hint")
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if released {
                        released = false
                        Task { await beginVoice() }
                    }
                    guard recorder.phase == .recording else { return }
                    dragX = value.translation.width
                    if value.translation.width < -90 { recorder.cancel(); dragX = 0; Haptics.tick() }
                    else if value.translation.height < -70 { recorder.lock(); dragX = 0; released = true; Haptics.tick() }   // the mic leaves the row when locked, so its end never comes
                }
                .onEnded { _ in
                    released = true
                    if recorder.phase == .recording { finishVoice() }
                    dragX = 0
                })
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Voice message")
            .accessibilityHint("Hold to record, release to send")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("composer-mic")
    }

    private var lockedRow: some View {
        HStack {
            Button { recorder.cancel() } label: {
                Image(systemName: "trash").font(.system(size: 19)).foregroundStyle(Color.red).frame(width: 44, height: 40)
            }
            .accessibilityLabel("Delete recording").accessibilityIdentifier("voice-cancel")
            Spacer()
            Text("Recording").font(Theme.secondary).foregroundStyle(Theme.textSecondary)
            Spacer()
            Button { finishVoice() } label: {
                Image(systemName: "arrow.up").font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.primaryInk)
                    .frame(width: 36, height: 36).background(Theme.primary, in: Circle()).frame(width: 44, height: 40)
            }
            .accessibilityLabel("Send voice message").accessibilityIdentifier("voice-send")
        }
    }

    private func beginVoice() async {
        guard await recorder.start() else { micDenied = true; released = true; return }
        // The finger was lifted while the microphone was being allowed: nothing to keep.
        if released && recorder.phase == .recording { recorder.cancel() }
        Haptics.tick()
    }

    /// Stops and sends the voice message (a very short one is dropped).
    private func finishVoice() {
        guard let note = recorder.finish(), let onSendAttachments else { return }
        let voice = OutgoingAttachment(bytes: note.bytes, name: "Voice message.m4a", mime: "audio/mp4", width: nil, height: nil,
                                       durationMs: UInt32(note.durationMs), thumb: Data(note.waveform))
        onSendAttachments([voice], "")
    }

    // MARK: Video

    private func add(video url: URL) {
        Task {
            preparingVideo = 0
            defer { preparingVideo = nil; try? FileManager.default.removeItem(at: url) }
            #if DEBUG
            if store.isDemo { preparingVideo = 1; drafts.append(ChatComposer.demoVideoDraft); return }
            #endif
            do {
                let made = try await VideoProcessing.prepare(url) { fraction in Task { @MainActor in preparingVideo = fraction } }
                drafts.append(DraftAttachment(outgoing: made.item, preview: made.poster))
            } catch let problem as VideoProcessing.Problem {
                videoProblem = VideoProcessing.message(for: problem)
            } catch {
                videoProblem = VideoProcessing.message(for: .unreadable)
            }
        }
    }

    private func add(images: [UIImage]) {
        Task {
            for image in images where drafts.count < AttachmentProcessing.maxPerMessage {
                let made = await Task.detached(priority: .userInitiated) { () -> (OutgoingAttachment, UIImage)? in
                    guard let item = AttachmentProcessing.photo(image) else { return nil }
                    return (item, PhotoProcessing.crop(image, viewport: 128, scale: 1, offset: .zero))
                }.value
                if let made { drafts.append(DraftAttachment(outgoing: made.0, preview: made.1)) }
            }
        }
    }

    private func add(files urls: [URL]) {
        Task {
            for url in urls where drafts.count < AttachmentProcessing.maxPerMessage {
                do {
                    let item = try await Task.detached(priority: .userInitiated) { try AttachmentProcessing.file(at: url) }.value
                    drafts.append(DraftAttachment(outgoing: item, preview: item.mime.hasPrefix("image/") ? UIImage(data: item.bytes).map { PhotoProcessing.crop($0, viewport: 128, scale: 1, offset: .zero) } : nil))
                } catch AttachmentProcessing.Problem.tooLarge {
                    tooLarge = true
                } catch {}
            }
        }
    }

    private func button(_ symbol: String, label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 20)).foregroundStyle(Theme.text).frame(width: 44, height: 40)
        }
        .accessibilityLabel(label).accessibilityIdentifier(id)
    }

    /// Sends what is written, as Markdown (LimeCore writes it the one way), and empties the composer.
    // MARK: Link card

    private struct PreviewDraft: Equatable {
        let url: URL
        let outgoing: OutgoingPreview
    }

    private func previewCard(_ draft: PreviewDraft) -> some View {
        HStack(alignment: .top, spacing: 8) {
            LinkCardView(title: draft.outgoing.title, site: draft.outgoing.site, image: UIImage(data: draft.outgoing.image), width: 220)
            Button { dismissedURL = draft.url; previewDraft = nil } label: {
                Image(systemName: "xmark.circle.fill").font(.system(size: 22)).foregroundStyle(Theme.textSecondary)
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel("Remove link preview").accessibilityIdentifier("preview-remove")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6).padding(.top, 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("preview-draft")
    }

    /// Looks for an address in what is written and builds its card on this phone (not for a request, not when the setting is off).
    private func refreshPreview() {
        previewTask?.cancel()
        guard previewsOn, onSendPreview != nil, drafts.isEmpty, let url = LinkPreviewMaker.firstURL(in: model.plainText) else {
            previewDraft = nil
            if LinkPreviewMaker.firstURL(in: model.plainText) == nil { dismissedURL = nil }
            return
        }
        if url == dismissedURL || previewDraft?.url == url { return }
        previewDraft = nil
        previewTask = Task {
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            #if DEBUG
            let demo = store.isDemo
            #else
            let demo = false
            #endif
            if let outgoing = await LinkPreviewMaker.make(for: url, demo: demo), !Task.isCancelled {
                previewDraft = PreviewDraft(url: url, outgoing: outgoing)
            }
        }
    }

    private func send() {
        let markdown = model.markdown()
        if drafts.isEmpty, let previewDraft, let onSendPreview, !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            onSendPreview(markdown, previewDraft.outgoing)
            self.previewDraft = nil
            dismissedURL = nil
            model.clear()
            return
        }
        if !drafts.isEmpty, let onSendAttachments {
            onSendAttachments(drafts.map(\.outgoing), markdown)
            drafts = []
            model.clear()
            return
        }
        guard !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        onSend(markdown)
        model.clear()
    }
}

/// Opens links from the messages inside it: a tapped link shows pressed for a moment, an https link opens
/// at once, any other (http, mailto) asks first.
struct LinkOpening: ViewModifier {
    @State private var pending: URL?
    @State private var pressed: URL?

    func body(content: Content) -> some View {
        content
            .environment(\.pressedLink, pressed)
            .environment(\.openURL, OpenURLAction { url in
                pressed = url
                Task { try? await Task.sleep(for: .milliseconds(350)); if pressed == url { pressed = nil } }
                if MessageRender.opensWithoutAsking(url) { return .systemAction }
                pending = url
                return .handled
            })
            .confirmationDialog("Open this link?", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), titleVisibility: .visible, presenting: pending) { url in
                Button("Open \(url.scheme == "mailto" ? "mail" : "link")") { UIApplication.shared.open(url) }
                    .accessibilityIdentifier("link-open")
                Button("Cancel", role: .cancel) {}.accessibilityIdentifier("link-dialog-cancel")
            } message: { url in
                Text(url.absoluteString)
            }
    }
}

extension View {
    func linkOpening() -> some View { modifier(LinkOpening()) }
}

/// "3 replies · 8:20 AM" with up to three replier avatars, under a message that has a thread.
struct ThreadSummaryRow: View {
    let messageID: String
    let thread: ThreadInfo
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                HStack(spacing: -6) {
                    ForEach(thread.repliers) { person in
                        AvatarView(person: person, size: 22)
                            .overlay(Circle().strokeBorder(Theme.canvas, lineWidth: 2))
                    }
                }
                Text(thread.summaryText)
                    .font(Theme.caption)
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                if thread.unread > 0 {
                    // New replies: an accent dot (the count is in the accessibility label).
                    Circle().fill(Theme.accent).frame(width: 9, height: 9)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .fixedSize()
            .background(Theme.surface, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(thread.summaryText)\(thread.unread > 0 ? ", \(thread.unread) new" : "")")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("thread-summary-\(messageID)")
    }
}
