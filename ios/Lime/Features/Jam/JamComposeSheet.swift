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
    /// The shared draft behind this unfinished article (LIME-233c), so closing and reopening the sheet finds it again.
    var draftID: String?
    var isEmpty: Bool { title.isEmpty && subtitle.isEmpty && markdown.isEmpty }
    func clear() { article = false; title = ""; subtitle = ""; markdown = ""; draftID = nil }
}

/// New post (LIME-188b, laid out as pages in LIME-188e). A **quick post**: your name, "What's on your mind?" at the top and growing down, the photos in a
/// row under the words, and the media bar above the keyboard (photos, camera, formatting, microphone) with the chips **Write an article** and
/// **Record**. An **article**: a page with the title (large), a one-line subtitle, and the body as the page itself; its bar above the keyboard puts a
/// **photo, camera picture or file in the text at the caret** (a block of its own), beside the formatting. Your jam is made on your first post.
struct JamComposeSheet: View {
    /// A post of mine being edited (LIME-195): the screen opens filled in and **Update** replaces the post in place. Its pictures and files stay as
    /// they are; its words, title and subtitle change.
    var editing: JamPostInfo? = nil
    /// A shared draft to write in (LIME-233d): an invitation accepted, or the post's ⋯ "Open draft".
    var openDraft: String? = nil
    @Environment(ConversationStore.self) private var store
    @Environment(AccountSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var composer = RichComposerModel()
    /// The article's shared draft (LIME-233c): made on the first change of an article, or found for a post being edited.
    @State private var coedit: CoEditSession?
    @State private var showingAuthors = false
    /// Landscape on an iPhone, or any window short of height: the cards move into the keyboard bar's row so nothing floats over the text (LIME-236d).
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    private var compact: Bool { verticalSizeClass == .compact }
    /// Where this author's caret is in the title and subtitle (characters), for the other authors' screens.
    @State private var titleCaret = (caret: 0, end: 0)
    @State private var subtitleCaret = (caret: 0, end: 0)
    @State private var photos: [DraftAttachment] = []          // a quick post's row
    @State private var articleFiles: [OutgoingAttachment] = []  // an article's, in the text by number
    @State private var clips: [OutgoingAttachment] = []         // recordings (video, voice)
    @State private var captions: [CaptionKey: CaptionDraft] = [:]
    @State private var editingCaptions: CaptionKey?
    @State private var recordTitle = ""
    @State private var recordSubtitle = ""
    @State private var recordDetails = ""
    @State private var recordCover: OutgoingAttachment?
    // An article's cover (LIME-219): one you add or pick from its photos, else the first photo or video poster.
    @State private var articleCover: OutgoingAttachment?
    @State private var coverImage: UIImage?
    @State private var coverRemoved = false
    @State private var pickingCover = false
    @State private var choosingArticlePhoto = false
    @State private var viewingCover = false
    @State private var headingOpen = false
    @State private var recordMode: Int?
    @State private var chooser: Chooser?
    @State private var coauthors: [Person] = []
    /// People asked who have not answered (shown dimmed on the org tile, LIME-215b).
    @State private var pendingHosts: [Person] = []
    @State private var choosingCoauthors = false
    @State private var editingButton: Int?
    @State private var postingAs = false
    /// nil: posted as me; otherwise the id of my jam (LIME-188q).
    @State private var postAsJam: String?
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

    /// The first name of the one who publishes this shared article.
    private var coeditWriterName: String {
        guard let writer = coedit?.peers.status?.writer, !writer.isEmpty else { return "The writer" }
        return store.teacher(writer).name.split(separator: " ").first.map(String.init) ?? "The writer"
    }
    /// Which media a set of captions is for: the recording (or video) of a quick post, or a file in an article's list.
    enum CaptionKey: Hashable, Identifiable {
        case clip(Int), article(Int)
        var id: String { switch self { case .clip(let i): "clip\(i)"; case .article(let i): "article\(i)" } }
    }
    private enum Chooser: String, Identifiable { case library, camera, files; var id: String { rawValue } }
    static let maxTitle = 120, maxSubtitle = 160

    private var hasClip: Bool { clips.contains { $0.mime.hasPrefix("video/") || $0.mime.hasPrefix("audio/") } }
    private var hasWords: Bool { !composer.plainText.replacingOccurrences(of: "\u{FFFC}", with: "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var hasPictures: Bool { composer.textView.map { !ComposerDocument.imageIndexes(in: $0.textStorage).isEmpty } ?? false }
    private var canPost: Bool {
        guard !posting else { return false }
        if let editing { return (editing.kind != "article" || !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) && (hasWords || hasPictures || editing.kind == "record" || !store.jamAttachments(editing.postId).isEmpty) }
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
            #if DEBUG
            .overlay(alignment: .topTrailing) { coeditProbe }
            #endif
            .navigationTitle(editing != nil ? "Edit" : article ? "" : "New post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { close() }.accessibilityIdentifier("jam-compose-cancel") }
                ToolbarItem(placement: .confirmationAction) {
                    HStack(spacing: 8) {
                        // The authors, like Google Docs, then what this author may do: the writer posts; a co-author says Ready, then Done (LIME-233g).
                        if let coedit { CoEditAvatars(session: coedit) { showingAuthors = true } }
                        if coedit?.isCoAuthorOnly == true {
                            if let coedit, coedit.peers.status?.publishedAt == nil {
                                Button { coedit.toggleReady() } label: { Text(coedit.peers.iAmReady ? "Ready \u{2713}" : "Ready") }
                                    .accessibilityLabel(coedit.peers.iAmReady ? "Ready, tell the writer you are not" : "Ready")
                                    .accessibilityHint("\(coeditWriterName) publishes this article. Tells them you are done")
                                    .accessibilityIdentifier("coedit-ready")
                            }
                            Button("Done") { close() }.fontWeight(.semibold).accessibilityIdentifier("jam-coedit-done")
                        } else if editing != nil {
                            Button("Update") { update() }.fontWeight(.semibold).disabled(!canPost).accessibilityIdentifier("jam-update")
                        } else {
                            Button("Post") { post() }.fontWeight(.semibold).disabled(!canPost).accessibilityIdentifier("jam-post")
                        }
                    }
                }
            }
            .sheet(isPresented: $showingAuthors) { if let coedit { CoEditAuthorsSheet(session: coedit) } }
            .onChange(of: composer.plainText) { refreshLink() }
            .onChange(of: previewsOn) { refreshLink() }
            .sheet(isPresented: $choosingCoauthors) { JamCoauthorPicker(selected: $coauthors) }
            .sheet(isPresented: $choosingArticlePhoto) { ArticlePhotoPicker(load: articlePhotos) { setCover($0); choosingArticlePhoto = false } }
            .fullScreenCover(isPresented: $pickingCover) {
                MediaLibraryPicker(limit: 1, onPick: { images, _ in pickingCover = false; if let image = images.first { setCover(image) } }, onCancel: { pickingCover = false }).ignoresSafeArea()
            }
            .fullScreenCover(isPresented: $viewingCover) {
                ZStack(alignment: .topTrailing) {
                    Color.black.ignoresSafeArea().accessibilityIdentifier("jam-cover-viewer")
                    if let coverImage { Image(uiImage: coverImage).resizable().scaledToFit().ignoresSafeArea().accessibilityLabel("Cover, full size") }
                    Button { viewingCover = false } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 30)).foregroundStyle(.white).frame(width: 44, height: 44) }
                        .padding().accessibilityLabel("Close").accessibilityIdentifier("jam-cover-close")
                }
                .onTapGesture { viewingCover = false }
            }
            .sheet(item: $editingCaptions) { key in
                CaptionsEditor(draft: Binding(get: { captions[key] ?? CaptionDraft(making: false) }, set: { captions[key] = $0 }))
            }
            .sheet(item: $composer.linkRequest) { request in LinkSheet(request: request, composer: composer) }
            .sheet(item: $composer.buttonRequest) { _ in ButtonSheet(composer: composer) }
            .sheet(isPresented: Binding(get: { editingButton != nil }, set: { if !$0 { editingButton = nil } })) { ButtonSheet(composer: composer, editing: editingButton) }
            .confirmationDialog(composer.blockMenu?.kind.short ?? "Block", isPresented: Binding(get: { composer.blockMenu != nil }, set: { if !$0 { composer.blockMenu = nil } }), titleVisibility: .visible, presenting: composer.blockMenu) { request in
                Button("Move up") { composer.moveBlock(request.index, by: -1) }.accessibilityIdentifier("block-move-up")
                Button("Move down") { composer.moveBlock(request.index, by: 1) }.accessibilityIdentifier("block-move-down")
                if case .button = request.kind { Button("Edit") { editingButton = request.index }.accessibilityIdentifier("block-edit") }
                Button("Delete", role: .destructive) { composer.deleteBlock(request.index) }.accessibilityIdentifier("block-delete")
                Button("Cancel", role: .cancel) {}
            }
            .fullScreenCover(item: Binding(get: { recordMode.map(RecordMode.init) }, set: { recordMode = $0?.mode })) { mode in
                if mode.mode == 2 {
                    // Audio for the article: the recorder with no title or co-host steps; the clip goes into the text at the caret.
                    PodcastRecorder(title: $recordTitle, coauthors: $coauthors, camera: false, forArticle: true) { clip in
                        insertIntoArticle(clip, preview: Self.fileCard(named: "Audio recording \(VoiceFormat.clock(Double(clip.durationMs ?? 0) / 1000))"))
                    }
                } else {
                    PodcastRecorder(title: $recordTitle, coauthors: $coauthors, camera: mode.mode == 0, subtitle: $recordSubtitle, details: $recordDetails, cover: $recordCover, postAsJam: $postAsJam,
                                    // The studio's Post (LIME-227): the take goes in, the studio closes and the post is made.
                                    post: { clip in
                        clips = [clip]; captions = captions.filter { if case .clip = $0.key { false } else { true } }; startCaptions(clip, .clip(0))
                        Task { try? await Task.sleep(for: .milliseconds(450)); post() }
                    }) { clip in clips = [clip]; captions = captions.filter { if case .clip = $0.key { false } else { true } }; startCaptions(clip, .clip(0)) }
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
            .onChange(of: title) { _, _ in coeditChanged(composer) }
            .onChange(of: subtitle) { _, _ in coeditChanged(composer) }
            .onChange(of: store.draftRevision) { _, _ in coeditRemote() }
            .onChange(of: coauthors) { _, now in if let coedit { store.coeditShare(coedit.draftID, with: now.map(\.id)); coedit.reloadAuthors() } }
            .onDisappear { coedit?.stop() }
            .task {
                if let editing {
                    // The post's own words, in its own layout (a recording shows its title, subtitle and description on the article page).
                    article = editing.kind != "quick"; title = editing.title; subtitle = editing.subtitle
                    postAsJam = editing.displayAs == "jam" ? editing.jamId : nil   // the chip starts on the post's current author (LIME-201)
                    coauthors = Array(store.bylinePeople(editing).dropFirst()); pendingHosts = store.pendingCoauthors(editing)
                    if let stored = store.jamAttachments(editing.postId).first(where: JamCover.isCover), let data = await store.jamAttachmentData(editing.postId, stored.attachmentId) { coverImage = UIImage(data: data) }
                    // The post's own files keep their numbers; new pictures are numbered after them (LIME-195b).
                    articleFiles = store.jamAttachments(editing.postId).map { _ in OutgoingAttachment(bytes: Data(), name: "", mime: "image/jpeg", width: nil, height: nil, durationMs: nil, thumb: Data(), poster: Data()) }
                    try? await Task.sleep(for: .milliseconds(300))
                    composer.textView?.attributedText = ComposerDocument.attributed(fromMarkdown: editing.markdown, post: true); composer.didEdit()
                    if article { coedit = store.coeditSession(existingID: nil, forPost: editing, title: title, subtitle: subtitle, markdown: editing.markdown) }
                    wireCoedit()
                    return
                }
                // A shared draft opened from an invitation or a post's ⋯: its words, with everyone's changes so far.
                if let openDraft {
                    article = true
                    try? await Task.sleep(for: .milliseconds(300))
                    if let session = store.coeditSession(existingID: openDraft, forPost: nil, title: "", subtitle: "", markdown: ""), let md = session.exportMarkdown(), let meta = store.coeditMeta(openDraft) {
                        coedit = session
                        title = meta.title; subtitle = meta.subtitle
                        wireCoedit()
                        composer.textView?.attributedText = session.render(markdown: md); composer.didEdit(); session.rebase()
                        store.coeditSeen(openDraft)
                        coauthors = session.otherAuthors()
                    }
                    wireCoedit()
                    return
                }
                // The draft's words go back into the field once it exists.
                try? await Task.sleep(for: .milliseconds(300))
                if !JamDraft.shared.markdown.isEmpty { composer.textView?.attributedText = ComposerDocument.attributed(fromMarkdown: JamDraft.shared.markdown, post: true); composer.didEdit() }
                // A draft that was started before (its words are in the core): it comes back, with everything the other authors wrote meanwhile.
                if article, let id = JamDraft.shared.draftID, let session = store.coeditSession(existingID: id, forPost: nil, title: "", subtitle: "", markdown: ""), let md = session.exportMarkdown(), let meta = store.coeditMeta(id) {
                    coedit = session
                    title = meta.title; subtitle = meta.subtitle
                    wireCoedit()
                    composer.textView?.attributedText = session.render(markdown: md); composer.didEdit(); session.rebase()
                }
                wireCoedit()
                if !article { composer.focus() }
            }
        }
    }

    /// A quick post: your name, the words at the top growing down, photos under them.
    @ViewBuilder private var quickPage: some View {
        if compact {
            // Short of height (landscape): the page scrolls, as an article's does, so the Post-as row stays under the top bar and the field is never
            // squeezed to nothing between the two; the text view grows with its text and the page keeps the caret in view.
            ScrollView {
                VStack(spacing: 0) {
                    quickHead
                    problemText
                    if hasClip { clipsRow }
                    captionsRow
                    ZStack(alignment: .topLeading) {
                        RichComposerField(model: composer, selfSizing: true)
                            .onAppear { composer.hasText = false; composer.isPost = true }
                        if !composer.hasText {
                            Text("What\u{2019}s on your mind?").font(Theme.body).foregroundStyle(Theme.placeholder)
                                .padding(.leading, 4).padding(.top, 8).allowsHitTesting(false).accessibilityHidden(true)
                        }
                    }
                    .padding(.horizontal, 16)
                    if !photos.isEmpty { photosRow }
                    if let link { linkRow(link) }
                }
            }
            .scrollDismissesKeyboard(.interactively)
        } else {
            quickPageTall
        }
    }

    private var quickPageTall: some View {
        VStack(spacing: 0) {
            quickHead
            problemText
            if hasClip { clipsRow }
            captionsRow
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
                captionsRow
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
        .padding(.horizontal, 20).padding(.top, compact ? 0 : 12)
    }

    /// Who the post is from: you, or your jam (LIME-188q).
    private var postAsChip: some View {
        let jam = postAsJam.flatMap { id in store.jamsMine.first { $0.jamId == id } }
        let name = jam?.title ?? store.meProvider().name
        return Button { postingAs = true } label: {
            HStack(spacing: 8) {
                if let jam { BylineAvatar(people: [store.meProvider()] + coauthors, jam: jam.title, size: 34, pending: pendingHosts).frame(width: 44, height: 34, alignment: .leading) } else { AvatarView(person: store.meProvider(), size: 32).accessibilityHidden(true) }
                Text(name).font(Theme.font(.subheadline, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.textSecondary)
            }
            .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Posting as \(name)").accessibilityHint("Choose who this post is from").accessibilityIdentifier("jam-post-as")
        .sheet(isPresented: $postingAs) { PostAsSheet(selection: $postAsJam) }
    }

    /// One line: who the post is from, the people added as small overlapping avatars (tap to change them), and the person-with-plus **last**, so it
    /// always sits to the right of the authors and co-authors.
    private var postLine: some View {
        HStack(spacing: 2) {
            postAsChip
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
            Button { choosingCoauthors = true } label: {
                Image(systemName: "person.badge.plus").font(.system(size: 18)).foregroundStyle(Theme.textSecondary).frame(width: 44, height: 44)
            }
            .buttonStyle(.plain).accessibilityLabel("Add co-author").accessibilityIdentifier("jam-add-coauthor")
            Spacer(minLength: 0)
        }
    }

    /// Title (large, up to 120), then a short subtitle (up to 160): Return in either moves on, neither ever holds the article.
    private var articleHead: some View {
        VStack(alignment: .leading, spacing: 4) {
            postLine.padding(.bottom, 6)
            if let coedit { CoEditBar(session: coedit) }
            coverRow.padding(.bottom, 8)
            CaretTextField(text: $title, title: "Title", prompt: Text("Title").foregroundColor(Theme.placeholderLarge)) { caret, end in titleCaret = (caret, end); coedit?.fieldMoved() }
                .font(Theme.font(.title2, weight: .bold)).lineLimit(1...3)
                .focused($focus, equals: .title).submitLabel(.next).onSubmit { focus = .subtitle }
                .onChange(of: title) { _, now in
                    if now.contains("\n") { title = now.replacingOccurrences(of: "\n", with: ""); focus = .subtitle }
                    else if now.count > Self.maxTitle { title = String(now.prefix(Self.maxTitle)) }
                }
                .accessibilityLabel("Title").accessibilityIdentifier("jam-article-title")
                .overlay(alignment: .topLeading) { if let coedit { PeerFieldCursors(peers: coedit.peers, field: "title", text: title, font: TextPreferences.shared.uiFont(.title2, weight: .bold, textStyle: .title2)) } }
            CaretTextField(text: $subtitle, title: "Add a subtitle\u{2026}", prompt: Text("Add a subtitle\u{2026}").foregroundColor(Theme.placeholder)) { caret, end in subtitleCaret = (caret, end); coedit?.fieldMoved() }
                .font(Theme.font(.body)).foregroundStyle(Theme.textSecondary).lineLimit(1...2)
                .focused($focus, equals: .subtitle).submitLabel(.next).onSubmit { toBody() }
                .onChange(of: subtitle) { _, now in
                    if now.contains("\n") { subtitle = now.replacingOccurrences(of: "\n", with: ""); toBody() }
                    else if now.count > Self.maxSubtitle { subtitle = String(now.prefix(Self.maxSubtitle)) }
                }
                .accessibilityLabel("Subtitle").accessibilityIdentifier("jam-article-subtitle")
                .overlay(alignment: .topLeading) { if let coedit { PeerFieldCursors(peers: coedit.peers, field: "subtitle", text: subtitle, font: TextPreferences.shared.uiFont(.body, weight: .regular, textStyle: .body)) } }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20).padding(.top, 12)
    }

    // MARK: The cover

    private var hasStoredCover: Bool { editing.map { store.jamAttachments($0.postId).contains(where: JamCover.isCover) } ?? false }

    /// The cover thumbnail with Add / Change / Remove, under the Post as line (LIME-219). Without one the card uses the first photo or video.
    private var coverRow: some View {
        HStack(spacing: 12) {
            if let coverImage {
                Button { viewingCover = true } label: {
                    Image(uiImage: coverImage).resizable().scaledToFill().frame(width: 72, height: 72).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain).accessibilityLabel("Cover").accessibilityHint("Opens full size").accessibilityIdentifier("jam-article-cover")
            }
            Menu {
                Button { addCoverFromLibrary() } label: { Label("Choose a photo", systemImage: "photo.on.rectangle") }.accessibilityIdentifier("jam-cover-library")
                Button { choosingArticlePhoto = true } label: { Label("Use a photo from this article", systemImage: "doc.richtext") }.accessibilityIdentifier("jam-cover-from-article")
            } label: {
                Text(coverImage == nil ? "Add cover" : "Edit cover").font(Theme.secondary).foregroundStyle(Theme.text).lineLimit(1).fixedSize().padding(.horizontal, 14).frame(minHeight: 44).background(Theme.surface, in: Capsule())
            }
            .accessibilityLabel(coverImage == nil ? "Add cover" : "Edit cover").accessibilityIdentifier("jam-cover-change")
            if coverImage != nil {
                Button(role: .destructive) { articleCover = nil; coverImage = nil; coverRemoved = hasStoredCover } label: { Text("Remove").font(Theme.secondary).padding(.horizontal, 10).frame(minHeight: 44) }
                    .accessibilityIdentifier("jam-cover-remove")
            }
            Spacer(minLength: 0)
        }
    }

    private func setCover(_ image: UIImage) {
        guard let made = AttachmentProcessing.photo(image, name: JamCover.name) else { return }
        articleCover = made; coverImage = image; coverRemoved = false
    }

    private func addCoverFromLibrary() {
        #if DEBUG
        if store.isDemo, let data = store.demoJamImage("p"), let image = UIImage(data: data) { setCover(image); return }
        #endif
        pickingCover = true
    }

    /// The article's own photos and the posters of its videos, as pictures to choose a cover from.
    private func articlePhotos() async -> [UIImage] {
        var found: [UIImage] = []
        let stored = editing.map { store.jamAttachments($0.postId) } ?? []
        for (index, file) in articleFiles.enumerated() {
            if !file.bytes.isEmpty {
                if file.mime.hasPrefix("image/"), let image = UIImage(data: file.bytes) { found.append(image) }
                else if file.mime.hasPrefix("video/"), let image = UIImage(data: file.poster) { found.append(image) }
            } else if stored.indices.contains(index), !JamCover.isCover(stored[index]) {
                if stored[index].kind == "image", let data = await store.jamAttachmentData(editing?.postId ?? "", stored[index].attachmentId), let image = UIImage(data: data) { found.append(image) }
                else if stored[index].kind == "video", let image = UIImage(data: stored[index].poster) { found.append(image) }
            }
        }
        return found
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

    // MARK: Captions (LIME-188o)

    /// Starts making captions for a video or a recording on this phone (nothing leaves it).
    private func startCaptions(_ item: OutgoingAttachment, _ key: CaptionKey) {
        guard item.mime.hasPrefix("video/") || item.mime.hasPrefix("audio/") else { return }
        if let ms = item.durationMs, Int(ms) / 1000 > CaptionMaker.maxSeconds { captions[key] = CaptionDraft(making: false, none: true); return }
        captions[key] = CaptionDraft()
        let ext = item.mime.hasPrefix("video/") ? "mp4" : "m4a"
        #if DEBUG
        let demo = store.isDemo
        #else
        let demo = false
        #endif
        Task {
            let cues = await CaptionMaker.make(bytes: item.bytes, fileExtension: ext, demo: demo)
            captions[key] = cues.map { CaptionDraft(cues: $0, making: false) } ?? CaptionDraft(making: false, none: true)
        }
    }

    @ViewBuilder
    private var captionsRow: some View {
        if !captions.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(captions.keys.sorted { $0.id < $1.id }) { key in
                    let draft = captions[key] ?? CaptionDraft(making: false)
                    HStack(spacing: 10) {
                        Image(systemName: "captions.bubble").foregroundStyle(Theme.textSecondary).accessibilityHidden(true)
                        Text(draft.making ? "Making captions\u{2026}" : draft.none ? "No captions for this one" : draft.on ? "Captions \u{00B7} \(draft.cues.count) lines" : "Captions off")
                            .font(Theme.secondary).foregroundStyle(Theme.textSecondary).accessibilityIdentifier("jam-captions-status")
                        Spacer()
                        if !draft.making, !draft.none {
                            Button("Edit") { editingCaptions = key }.font(Theme.secondary).foregroundStyle(Theme.text).frame(minWidth: 44, minHeight: 44).accessibilityIdentifier("jam-captions-edit")
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
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
                Button { clips.remove(at: index); captions[.clip(index)] = nil } label: {
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
            if !article && editing == nil && !compact {
                // Two cards side by side, lined up with the photo icon below; they scroll sideways when they do not fit, and the last one ends with room to spare.
                let itemWidth = min(44, (UIScreen.main.bounds.width - 32) / 7)
                ScrollView(.horizontal, showsIndicators: false) { pillRow.padding(.leading, 16 + (itemWidth - 25) / 2).padding(.trailing, 20) }
                    .scrollBounceBehavior(.basedOnSize)
                    .padding(.bottom, 6)
            }
            // The full strip (Aa) sits under the pills in a quick post, above the tool row in an article; never over the text.
            if composer.showsStrip { FormattingToolbar(model: composer).transition(.opacity) }
            // + (or photo, camera) · Aa · H · Undo · Redo on the left, the keyboard on the right; the side margins are Cancel's and Post's (16 pt), so
            // the first glyph lines up under Cancel's edge and the keyboard under Post's (LIME-197).
            let items: CGFloat = article ? 6 : 7
            let width = min(44, (UIScreen.main.bounds.width - 32) / items)
            let inline = compact && !article && editing == nil
            HStack(spacing: 0) {
                if inline {
                    // The pills live here, at the leading end after photo and camera; the row scrolls sideways when it is short of room, the keyboard key stays put.
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 0) {
                            leadingTools(width: width)
                            compactPill("Write article", spoken: "Write an article", system: "square.and.pencil", id: "jam-write-article") { setArticle(true) }.padding(.leading, 4)
                            compactPill("Record podcast", spoken: "Record a podcast", system: "waveform", id: "jam-record") { recordMode = 0 }.padding(.horizontal, 8)
                            trailingTools(width: width)
                        }
                    }
                } else {
                    leadingTools(width: width)
                    trailingTools(width: width)
                    Spacer(minLength: 0)
                }
                tool(composer.editing ? "keyboard.chevron.compact.down" : "keyboard", composer.editing ? "Hide keyboard" : "Show keyboard", id: "jam-hide-keyboard", width: width) { composer.toggleKeyboard() }
                    .padding(.trailing, -(width - 28) / 2)
            }
            .padding(.horizontal, 16).frame(minHeight: 48)
            .background(.bar)
        }
    }

    @ViewBuilder private func leadingTools(width: CGFloat) -> some View {
        if article {
            plusMenu(width: width).padding(.leading, (width - 32) / 2 * -1)
        } else {
            tool("photo.on.rectangle", "Add photos", id: "jam-add-photo", width: width) { choose(.library) }
            tool("camera", "Camera", id: "jam-add-camera", width: width) { choose(.camera) }
        }
    }

    @ViewBuilder private func trailingTools(width: CGFloat) -> some View {
        formattingButton(width: width)
        headingButton(width: width)
        tool("arrow.uturn.backward", "Undo", id: "jam-undo", width: width) { composer.undo() }
            .disabled(!composer.format.canUndo).opacity(composer.format.canUndo ? 1 : 0.35)
        tool("arrow.uturn.forward", "Redo", id: "jam-redo", width: width) { composer.redo() }
            .disabled(!composer.format.canRedo).opacity(composer.format.canRedo ? 1 : 0.35)
    }

    /// The compact layout's one-line warm-grey pill.
    private func compactPill(_ label: String, spoken: String, system: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: system).font(Theme.font(.footnote, weight: .medium)).foregroundStyle(Theme.text).lineLimit(1).fixedSize()
                .padding(.horizontal, 12).frame(minHeight: 36).background(Theme.surface, in: Capsule()).frame(minHeight: 44).contentShape(Capsule())
        }
        .buttonStyle(.plain).accessibilityLabel(spoken).accessibilityIdentifier(id)
    }

    /// Aa opens the strip of text styles (B I U S link code lists quote indent): it also appears under a selection.
    private func formattingButton(width: CGFloat) -> some View {
        Button { composer.formattingTapped() } label: {
            Text("Aa").font(.system(size: 17, weight: composer.toolbarVisible ? .bold : .medium)).foregroundStyle(Theme.text).frame(width: width, height: 44)
                .background(composer.toolbarVisible ? Theme.surface : .clear, in: Circle())
        }
        .accessibilityLabel("Formatting").accessibilityIdentifier("jam-format").accessibilityAddTraits(composer.toolbarVisible ? [.isSelected] : [])
    }

    /// H opens a small popover: Normal text and Heading 1 to 6. Every row has the same narrow column on the left for a small check on the current
    /// one (empty space on the others), then the label, so nothing shifts when the check moves. Its icon says which one the caret is in.
    private func headingButton(width: CGFloat) -> some View {
        let level = composer.format.heading
        return Button { headingOpen = true } label: {
            Text(level == 0 ? "H" : "H\(level)").font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.text).frame(width: width, height: 44)
                .background(level == 0 ? .clear : Theme.surface, in: Circle())
        }
        .accessibilityLabel(level == 0 ? "Heading, currently normal text" : "Heading, currently Heading \(level)").accessibilityIdentifier("jam-heading")
        .popover(isPresented: $headingOpen, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(0...6, id: \.self) { n in
                    Button { composer.setHeading(n == 0 ? nil : n); headingOpen = false } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark").font(.system(size: 12, weight: .semibold)).frame(width: 16).opacity(level == n ? 1 : 0).accessibilityHidden(true)
                            Text(n == 0 ? "Normal text" : "Heading \(n)").font(n == 0 ? Theme.body : .system(size: CGFloat(20 - n), weight: .bold))
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(Theme.text).padding(.horizontal, 14).frame(minHeight: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(n == 0 ? "Normal text" : "Heading \(n)").accessibilityAddTraits(level == n ? [.isSelected] : [])
                    .accessibilityIdentifier("jam-heading-\(n)")
                }
            }
            .frame(width: 210).padding(.vertical, 6)
            .presentationCompactAdaptation(.popover)
        }
    }

    /// The article's ⊕: a menu above the bar, top to bottom as you see it: **Freewall · Divider · Button · Audio › · Photo › · Video ›**
    /// (`menuOrder(.fixed)`: a menu that opens upward would otherwise reverse them). Each goes in at the caret. (Files other than audio are not
    /// offered in v1.)
    private func plusMenu(width: CGFloat) -> some View {
        Menu {
            Button { composer.insertRule("freewall") } label: { Label("Freewall", systemImage: "lock.open") }
                .disabled(composer.textView.map { ComposerDocument.hasFreewall(in: $0.textStorage) } ?? false)
                .accessibilityIdentifier("jam-menu-freewall")
            Button { composer.insertRule("divider") } label: { Label("Divider", systemImage: "minus") }.accessibilityIdentifier("jam-menu-divider")
            Button { composer.buttonRequest = ButtonRequest() } label: { Label("Button", systemImage: "rectangle.and.hand.point.up.left") }.accessibilityIdentifier("jam-menu-button")
            Menu {
                Button { recordMode = 2 } label: { Label("Record", systemImage: "waveform") }.accessibilityIdentifier("jam-menu-audio-record")
                Button { choose(.files) } label: { Label("Choose a file", systemImage: "doc") }.accessibilityIdentifier("jam-menu-audio-file")
            } label: { Label("Audio", systemImage: "waveform.circle") }
                .accessibilityIdentifier("jam-menu-audio")
            Menu {
                Button { choose(.library) } label: { Label("Library", systemImage: "photo.on.rectangle") }.accessibilityIdentifier("jam-menu-photo-library")
                Button { choose(.camera) } label: { Label("Take photo", systemImage: "camera") }.accessibilityIdentifier("jam-menu-photo-camera")
            } label: { Label("Photo", systemImage: "photo") }
                .accessibilityIdentifier("jam-menu-photo")
            Menu {
                Button { choose(.library) } label: { Label("Library", systemImage: "photo.on.rectangle") }.accessibilityIdentifier("jam-menu-video-library")
                Button { choose(.camera) } label: { Label("Record video", systemImage: "video") }.accessibilityIdentifier("jam-menu-video-camera")
            } label: { Label("Video", systemImage: "video") }
                .accessibilityIdentifier("jam-menu-video")
        } label: {
            Image(systemName: "plus").font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.canvas).frame(width: 32, height: 32).background(Theme.text, in: Circle()).frame(width: width, height: 44)
        }
        .menuOrder(.fixed)
        .accessibilityLabel("Add").accessibilityIdentifier("jam-add")
    }

    private func tool(_ symbol: String, _ label: String, id: String, on: Bool = false, width: CGFloat = 44, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 19)).foregroundStyle(Theme.text).frame(width: width, height: 44)
                .background(on ? Theme.surface : .clear, in: Circle())
        }
        .accessibilityLabel(label).accessibilityIdentifier(id).accessibilityAddTraits(on ? [.isSelected] : [])
    }

    private var pillRow: some View {
        HStack(spacing: 10) {
            chip("Write article", spoken: "Write an article", system: "square.and.pencil", id: "jam-write-article") { setArticle(true) }
            chip("Record podcast", spoken: "Record a podcast", system: "waveform", id: "jam-record") { recordMode = 0 }
        }
    }

    /// A card above the keyboard bar (LIME-236c): a warm grey rounded rectangle, the icon on top at the left, the label on its own line below.
    private func chip(_ label: String, spoken: String, system: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: system).font(.system(size: 20, weight: .regular)).accessibilityHidden(true)
                Text(label).font(Theme.font(.subheadline, weight: .medium)).lineLimit(1).fixedSize()
            }
            .foregroundStyle(Theme.text).padding(.horizontal, 14).padding(.vertical, 12).frame(minWidth: 120, minHeight: 44, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous)).contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain).accessibilityLabel(spoken).accessibilityIdentifier(id)
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
                if article { insertIntoArticle(clip.outgoing, preview: clip.preview ?? Self.fileCard(named: "Video")) } else { clips.append(clip.outgoing); startCaptions(clip.outgoing, .clip(clips.count - 1)) }
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
                startCaptions(made.item, .clip(clips.count - 1))
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
        startCaptions(item, .article(articleFiles.count - 1))
        let width = max(120, view.bounds.width - 16)
        let small = preview.preparingThumbnail(of: CGSize(width: 900, height: 900)) ?? preview
        coedit?.notePicture(local: articleFiles.count - 1, image: small)
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

    // MARK: The shared draft (LIME-233c)

    #if DEBUG
    /// Tests only (demo runs): what the draft holds. With `-lime-coedit-sim-remote`, six seconds after the first words "another author" types at the
    /// start of the draft once.
    @ViewBuilder private var coeditProbe: some View {
        if store.isDemo, FeatureFlags.coedit, let coedit {
            TimelineView(.periodic(from: .now, by: 0.3)) { _ in
                Color.clear.frame(width: 2, height: 2).accessibilityElement().accessibilityLabel(store.coeditMarkdown(coedit.draftID) ?? "").accessibilityIdentifier("coedit-probe")
            }
        }
    }

    private func simulateRemoteOnce(_ id: String) {
        if ProcessInfo.processInfo.arguments.contains("-lime-coedit-sim-peer"), !Self.peerSimulated, let coedit {
            Self.peerSimulated = true
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                for step in 0..<12 { coedit.simulatePeer(step: step); try? await Task.sleep(for: .seconds(2)) }   // she stays in the draft, moving her cursor
            }
        }
        guard ProcessInfo.processInfo.arguments.contains("-lime-coedit-sim-remote"), !Self.simulated else { return }
        Self.simulated = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(6))
            let mid = ProcessInfo.processInfo.arguments.contains("-lime-coedit-sim-remote-mid")
            store.coeditSimulateRemote(id) { mid && $0.count > 3 ? String($0.prefix(3)) + "-X-" + String($0.dropFirst(3)) : "REMOTE " + $0 }
        }
    }

    @MainActor private static var simulated = false
    @MainActor private static var peerSimulated = false
    #endif

    /// The editor's changes go to the draft. The draft is made on the first change of an article (an empty page makes none).
    private func wireCoedit() {
        guard FeatureFlags.coedit else { return }
        composer.onChange = { [weak composer] in
            guard let composer else { return }
            Task { @MainActor in coeditChanged(composer) }
        }
        composer.onSelect = { [weak composer] in
            guard let composer else { return }
            Task { @MainActor in coedit?.sendPresence(composer) }
        }
        if let coedit {
            coedit.files = CoEditFiles(
                file: { articleFiles.indices.contains($0) ? articleFiles[$0] : nil },
                add: { articleFiles.append($0); return articleFiles.count - 1 },
                fill: { if articleFiles.indices.contains($0) { articleFiles[$0] = $1 } },
                width: { max(120, (composer.textView?.bounds.width ?? 320) - 16) },
                title: { title }, subtitle: { subtitle }, setTitle: { title = $0 }, setSubtitle: { subtitle = $0 },
                focusedField: {
                    switch focus {
                    case .title: return ("title", titleCaret.caret, titleCaret.end)
                    case .subtitle: return ("subtitle", subtitleCaret.caret, subtitleCaret.end)
                    default: return nil
                    }
                })
            coedit.start(composer: composer)
        }
    }

    private func coeditChanged(_ composer: RichComposerModel) {
        guard FeatureFlags.coedit, article, let view = composer.textView else { return }
        let markdown = { ComposerDocument.markdown(from: view.textStorage, post: true) }
        if coedit == nil {
            guard !markdown().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !title.isEmpty else { return }
            coedit = store.coeditSession(existingID: nil, forPost: nil, title: title, subtitle: subtitle, markdown: markdown())
            JamDraft.shared.draftID = coedit?.draftID
            wireCoedit()
            if let coedit { if !coauthors.isEmpty { store.coeditShare(coedit.draftID, with: coauthors.map(\.id)) } }
        }
        coedit?.editorChanged(title: title, subtitle: subtitle, composer: composer)
        #if DEBUG
        if store.isDemo, let id = coedit?.draftID, !markdown().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { simulateRemoteOnce(id) }
        #endif
    }

    /// Other authors' words arrived.
    private func coeditRemote() {
        coedit?.applyRemote()
    }

    // MARK: Closing and posting

    private func close() {
        coedit?.stop()
        if editing != nil || openDraft != nil { if let coedit, let view = composer.textView { coedit.syncNow(title: title, subtitle: subtitle, markdown: coedit.draftMarkdown(from: view.textStorage)) }; dismiss(); return }
        let draft = JamDraft.shared
        let text = hasWords && !hasPictures ? composer.markdown() : ""
        draft.article = article; draft.title = title; draft.subtitle = subtitle; draft.markdown = text
        if let coedit, let view = composer.textView { coedit.syncNow(title: title, subtitle: subtitle, markdown: coedit.draftMarkdown(from: view.textStorage)); draft.draftID = coedit.draftID }
        dismiss()
    }

    /// Update: the words go to the post in place (its pictures keep the numbers the text already has).
    private func update() {
        guard let editing, !posting else { return }
        let existing = store.jamAttachments(editing.postId).count
        // An article keeps its pictures' numbers as they stand (the core closes up the gaps); the new files are the ones after the old.
        let markdown = article ? (composer.textView.map { ComposerDocument.markdown(from: $0.textStorage, post: true) } ?? composer.markdown()) : composer.markdown()
        let added = article && articleFiles.count > existing ? Array(articleFiles[existing...]) : []
        problem = nil
        posting = true
        Task {
            let result = await store.editJamPost(editing, title: title, subtitle: subtitle, markdown: markdown, added: added + (article ? articleCover.map { [$0] } ?? [] : []),
                                                 displayAs: postAsJam == nil ? "person" : "jam", removeCover: article && coverRemoved && articleCover == nil)
            posting = false
            if result { coedit?.published(postID: editing.postId); dismiss() } else { problem = "Could not update the post." }
        }
    }

    private func post() {
        guard captions.values.contains(where: \.making) else { buildAndPost(); return }
        // Captions are still being made: wait a few seconds for them, then post with what there is.
        posting = true
        Task {
            for _ in 0..<20 where captions.values.contains(where: \.making) { try? await Task.sleep(for: .milliseconds(500)) }
            posting = false
            buildAndPost()
        }
    }

    private func buildAndPost() {
        var files: [OutgoingAttachment] = []
        var captionTargets: [(index: Int, draft: CaptionDraft)] = []
        var markdown = ""
        if article, let view = composer.textView {
            // Only the files still in the text go, numbered in the order they appear.
            let copy = NSMutableAttributedString(attributedString: view.textStorage)
            var renumber: [Int: Int] = [:]
            copy.enumerateAttribute(.limeImage, in: NSRange(location: 0, length: copy.length)) { value, range, _ in
                guard let old = value as? Int, articleFiles.indices.contains(old) else { return }
                if renumber[old] == nil {
                    renumber[old] = files.count
                    if let draft = captions[.article(old)] { captionTargets.append((files.count, draft)) }
                    files.append(articleFiles[old])
                }
                copy.addAttribute(.limeImage, value: renumber[old] ?? 0, range: range)
            }
            markdown = ComposerDocument.markdown(from: copy, post: true)
        } else {
            markdown = composer.markdown()
            files = photos.map(\.outgoing)
        }
        for (i, _) in clips.enumerated() { if let draft = captions[.clip(i)] { captionTargets.append((files.count + i, draft)) } }
        files += clips
        if let link { files.append(JamLink.attachment(link.preview)) }
        // The captions the writer kept go with the post, one small file per video or recording.
        for target in captionTargets where target.draft.on && !target.draft.making && !target.draft.cues.isEmpty && files.count < 10 {
            let vtt = Data(captionsToVtt(cues: target.draft.cues).utf8)
            files.append(OutgoingAttachment(bytes: vtt, name: captionFileName(index: UInt32(target.index)), mime: "text/vtt", width: nil, height: nil, durationMs: nil, thumb: Data(), poster: Data()))
        }
        if hasClip, let recordCover, files.count < 10 { files.append(recordCover) }
        if article, !hasClip, let articleCover, files.count < 10 { files.append(articleCover) }
        let kind = hasClip ? "record" : article ? "article" : "quick"
        let headline = article ? title : recordTitle
        // A recording's description is its words when no words were written.
        if hasClip, markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { markdown = recordDetails.trimmingCharacters(in: .whitespacesAndNewlines) }
        problem = nil
        posting = true
        Task {
            let result = await store.publishJamPost(kind: kind, title: headline, subtitle: article ? subtitle : hasClip ? recordSubtitle : "", markdown: markdown, items: files, coauthors: coauthors.map(\.id), displayAs: postAsJam == nil ? "person" : "jam", about: session.profile?.aboutText ?? "")
            posting = false
            switch result {
            case .success:
                if let coedit { coedit.published(postID: store.lastPublishedPostID); store.coeditFinish(coedit.draftID) }
                JamDraft.shared.clear(); dismiss()
            case .failure(let failure): problem = failure.message   // the words, the photos and the title all stay
            }
        }
    }
}

