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
    @State private var coauthors: [Person] = []
    @State private var choosingCoauthors = false
    @State private var postingAs = false
    @State private var article = JamDraft.shared.article
    @State private var title = JamDraft.shared.title
    @State private var subtitle = JamDraft.shared.subtitle
    @State private var posting = false
    @State private var problem: String?
    @FocusState private var focus: Field?
    @AppStorage(LinkPreviewSetting.key) private var previewsOn = true
    @State private var link: JamLinkDraft?
    @State private var dismissedLink: URL?
    @State private var linkTask: Task<Void, Never>?

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
            Group {
                if article { articlePage } else { quickPage }
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
            .onChange(of: composer.plainText) { refreshLink() }
            .onChange(of: previewsOn) { refreshLink() }
            .sheet(isPresented: $choosingCoauthors) { JamCoauthorPicker(selected: $coauthors) }
            .sheet(item: $composer.linkRequest) { request in LinkSheet(request: request, composer: composer) }
            .sheet(item: $composer.buttonRequest) { _ in ButtonSheet(composer: composer) }
            .fullScreenCover(item: Binding(get: { recordMode.map(RecordMode.init) }, set: { recordMode = $0?.mode })) { mode in
                if mode.mode == 2 {
                    // Audio for the article: the recorder with no title or co-host steps; the clip goes into the text at the caret.
                    PodcastRecorder(title: $recordTitle, coauthors: $coauthors, camera: false, forArticle: true) { clip in
                        insertIntoArticle(clip, preview: Self.fileCard(named: "Audio recording \(VoiceFormat.clock(Double(clip.durationMs ?? 0) / 1000))"))
                    }
                } else {
                    PodcastRecorder(title: $recordTitle, coauthors: $coauthors, camera: mode.mode == 0) { clips = [$0] }
                }
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
                if !JamDraft.shared.markdown.isEmpty { composer.textView?.attributedText = ComposerDocument.attributed(fromMarkdown: JamDraft.shared.markdown, post: true); composer.didEdit() }
                if !article { composer.focus() }
            }
        }
    }

    /// A quick post: your name, the words at the top growing down, photos under them.
    private var quickPage: some View {
        VStack(spacing: 0) {
            quickHead
            problemText
            if hasClip { clipsRow }
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    RichComposerField(model: composer, maxHeight: geo.size.height, fills: true)
                        .onAppear { composer.hasText = false; composer.isPost = true }
                    if !composer.hasText {
                        Text("What\u{2019}s on your mind?").font(Theme.body).foregroundStyle(Theme.placeholder)
                            .padding(.leading, 4).padding(.top, 8).allowsHitTesting(false).accessibilityHidden(true)
                    }
                }
                .padding(.horizontal, 16)
            }
            if !photos.isEmpty { photosRow }
            if let link { linkRow(link) }
        }
    }

    /// An article is one page (LIME-188n): the name line, the title, the subtitle and the body scroll together, under the top bar, and the body is as
    /// tall as its text (a text view that does not scroll itself; it keeps the page scrolled to the caret). One scroll view, not a field with its own.
    private var articlePage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                articleHead
                problemText
                if hasClip { clipsRow }
                ZStack(alignment: .topLeading) {
                    RichComposerField(model: composer, selfSizing: true)
                        .onAppear { composer.hasText = false; composer.isPost = true }
                    if !composer.hasText {
                        Text("Start writing an article\u{2026}").font(Theme.body).foregroundStyle(Theme.placeholder)
                            .padding(.leading, 4).padding(.top, 8).allowsHitTesting(false).accessibilityHidden(true)
                    }
                }
                .padding(.horizontal, 16).padding(.top, 16)
                if let link { linkRow(link) }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .accessibilityIdentifier("jam-article-page")
    }

    @ViewBuilder
    private var problemText: some View {
        if let problem {
            Text(problem).font(Theme.secondary).foregroundStyle(.red).padding(.horizontal, 20).padding(.top, 6).frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("jam-compose-problem")
        }
    }

    /// Switching between a quick post and an article keeps what is written (the field is a new view in each).
    private func setArticle(_ on: Bool) {
        let saved = composer.textView.map { NSAttributedString(attributedString: $0.attributedText) }
        article = on
        guard let saved, saved.length > 0 else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            composer.textView?.attributedText = saved
            composer.didEdit()
        }
    }

    /// Nothing written or added yet: the "Exit article mode" pill shows.
    private var isEmptyArticle: Bool {
        title.isEmpty && subtitle.isEmpty && !hasWords && !hasPictures && link == nil && clips.isEmpty
    }

    private struct RecordMode: Identifiable { let mode: Int; var id: Int { mode } }

    // MARK: Heads

    private var quickHead: some View {
        VStack(alignment: .leading, spacing: 8) {
            postLine
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20).padding(.top, 12)
    }

    /// Who the post is from (LIME-188f): you, for now; the sheet is built to list a school or subject group later, when shared jams exist.
    private var postAsChip: some View {
        Button { postingAs = true } label: {
            HStack(spacing: 8) {
                AvatarView(person: store.meProvider(), size: 32).accessibilityHidden(true)
                Text(store.meProvider().name).font(Theme.font(.subheadline, weight: .semibold)).foregroundStyle(Theme.text)
                Image(systemName: "chevron.down").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.textSecondary)
            }
            .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Posting as \(store.meProvider().name)").accessibilityHint("Choose who this post is from").accessibilityIdentifier("jam-post-as")
        .sheet(isPresented: $postingAs) { PostAsSheet() }
    }

    /// One line: who the post is from, a person-with-plus to add a co-author, and the people added as small overlapping avatars (tap to change them).
    private var postLine: some View {
        HStack(spacing: 2) {
            postAsChip
            Button { choosingCoauthors = true } label: {
                Image(systemName: "person.badge.plus").font(.system(size: 18)).foregroundStyle(Theme.textSecondary).frame(width: 44, height: 44)
            }
            .buttonStyle(.plain).accessibilityLabel("Add co-author").accessibilityIdentifier("jam-add-coauthor")
            if !coauthors.isEmpty {
                Button { choosingCoauthors = true } label: {
                    HStack(spacing: -8) {
                        ForEach(coauthors) { person in
                            AvatarView(person: person, size: 28).overlay(Circle().strokeBorder(Theme.canvas, lineWidth: 2)).accessibilityHidden(true)
                        }
                    }
                    .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Co-authors: \(coauthors.map(\.name).joined(separator: ", "))").accessibilityHint("Opens the list to change them")
                .accessibilityIdentifier("jam-coauthors")
            }
            Spacer(minLength: 0)
        }
    }

    /// Title (large, up to 120), then a short subtitle (up to 160): Return in either moves on, neither ever holds the article.
    private var articleHead: some View {
        VStack(alignment: .leading, spacing: 4) {
            postLine.padding(.bottom, 6)
            TextField("Title", text: $title, prompt: Text("Title").foregroundColor(Theme.placeholderLarge), axis: .vertical).font(Theme.font(.title2, weight: .bold)).lineLimit(1...3)
                .focused($focus, equals: .title).submitLabel(.next).onSubmit { focus = .subtitle }
                .onChange(of: title) { _, now in
                    if now.contains("\n") { title = now.replacingOccurrences(of: "\n", with: ""); focus = .subtitle }
                    else if now.count > Self.maxTitle { title = String(now.prefix(Self.maxTitle)) }
                }
                .accessibilityLabel("Title").accessibilityIdentifier("jam-article-title")
            TextField("Add a subtitle\u{2026}", text: $subtitle, prompt: Text("Add a subtitle\u{2026}").foregroundColor(Theme.placeholder), axis: .vertical).font(Theme.font(.body)).foregroundStyle(Theme.textSecondary).lineLimit(1...2)
                .focused($focus, equals: .subtitle).submitLabel(.next).onSubmit { toBody() }
                .onChange(of: subtitle) { _, now in
                    if now.contains("\n") { subtitle = now.replacingOccurrences(of: "\n", with: ""); toBody() }
                    else if now.count > Self.maxSubtitle { subtitle = String(now.prefix(Self.maxSubtitle)) }
                }
                .accessibilityLabel("Subtitle").accessibilityIdentifier("jam-article-subtitle")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20).padding(.top, 12)
    }

    /// Return in the subtitle: the caret goes to the article itself.
    private func toBody() {
        focus = nil
        DispatchQueue.main.async { composer.focus() }
    }

    // MARK: A link's card

    struct JamLinkDraft: Equatable { let url: URL; let preview: OutgoingPreview }

    private func linkRow(_ draft: JamLinkDraft) -> some View {
        HStack(alignment: .top, spacing: 8) {
            LinkCardView(title: draft.preview.title, site: draft.preview.site, image: UIImage(data: draft.preview.image), width: 220)
            Button { dismissedLink = draft.url; link = nil } label: {
                Image(systemName: "xmark.circle.fill").font(.system(size: 22)).foregroundStyle(Theme.textSecondary).frame(width: 44, height: 44)
            }
            .accessibilityLabel("Remove link preview").accessibilityIdentifier("jam-link-remove")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20).padding(.vertical, 6)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("jam-link-draft")
    }

    /// The first address in the words gets its card, built on this phone (the same as a chat's, and off when the setting is off).
    private func refreshLink() {
        linkTask?.cancel()
        guard previewsOn, let url = LinkPreviewMaker.firstURL(in: composer.plainText) else {
            link = nil
            if LinkPreviewMaker.firstURL(in: composer.plainText) == nil { dismissedLink = nil }
            return
        }
        if url == dismissedLink || link?.url == url { return }
        link = nil
        linkTask = Task {
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            #if DEBUG
            let demo = store.isDemo
            #else
            let demo = false
            #endif
            if let preview = await LinkPreviewMaker.make(for: url, demo: demo), !Task.isCancelled { link = JamLinkDraft(url: url, preview: preview) }
        }
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
                    Label("Recording \(VoiceFormat.clock(Double(clip.durationMs ?? 0) / 1000))", systemImage: "xmark.circle.fill")
                        .font(Theme.secondary).foregroundStyle(Theme.text).padding(.horizontal, 12).frame(minHeight: 36).background(Theme.surface, in: Capsule())
                }
                .accessibilityLabel("Remove the \(clip.mime.hasPrefix("video/") ? "video" : "audio") recording").accessibilityIdentifier("jam-recorded-\(index)")
            }
            Spacer()
        }
        .padding(.horizontal, 20).padding(.top, 8)
    }

    // MARK: The bar above the keyboard

    private var bottomBar: some View {
        VStack(spacing: 0) {
            if article, isEmptyArticle {
                Button { setArticle(false) } label: {
                    Label("Exit article mode", systemImage: "arrow.uturn.backward").font(Theme.secondary).foregroundStyle(Theme.text)
                        .padding(.horizontal, 14).frame(minHeight: 44).background(Theme.surface, in: Capsule())
                }
                .buttonStyle(.plain).padding(.bottom, 6).accessibilityIdentifier("jam-exit-article")
            }
            if composer.showsStrip { FormattingToolbar(model: composer).transition(.opacity) }
            if !article {
                HStack(spacing: 8) {
                    chip("Write an article", system: "doc.text", id: "jam-write-article") { setArticle(true) }
                    chip("Record", system: "waveform", id: "jam-record") { recordMode = 1 }
                    Spacer()
                }
                .padding(.horizontal, 16).padding(.bottom, 4)
            }
            HStack(spacing: 2) {
                if article {
                    plusMenu
                } else {
                    tool("photo.on.rectangle", "Add photos", id: "jam-add-photo") { choose(.library) }
                    tool("camera", "Camera", id: "jam-add-camera") { choose(.camera) }
                }
                tool("textformat", "Formatting", id: "jam-format", on: composer.toolbarVisible) { composer.formattingTapped() }
                if !article { tool("waveform", "Record your voice", id: "jam-add-voice") { recordMode = 1 } }
                Spacer()
                tool(composer.editing ? "keyboard.chevron.compact.down" : "keyboard", composer.editing ? "Hide keyboard" : "Show keyboard", id: "jam-hide-keyboard") { composer.toggleKeyboard() }
            }
            .padding(.horizontal, 8).frame(minHeight: 48)
            .background(.bar)
        }
    }

    /// The article's ⊕: a menu above the bar. Image and Video (the library; "Take a photo or video" as well), Audio (record, or choose a file), then
    /// Button, Divider and Freewall. Each goes in at the caret. (Files other than audio are not offered in v1.)
    private var plusMenu: some View {
        Menu {
            Section {
                Button { choose(.library) } label: { Label("Image", systemImage: "photo") }.accessibilityIdentifier("jam-menu-image")
                Button { choose(.library) } label: { Label("Video", systemImage: "video") }.accessibilityIdentifier("jam-menu-video")
                Button { choose(.camera) } label: { Label("Take a photo or video", systemImage: "camera") }.accessibilityIdentifier("jam-menu-camera")
                Menu {
                    Button { recordMode = 2 } label: { Label("Record", systemImage: "waveform") }.accessibilityIdentifier("jam-menu-audio-record")
                    Button { choose(.files) } label: { Label("Choose a file", systemImage: "doc") }.accessibilityIdentifier("jam-menu-audio-file")
                } label: { Label("Audio", systemImage: "waveform.circle") }
                    .accessibilityIdentifier("jam-menu-audio")
            }
            Section {
                Button { composer.buttonRequest = ButtonRequest() } label: { Label("Button", systemImage: "rectangle.and.hand.point.up.left") }.accessibilityIdentifier("jam-menu-button")
                Button { composer.insertRule("divider") } label: { Label("Divider", systemImage: "minus") }.accessibilityIdentifier("jam-menu-divider")
                Button { composer.insertRule("freewall") } label: { Label("Freewall", systemImage: "lock.open") }
                    .disabled(composer.textView.map { ComposerDocument.hasFreewall(in: $0.textStorage) } ?? false)
                    .accessibilityIdentifier("jam-menu-freewall")
            }
        } label: {
            Image(systemName: "plus").font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.canvas).frame(width: 36, height: 36).background(Theme.text, in: Circle()).frame(width: 44, height: 44)
        }
        .accessibilityLabel("Add").accessibilityIdentifier("jam-add")
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
                else if which == .camera, article {
                    let clip = ChatComposer.demoVideoDraft
                    insertIntoArticle(clip.outgoing, preview: clip.preview ?? Self.fileCard(named: "Video"))
                } else { await picked(images: [UIImage(data: store.demoJamImage("p")!)!], videos: []) }
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
            #if DEBUG
            if store.isDemo {
                let clip = ChatComposer.demoVideoDraft
                if article { insertIntoArticle(clip.outgoing, preview: clip.preview ?? Self.fileCard(named: "Video")) } else { clips.append(clip.outgoing) }
                continue
            }
            #endif
            guard let made = try? await VideoProcessing.prepare(url, maxBytes: ConversationStore.jamFileLimit - 256 * 1024, progress: { _ in }) else { problem = "Couldn\u{2019}t use that video."; continue }
            if article {
                // A video stands in the text like a photo (its cover frame shows while you write).
                guard articleFiles.count < 10 else { problem = ConversationStore.JamPostFailure.tooManyFiles.message; continue }
                insertIntoArticle(made.item, preview: made.poster ?? Self.fileCard(named: made.item.name))
            } else {
                clips.append(made.item)
            }
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
            markdown = ComposerDocument.markdown(from: copy, post: true)
        } else {
            markdown = composer.markdown()
            files = photos.map(\.outgoing)
        }
        files += clips
        if let link { files.append(JamLink.attachment(link.preview)) }
        let kind = hasClip ? "record" : article ? "article" : "quick"
        let headline = article ? title : recordTitle
        problem = nil
        posting = true
        Task {
            let result = await store.publishJamPost(kind: kind, title: headline, subtitle: article ? subtitle : "", markdown: markdown, items: files, coauthors: coauthors.map(\.id), about: session.profile?.aboutText ?? "")
            posting = false
            switch result {
            case .success: JamDraft.shared.clear(); dismiss()
            case .failure(let failure): problem = failure.message   // the words, the photos and the title all stay
            }
        }
    }
}

