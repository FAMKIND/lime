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

/// New post (LIME-188b, laid out as pages in LIME-188e). A **quick post**: your name, "What's on your mind?" at the top and growing down, the photos in a
/// row under the words, and the media bar above the keyboard (photos, camera, formatting, microphone) with the chips **Write an article** and
/// **Record**. An **article**: a page with the title (large), a one-line subtitle, and the body as the page itself; its bar above the keyboard puts a
/// **photo, camera picture or file in the text at the caret** (a block of its own), beside the formatting. Your jam is made on your first post.
struct JamComposeSheet: View {
    @Environment(ConversationStore.self) private var store
    @Environment(AccountSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var composer = RichComposerModel()
    @State private var photos: [DraftAttachment] = []          // a quick post's row
    @State private var articleFiles: [OutgoingAttachment] = []  // an article's, in the text by number
    @State private var clips: [OutgoingAttachment] = []         // recordings (video, voice)
    @State private var recordTitle = ""
    @State private var recordMode: Int?
    @State private var chooser: Chooser?
    @State private var article = JamDraft.shared.article
    @State private var title = JamDraft.shared.title
    @State private var subtitle = JamDraft.shared.subtitle
    @State private var posting = false
    @State private var problem: String?
    @FocusState private var focus: Field?

    private enum Field { case title, subtitle }
    private enum Chooser: String, Identifiable { case library, camera, files; var id: String { rawValue } }
    static let maxTitle = 120, maxSubtitle = 160

    private var hasClip: Bool { clips.contains { $0.mime.hasPrefix("video/") || $0.mime.hasPrefix("audio/") } }
    private var hasWords: Bool { !composer.plainText.replacingOccurrences(of: "\u{FFFC}", with: "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var hasPictures: Bool { composer.textView.map { !ComposerDocument.imageIndexes(in: $0.textStorage).isEmpty } ?? false }
    private var canPost: Bool {
        guard !posting else { return false }
        if article { return !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (hasWords || hasPictures) }
        return hasWords || !photos.isEmpty || !clips.isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if article { articleHead } else { quickHead }
                if let problem {
                    Text(problem).font(Theme.secondary).foregroundStyle(.red).padding(.horizontal, 20).padding(.top, 6).frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("jam-compose-problem")
                }
                if hasClip { clipsRow }
                GeometryReader { geo in
                    ZStack(alignment: .topLeading) {
                        RichComposerField(model: composer, maxHeight: geo.size.height, fills: true)
                            .onAppear { composer.hasText = false }
                        if !composer.hasText {
                            Text(article ? "Start writing an article\u{2026}" : "What\u{2019}s on your mind?").font(Theme.body).foregroundStyle(Theme.textSecondary)
                                .padding(.leading, 4).padding(.top, 8).allowsHitTesting(false).accessibilityHidden(true)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                if !article, !photos.isEmpty { photosRow }
            }
            .background(Theme.canvas)
            .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
            .navigationTitle(article ? "Article" : "New post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { close() }.accessibilityIdentifier("jam-compose-cancel") }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Post") { post() }.fontWeight(.semibold).disabled(!canPost).accessibilityIdentifier("jam-post")
                }
            }
            .sheet(item: Binding(get: { recordMode.map(RecordMode.init) }, set: { recordMode = $0?.mode })) { mode in
                JamRecorderSheet(title: $recordTitle, initialMode: mode.mode) { clips.append($0) }
            }
            .fullScreenCover(item: $chooser) { which in
                switch which {
                case .library:
                    MediaLibraryPicker(limit: max(1, 10 - (article ? articleFiles.count : photos.count)),
                                       onPick: { images, videos in chooser = nil; Task { await picked(images: images, videos: videos) } },
                                       onCancel: { chooser = nil }).ignoresSafeArea()
                case .camera:
                    CameraCapturePicker(onPhoto: { image in chooser = nil; Task { await picked(images: [image], videos: []) } },
                                        onVideo: { url in chooser = nil; Task { await picked(images: [], videos: [url]) } },
                                        onCancel: { chooser = nil }).ignoresSafeArea()
                case .files:
                    DocumentPicker(onPick: { urls in chooser = nil; Task { await picked(files: urls) } }, onCancel: { chooser = nil }).ignoresSafeArea()
                }
            }
            .task {
                // The draft's words go back into the field once it exists.
                try? await Task.sleep(for: .milliseconds(300))
                if !JamDraft.shared.markdown.isEmpty { composer.textView?.attributedText = ComposerDocument.attributed(fromMarkdown: JamDraft.shared.markdown); composer.didEdit() }
                if !article { composer.focus() }
            }
        }
    }

    private struct RecordMode: Identifiable { let mode: Int; var id: Int { mode } }

    // MARK: Heads

    private var quickHead: some View {
        HStack(spacing: 10) {
            AvatarView(person: store.meProvider(), size: 36).accessibilityHidden(true)
            Text(store.meProvider().name).font(Theme.font(.body, weight: .semibold)).foregroundStyle(Theme.text)
            Spacer()
        }
        .padding(.horizontal, 20).padding(.top, 12)
    }

    /// Title (large, up to 120), then a short subtitle (up to 160): Return in either moves on, neither ever holds the article.
    private var articleHead: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("Title", text: $title, axis: .vertical).font(Theme.font(.title2, weight: .bold)).lineLimit(1...3)
                .focused($focus, equals: .title).submitLabel(.next).onSubmit { focus = .subtitle }
                .onChange(of: title) { _, now in
                    if now.contains("\n") { title = now.replacingOccurrences(of: "\n", with: ""); focus = .subtitle }
                    else if now.count > Self.maxTitle { title = String(now.prefix(Self.maxTitle)) }
                }
                .accessibilityLabel("Title").accessibilityIdentifier("jam-article-title")
            TextField("Add a subtitle\u{2026}", text: $subtitle, axis: .vertical).font(Theme.font(.body)).foregroundStyle(Theme.textSecondary).lineLimit(1...2)
                .focused($focus, equals: .subtitle).submitLabel(.next).onSubmit { toBody() }
                .onChange(of: subtitle) { _, now in
                    if now.contains("\n") { subtitle = now.replacingOccurrences(of: "\n", with: ""); toBody() }
                    else if now.count > Self.maxSubtitle { subtitle = String(now.prefix(Self.maxSubtitle)) }
                }
                .accessibilityLabel("Subtitle").accessibilityIdentifier("jam-article-subtitle")
            Divider().overlay(Theme.hairline).padding(.top, 6)
        }
        .padding(.horizontal, 20).padding(.top, 12)
    }