/// Who the post is from (LIME-188q): you, or a jam you write (its name is the author line, with "by you" under it). A school or subject group
/// comes with LIME-193.
struct PostAsSheet: View {
    @Binding var selection: String?
    @Environment(ConversationStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Button { selection = nil; dismiss() } label: {
                    HStack(spacing: 12) {
                        AvatarView(person: store.meProvider(), size: 40).accessibilityHidden(true)
                        Text(store.meProvider().name).font(Theme.body).foregroundStyle(Theme.text)
                        Spacer()
                        if selection == nil { Image(systemName: "checkmark").foregroundStyle(Theme.text) }
                    }
                    .frame(minHeight: 48)
                }
                .accessibilityLabel("\(store.meProvider().name)\(selection == nil ? ", selected" : "")").accessibilityIdentifier("jam-post-as-me")
                ForEach(store.jamsMine, id: \.jamId) { jam in
                    Button { selection = jam.jamId; dismiss() } label: {
                        HStack(spacing: 12) {
                            // Its tile with its writers' circles at the bottom right, you included (LIME-215b).
                            BylineAvatar(people: store.jamAuthors(jam.jamId), jam: jam.title, size: 44).frame(width: 52, height: 44, alignment: .leading)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(jam.title).font(Theme.font(.callout, weight: .medium)).foregroundStyle(Theme.text).lineLimit(1).minimumScaleFactor(0.85)
                                Text((["You"] + store.jamAuthors(jam.jamId).dropFirst().map(\.name)).joined(separator: " \u{00B7} ")).font(Theme.caption).foregroundStyle(Theme.textSecondary).lineLimit(1)
                            }
                            Spacer()
                            if selection == jam.jamId { Image(systemName: "checkmark").foregroundStyle(Theme.text) }
                        }
                        .frame(minHeight: 48)
                    }
                    .accessibilityLabel("\(jam.title), with you\(store.jamAuthors(jam.jamId).count > 1 ? " and " + store.jamAuthors(jam.jamId).dropFirst().map(\.name).joined(separator: ", ") : "")\(selection == jam.jamId ? ", selected" : "")").accessibilityIdentifier("jam-post-as-jam-\(jam.jamId)")
                }
                Text("Posting as a school or a subject group comes later.").font(Theme.caption).foregroundStyle(Theme.textSecondary)
            }
            .navigationTitle("Post as").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium])
    }
}