/// Who the post is from (LIME-188f): you. A school or subject group will be listed here when shared jams exist.
struct PostAsSheet: View {
    @Environment(ConversationStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Button { dismiss() } label: {
                    HStack(spacing: 12) {
                        AvatarView(person: store.meProvider(), size: 40).accessibilityHidden(true)
                        Text(store.meProvider().name).font(Theme.body).foregroundStyle(Theme.text)
                        Spacer()
                        Image(systemName: "checkmark").foregroundStyle(Theme.text)
                    }
                    .frame(minHeight: 48)
                }
                .accessibilityLabel("\(store.meProvider().name), selected").accessibilityIdentifier("jam-post-as-me")
                Text("Posting as a school or a subject group comes with shared jams.").font(Theme.caption).foregroundStyle(Theme.textSecondary)
            }
            .navigationTitle("Post as").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium])
    }
}

/// Add co-authors (or co-hosts) from your contacts (LIME-188f/g): each is asked, and the credit shows once they accept.
struct JamCoauthorPicker: View {
    @Binding var selected: [Person]
    /// "Add co-hosts" for a recording; with none chosen the button says Skip.
    var title = "Add co-author"
    @Environment(ConversationStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var people: [Person] {
        let all = store.coauthorChoices
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? all : all.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        NavigationStack {
            List(people) { person in
                let on = selected.contains { $0.id == person.id }
                Button {
                    if on { selected.removeAll { $0.id == person.id } } else if selected.count < 4 { selected.append(person) }
                } label: {
                    HStack(spacing: 12) {
                        AvatarView(person: person, size: 40).accessibilityHidden(true)
                        Text(person.name).font(Theme.body).foregroundStyle(Theme.text)
                        Spacer()
                        if on { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.text) }
                    }
                    .frame(minHeight: 48)
                }
                .accessibilityAddTraits(on ? [.isSelected] : [])
                .accessibilityIdentifier("jam-coauthor-choice-\(person.id)")
            }
            .listStyle(.plain)
            .searchable(text: $query, prompt: "Search your contacts")
            .overlay { if store.coauthorChoices.isEmpty { Text("Your contacts show here.").font(Theme.body).foregroundStyle(Theme.textSecondary) } }
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(selected.isEmpty && title != "Add co-author" ? "Skip" : "Done") { dismiss() }.fontWeight(.semibold).accessibilityIdentifier("jam-coauthor-done") } }
            .safeAreaInset(edge: .bottom) {
                Text("They are asked first. \u{201C}with <name>\u{201D} shows once they accept.").font(Theme.caption).foregroundStyle(Theme.textSecondary).padding(.bottom, 8)
            }
        }
        .presentationDetents([.large])
    }
}