    /// Return in the subtitle: the caret goes to the article itself.
    private func toBody() {
        focus = nil
        DispatchQueue.main.async { composer.focus() }
    }

    private var photosRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(photos.enumerated()), id: \.element.id) { index, draft in
                    ZStack(alignment: .topTrailing) {
                        Group {
                            if let preview = draft.preview { Image(uiImage: preview).resizable().scaledToFill() } else { Rectangle().fill(Theme.surface) }
                        }
                        .frame(width: 84, height: 84).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        Button { photos.remove(at: index) } label: {
                            Image(systemName: "xmark.circle.fill").font(.system(size: 22)).symbolRenderingMode(.palette).foregroundStyle(.white, .black.opacity(0.6)).frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("Remove photo \(index + 1)").accessibilityIdentifier("jam-photo-remove-\(index)")
                    }
                    .accessibilityIdentifier("jam-photo-\(index)")
                }
            }
            .padding(.horizontal, 20)
        }
        .frame(height: 96).accessibilityIdentifier("jam-photos")
    }

    private var clipsRow: some View {
        HStack {
            ForEach(Array(clips.enumerated()), id: \.offset) { index, clip in
                Button { clips.remove(at: index) } label: {
                    Label(clip.mime.hasPrefix("video/") ? "Video" : "Voice", systemImage: "xmark.circle.fill")
                        .font(Theme.secondary).foregroundStyle(Theme.text).padding(.horizontal, 12).frame(minHeight: 36).background(Theme.surface, in: Capsule())
                }
                .accessibilityLabel("Remove \(clip.mime.hasPrefix("video/") ? "video" : "voice recording")").accessibilityIdentifier("jam-recorded-\(index)")
            }
            Spacer()
        }
        .padding(.horizontal, 20).padding(.top, 8)
    }

    // MARK: The bar above the keyboard

    private var bottomBar: some View {
        VStack(spacing: 0) {
            if composer.showsStrip { FormattingToolbar(model: composer).transition(.opacity) }
            if !article {
                HStack(spacing: 8) {
                    chip("Write an article", system: "doc.text", id: "jam-write-article") { article = true }
                    chip("Record", system: "video", id: "jam-record") { recordMode = 0 }
                    Spacer()
                }
                .padding(.horizontal, 16).padding(.bottom, 4)
            }
            HStack(spacing: 2) {
                tool("photo.on.rectangle", "Add photos", id: "jam-add-photo") { choose(.library) }
                tool("camera", "Camera", id: "jam-add-camera") { choose(.camera) }
                if article { tool("paperclip", "Add a file", id: "jam-add-file") { choose(.files) } }
                tool("textformat", "Formatting", id: "jam-format", on: composer.toolbarVisible) { composer.formattingTapped() }
                if !article { tool("mic", "Record your voice", id: "jam-add-voice") { recordMode = 1 } }
                Spacer()
                if article { chipPlain("Exit article mode", id: "jam-exit-article") { article = false } }
                tool(composer.editing ? "keyboard.chevron.compact.down" : "keyboard", composer.editing ? "Hide keyboard" : "Show keyboard", id: "jam-hide-keyboard") { composer.toggleKeyboard() }
            }
            .padding(.horizontal, 8).frame(minHeight: 48)
            .background(.bar)
        }
    }

    private func tool(_ symbol: String, _ label: String, id: String, on: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 20)).foregroundStyle(Theme.text).frame(width: 44, height: 44)
                .background(on ? Theme.surface : .clear, in: Circle())
        }
        .accessibilityLabel(label).accessibilityIdentifier(id).accessibilityAddTraits(on ? [.isSelected] : [])
    }

    private func chip(_ label: String, system: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: system).font(Theme.secondary).foregroundStyle(Theme.text)
                .padding(.horizontal, 12).frame(minHeight: 40).background(Theme.surface, in: Capsule())
        }
        .buttonStyle(.plain).accessibilityIdentifier(id)
    }

    private func chipPlain(_ label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(label).font(Theme.secondary).foregroundStyle(Theme.text).padding(.horizontal, 10).frame(minHeight: 44) }
            .buttonStyle(.plain).accessibilityIdentifier(id)
    }

    // MARK: Adding pictures

    /// Opens a picker. (Demo mode, for UI tests: no system picker; a made-up picture is added at once.)
    private func choose(_ which: Chooser) {
        #if DEBUG
        if store.isDemo {
            Task {
                if which == .files { insertIntoArticle(OutgoingAttachment(bytes: Data("demo".utf8), name: "Permission slip.pdf", mime: "application/pdf", width: nil, height: nil, durationMs: nil, thumb: Data(), poster: Data()), preview: Self.fileCard(named: "Permission slip.pdf")) }
                else { await picked(images: [UIImage(data: store.demoJamImage("p")!)!], videos: []) }
            }
            return
        }
        #endif
        chooser = which
    }

    /// Photos and videos from the library or the camera. A quick post puts photos in the row (a video is a recording); an article puts each photo into
    /// the text where the caret is.
    private func picked(images: [UIImage], videos: [URL]) async {
        problem = nil
        for image in images {
            if article {
                guard articleFiles.count < 10 else { problem = ConversationStore.JamPostFailure.tooManyFiles.message; break }
                if let item = await Task.detached(priority: .userInitiated, operation: { AttachmentProcessing.photo(image) }).value {
                    insertIntoArticle(item, preview: image)
                }
            } else if photos.count < 10 {
                let made = await Task.detached(priority: .userInitiated) { () -> (OutgoingAttachment, UIImage)? in
                    guard let item = AttachmentProcessing.photo(image) else { return nil }
                    return (item, PhotoProcessing.crop(image, viewport: 168, scale: 1, offset: .zero))
                }.value
                if let made { photos.append(DraftAttachment(outgoing: made.0, preview: made.1)) }
            }
        }
        for url in videos {
            defer { try? FileManager.default.removeItem(at: url) }
            if article { problem = "Videos go in a recording. Use Record on a new post."; continue }
            if let made = try? await VideoProcessing.prepare(url, progress: { _ in }) { clips.append(made.item) } else { problem = "Couldn\u{2019}t use that video." }
        }
    }

    private func picked(files urls: [URL]) async {
        for url in urls where articleFiles.count < 10 {
            do {
                let item = try await Task.detached(priority: .userInitiated) { try AttachmentProcessing.file(at: url) }.value
                if item.mime.hasPrefix("image/"), let image = UIImage(data: item.bytes) { insertIntoArticle(item, preview: image) }
                else { insertIntoArticle(item, preview: Self.fileCard(named: item.name)) }
            } catch AttachmentProcessing.Problem.tooLarge { problem = ConversationStore.JamPostFailure.fileTooLarge.message } catch {}
        }
    }

    /// Puts the file in the article's list and its picture (or a card for a file) into the text at the caret.
    private func insertIntoArticle(_ item: OutgoingAttachment, preview: UIImage) {
        guard let view = composer.textView else { return }
        articleFiles.append(item)
        let width = max(120, view.bounds.width - 16)
        let small = preview.preparingThumbnail(of: CGSize(width: 900, height: 900)) ?? preview
        let caret = ComposerDocument.insertImage(small, index: articleFiles.count - 1, into: view.textStorage, at: view.selectedRange.location, width: width)
        view.selectedRange = NSRange(location: caret, length: 0)
        view.delegate?.textViewDidChange?(view)
    }

    /// A file's stand-in in the text: a card with its name.
    private static func fileCard(named name: String) -> UIImage {
        let size = CGSize(width: 600, height: 120)
        return UIGraphicsImageRenderer(size: size).image { context in
            UIColor.secondarySystemBackground.setFill()
            UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 24).fill()
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byTruncatingMiddle
            (name.isEmpty ? "File" : name).draw(in: CGRect(x: 120, y: 40, width: 450, height: 44),
                                               withAttributes: [.font: UIFont.systemFont(ofSize: 34, weight: .semibold), .foregroundColor: UIColor.label, .paragraphStyle: paragraph])
            UIImage(systemName: "doc.fill")?.withTintColor(.label, renderingMode: .alwaysOriginal).draw(in: CGRect(x: 36, y: 28, width: 56, height: 64))
        }
    }

    // MARK: Closing and posting

    private func close() {
        let draft = JamDraft.shared
        let text = hasWords && !hasPictures ? composer.markdown() : ""
        draft.article = article; draft.title = title; draft.subtitle = subtitle; draft.markdown = text
        dismiss()
    }

    private func post() {
        var files: [OutgoingAttachment] = []
        var markdown = ""
        if article, let view = composer.textView {
            // Only the files still in the text go, numbered in the order they appear.
            let copy = NSMutableAttributedString(attributedString: view.textStorage)
            var renumber: [Int: Int] = [:]
            copy.enumerateAttribute(.limeImage, in: NSRange(location: 0, length: copy.length)) { value, range, _ in
                guard let old = value as? Int, articleFiles.indices.contains(old) else { return }
                if renumber[old] == nil { renumber[old] = files.count; files.append(articleFiles[old]) }
                copy.addAttribute(.limeImage, value: renumber[old] ?? 0, range: range)
            }
            markdown = ComposerDocument.markdown(from: copy)
        } else {
            markdown = composer.markdown()
            files = photos.map(\.outgoing)
        }
        files += clips
        let kind = hasClip ? "record" : article ? "article" : "quick"
        let headline = article ? title : recordTitle
        problem = nil
        posting = true
        Task {
            let result = await store.publishJamPost(kind: kind, title: headline, subtitle: article ? subtitle : "", markdown: markdown, items: files, about: session.profile?.aboutText ?? "")
            posting = false
            switch result {
            case .success: JamDraft.shared.clear(); dismiss()
            case .failure(let failure): problem = failure.message   // the words, the photos and the title all stay
            }
        }
    }
}

/// Record (LIME-188b): a video from the camera, or a voice clip, with an optional title; **Next** hands it back to the post.
struct JamRecorderSheet: View {
    @Binding var title: String
    var initialMode = 0
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
                mode = initialMode
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