/// A jam has no picture yet: its first letter on a soft tint.
struct JamInitialTile: View {
    let title: String
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous).fill(Theme.accent.opacity(0.35))
            Text(String(title.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()).font(.system(size: size * 0.45, weight: .bold)).foregroundStyle(Theme.text)
        }
        .frame(width: size, height: size)
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


/// "Use a photo from this article": the article's own photos and video posters to pick a cover from (LIME-219).
struct ArticlePhotoPicker: View {
    let load: () async -> [UIImage]
    let pick: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var photos: [UIImage]?

    var body: some View {
        NavigationStack {
            ScrollView {
                if let photos {
                    if photos.isEmpty {
                        Text("This article has no photos yet.").font(Theme.body).foregroundStyle(Theme.textSecondary).padding(40).accessibilityIdentifier("jam-cover-none")
                    } else {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                            ForEach(Array(photos.enumerated()), id: \.offset) { index, image in
                                Button { pick(image) } label: {
                                    Color.clear.aspectRatio(1, contentMode: .fit).overlay { Image(uiImage: image).resizable().scaledToFill() }.clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                                .buttonStyle(.plain).accessibilityLabel("Photo \(index + 1)").accessibilityIdentifier("jam-cover-photo-\(index)")
                            }
                        }
                        .padding(16)
                    }
                } else {
                    ProgressView().padding(40)
                }
            }
            .background(Theme.canvas)
            .navigationTitle("Choose a cover").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .task { photos = await load() }
        }
        .presentationDetents([.medium, .large])
    }
}
