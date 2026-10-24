import SwiftUI

/// Edit decides which editor a post gets (LIME-212): a recording opens a **podcast page**, everything else the writing screen.
struct JamEditSheet: View {
    let post: JamPostInfo
    var body: some View {
        if post.kind == "record" { JamPodcastEditSheet(post: post) } else { JamComposeSheet(editing: post) }
    }
}

/// Editing a podcast (LIME-212; laid out like the article editor, LIME-220): who it is from, the small cover (tap for full size), the recording
/// (playable here), title, subtitle and the description as the article editor's body, with its bar. The recording itself is not replaced here. Update saves it as today's edit does and, with a new cover, replaces `cover.jpg`.
struct JamPodcastEditSheet: View {
    let post: JamPostInfo
    @Environment(ConversationStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var subtitle: String
    @State private var newCover: OutgoingAttachment?
    @State private var removeCover = false
    @State private var postAsJam: String?
    @State private var postingAs = false
    @State private var coauthors: [Person] = []
    @State private var pendingHosts: [Person] = []
    @State private var choosingCoauthors = false
    @State private var picking = false
    @State private var saving = false
    @State private var problem: String?
    // The description is the article editor's body (LIME-220): same field, same bar.
    @State private var composer = RichComposerModel()
    @State private var newFiles: [OutgoingAttachment] = []
    @State private var existingCount = 0
    @State private var headingOpen = false
    @State private var viewingCover = false
    @FocusState private var focus: Field?
    private enum Field { case title, subtitle }

    init(post: JamPostInfo) {
        self.post = post
        _title = State(initialValue: post.title)
        _subtitle = State(initialValue: post.subtitle)
        _postAsJam = State(initialValue: post.displayAs == "jam" ? post.jamId : nil)
        _initialHosts = State(initialValue: post.coauthors)
    }

    /// The accepted co-hosts the post had; the list is only sent when it changed.
    @State private var initialHosts: [String]

    private var files: [JamAttachmentInfo] { store.jamAttachments(post.postId) }
    private var recording: JamAttachmentInfo? { files.first { $0.kind == "audio" } ?? files.first { $0.kind == "video" } }
    private var hasOwnCover: Bool { files.contains(where: JamCover.isCover) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 4) {
                        postAsChip
                        hosts
                        Spacer(minLength: 0)
                    }
                    .padding(.bottom, 6)
                    cover.padding(.bottom, 10)
                    recordingRow.padding(.bottom, 14)
                    TextField("Title", text: $title, prompt: Text("Title").foregroundColor(Theme.placeholderLarge), axis: .vertical)
                        .font(Theme.font(.title2, weight: .bold)).lineLimit(1...3)
                        .focused($focus, equals: .title).submitLabel(.next).onSubmit { focus = .subtitle }
                        .onChange(of: title) { _, now in
                            if now.contains("\n") { title = now.replacingOccurrences(of: "\n", with: ""); focus = .subtitle }
                            else if now.count > 120 { title = String(now.prefix(120)) }
                        }
                        .accessibilityLabel("Title").accessibilityIdentifier("podcast-edit-title")
                    TextField("Add a subtitle\u{2026}", text: $subtitle, prompt: Text("Add a subtitle\u{2026}").foregroundColor(Theme.placeholder), axis: .vertical)
                        .font(Theme.font(.body)).foregroundStyle(Theme.textSecondary).lineLimit(1...2)
                        .focused($focus, equals: .subtitle).submitLabel(.next).onSubmit { focus = nil; DispatchQueue.main.async { composer.focus() } }
                        .onChange(of: subtitle) { _, now in
                            if now.contains("\n") { subtitle = now.replacingOccurrences(of: "\n", with: ""); focus = nil; DispatchQueue.main.async { composer.focus() } }
                            else if now.count > 160 { subtitle = String(now.prefix(160)) }
                        }
                        .accessibilityLabel("Subtitle").accessibilityIdentifier("podcast-edit-subtitle")
                        .padding(.top, 4)
                    if let problem { Text(problem).font(Theme.secondary).foregroundStyle(.red).padding(.top, 6) }
                    ZStack(alignment: .topLeading) {
                        RichComposerField(model: composer, selfSizing: true)
                            .onAppear { composer.hasText = false; composer.isPost = true }
                            .accessibilityLabel("Description").accessibilityIdentifier("podcast-edit-description")
                        if !composer.hasText {
                            Text("Description\u{2026}").font(Theme.body).foregroundStyle(Theme.placeholder)
                                .padding(.leading, 4).padding(.top, 8).allowsHitTesting(false).accessibilityHidden(true)
                        }
                    }
                    .padding(.top, 16).padding(.horizontal, -4)
                }
                .padding(.horizontal, 20).padding(.top, 12)
            }
            .background(Theme.canvas)
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
            .navigationTitle("Edit").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.accessibilityIdentifier("podcast-edit-cancel") }
                ToolbarItem(placement: .confirmationAction) { Button("Update") { update() }.fontWeight(.semibold).disabled(saving || title.trimmingCharacters(in: .whitespaces).isEmpty).accessibilityIdentifier("podcast-edit-update") }
            }
            .sheet(isPresented: $postingAs) { PostAsSheet(selection: $postAsJam) }
            .sheet(isPresented: $choosingCoauthors) { JamCoauthorPicker(selected: $coauthors, title: "Add co-hosts") }
            .sheet(item: $composer.linkRequest) { request in LinkSheet(request: request, composer: composer) }
            .onAppear { if coauthors.isEmpty { coauthors = initialHosts.map { store.teacher($0) } }; pendingHosts = store.pendingCoauthors(post) }
            .task {
                // The post's own words go in as they are, except the picture block of the cover itself, which the page already shows (LIME-220).
                existingCount = files.count
                var text = post.markdown
                if let at = files.firstIndex(where: JamCover.isCover) {
                    text = text.replacingOccurrences(of: "![](attachment:\(at))", with: "")
                    text = text.replacingOccurrences(of: "\n\n\n", with: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
                }
                try? await Task.sleep(for: .milliseconds(300))
                composer.textView?.attributedText = ComposerDocument.attributed(fromMarkdown: text, post: true); composer.didEdit()
            }
            .fullScreenCover(isPresented: $picking) {
                MediaLibraryPicker(limit: 1, onPick: { images, _ in
                    picking = false
                    if let image = images.first, let made = AttachmentProcessing.photo(image, name: JamCover.name) { newCover = made; removeCover = false }
                }, onCancel: { picking = false }).ignoresSafeArea()
            }
            .fullScreenCover(isPresented: $pickingPicture) {
                MediaLibraryPicker(limit: 1, onPick: { images, _ in
                    pickingPicture = false
                    if let image = images.first { addPicture(image) }
                }, onCancel: { pickingPicture = false }).ignoresSafeArea()
            }
            .fullScreenCover(isPresented: $viewingCover) { coverViewer }
        }
    }

    @State private var pickingPicture = false

    /// The cover full size: a tap anywhere closes it.
    private var coverViewer: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            Group {
                if let newCover, let image = UIImage(data: newCover.bytes) { Image(uiImage: image).resizable().scaledToFit() }
                else if removeCover { CoverArt(image: nil, person: store.teacher(post.author), org: store.orgName(post)).aspectRatio(1, contentMode: .fit) }
                else { PostCover(postID: post.postId).aspectRatio(1, contentMode: .fit) }
            }
            .frame(maxWidth: .infinity).accessibilityLabel("Cover, full size")
            Button { viewingCover = false } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 30)).foregroundStyle(.white).frame(width: 44, height: 44) }
                .padding().accessibilityLabel("Close").accessibilityIdentifier("podcast-edit-cover-close")
        }
        .onTapGesture { viewingCover = false }
        .accessibilityIdentifier("podcast-edit-cover-viewer")
    }

    // MARK: The bar: + Aa H undo redo, as in the article editor

    private var bottomBar: some View {
        VStack(spacing: 0) {
            if composer.showsStrip { FormattingToolbar(model: composer).transition(.opacity) }
            let width = min(44, (UIScreen.main.bounds.width - 32) / 6)
            HStack(spacing: 0) {
                Menu {
                    Button { composer.insertRule("divider") } label: { Label("Divider", systemImage: "minus") }.accessibilityIdentifier("jam-menu-divider")
                    Button { addPictureFromLibrary() } label: { Label("Photo", systemImage: "photo") }.accessibilityIdentifier("jam-menu-photo")
                } label: {
                    Image(systemName: "plus").font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.canvas).frame(width: 32, height: 32).background(Theme.text, in: Circle()).frame(width: width, height: 44)
                }
                .menuOrder(.fixed).padding(.leading, (width - 32) / 2 * -1)
                .accessibilityLabel("Add").accessibilityIdentifier("jam-add")
                Button { composer.formattingTapped() } label: {
                    Text("Aa").font(.system(size: 17, weight: composer.toolbarVisible ? .bold : .medium)).foregroundStyle(Theme.text).frame(width: width, height: 44)
                        .background(composer.toolbarVisible ? Theme.surface : .clear, in: Circle())
                }
                .accessibilityLabel("Formatting").accessibilityIdentifier("jam-format").accessibilityAddTraits(composer.toolbarVisible ? [.isSelected] : [])
                headingButton(width: width)
                tool("arrow.uturn.backward", "Undo", id: "jam-undo", width: width) { composer.undo() }
                    .disabled(!composer.format.canUndo).opacity(composer.format.canUndo ? 1 : 0.35)
                tool("arrow.uturn.forward", "Redo", id: "jam-redo", width: width) { composer.redo() }
                    .disabled(!composer.format.canRedo).opacity(composer.format.canRedo ? 1 : 0.35)
                Spacer(minLength: 0)
                tool(composer.editing ? "keyboard.chevron.compact.down" : "keyboard", composer.editing ? "Hide keyboard" : "Show keyboard", id: "jam-hide-keyboard", width: width) { composer.toggleKeyboard() }
                    .padding(.trailing, -(width - 28) / 2)
            }
            .padding(.horizontal, 16).frame(minHeight: 48)
            .background(.bar)
        }
    }

    private func tool(_ symbol: String, _ label: String, id: String, width: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 19)).foregroundStyle(Theme.text).frame(width: width, height: 44) }
            .accessibilityLabel(label).accessibilityIdentifier(id)
    }

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

    /// A picture in the description goes in at the caret and is numbered after the post's own files.
    private func addPictureFromLibrary() {
        #if DEBUG
        if store.isDemo, let data = store.demoJamImage("p"), let image = UIImage(data: data) { addPicture(image); return }
        #endif
        pickingPicture = true
    }

    private func addPicture(_ image: UIImage) {
        guard let view = composer.textView, existingCount + newFiles.count < 10, let item = AttachmentProcessing.photo(image) else { return }
        newFiles.append(item)
        let width = max(120, view.bounds.width - 16)
        let small = image.preparingThumbnail(of: CGSize(width: 900, height: 900)) ?? image
        let caret = ComposerDocument.insertImage(small, index: existingCount + newFiles.count - 1, into: view.textStorage, at: view.selectedRange.location, width: width)
        view.selectedRange = NSRange(location: caret, length: 0)
        view.delegate?.textViewDidChange?(view)
    }

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
        .buttonStyle(.plain).accessibilityLabel("Posting as \(name)").accessibilityIdentifier("jam-post-as")
    }

    /// The co-hosts as small overlapping avatars and the person-plus to change them (as on the article page).
    private var hosts: some View {
        HStack(spacing: 2) {
            if !coauthors.isEmpty {
                Button { choosingCoauthors = true } label: {
                    HStack(spacing: -8) { ForEach(Array(coauthors.prefix(3).enumerated()), id: \.offset) { _, person in AvatarView(person: person, size: 28).overlay(Circle().stroke(Theme.canvas, lineWidth: 2)) } }
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain).accessibilityLabel("With \(coauthors.map(\.name).joined(separator: ", "))").accessibilityIdentifier("podcast-edit-hosts")
            }
            Button { choosingCoauthors = true } label: { Image(systemName: "person.badge.plus").font(.system(size: 17)).foregroundStyle(Theme.text).frame(width: 44, height: 44) }
                .accessibilityLabel("Add co-host").accessibilityIdentifier("podcast-edit-add-host")
        }
    }

    /// The cover at about 107 pt (two thirds of before) with Change cover and Remove beside it; a tap opens it full size (for a video, its poster until a cover is chosen).
    private var cover: some View {
        HStack(alignment: .center, spacing: 14) {
            Button { viewingCover = true } label: {
                Group {
                    if let newCover, let image = UIImage(data: newCover.bytes) {
                        Image(uiImage: image).resizable().scaledToFill()
                    } else if removeCover {
                        CoverArt(image: nil, person: store.teacher(post.author), org: store.orgName(post))
                    } else {
                        PostCover(postID: post.postId)
                    }
                }
                .frame(width: 107, height: 107).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cover").accessibilityHint("Opens full size").accessibilityIdentifier("podcast-edit-cover")
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    #if DEBUG
                    if store.isDemo, let data = store.demoJamImage("p"), let image = UIImage(data: data), let made = AttachmentProcessing.photo(image, name: JamCover.name) { newCover = made; removeCover = false; return }
                    #endif
                    picking = true
                } label: { Text(recording?.kind == "video" && !hasOwnCover && newCover == nil ? "Choose a cover" : "Change cover").font(Theme.secondary).foregroundStyle(Theme.text).padding(.horizontal, 14).frame(minHeight: 44).background(Theme.surface, in: Capsule()) }
                    .accessibilityLabel("Change cover").accessibilityIdentifier("podcast-edit-change-cover")
                if (hasOwnCover && !removeCover) || newCover != nil {
                    Button(role: .destructive) { newCover = nil; removeCover = hasOwnCover } label: { Text("Remove").font(Theme.secondary).padding(.horizontal, 14).frame(minHeight: 44) }
                        .accessibilityIdentifier("podcast-edit-remove-cover")
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// The recording as a row: play, its length, and whether it is audio or video. It plays here (the mini player opens).
    private var recordingRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let recording {
                let length = Double(recording.durationMs ?? 0) / 1000
                Button { play() } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "play.fill").frame(width: 36, height: 36).background(Theme.accent, in: Circle()).foregroundStyle(Theme.accentInk).accessibilityHidden(true)
                        Text(VoiceFormat.clock(length)).font(Theme.body.monospacedDigit()).foregroundStyle(Theme.text)
                        Text(recording.kind == "video" ? "Video" : "Audio").font(Theme.secondary).foregroundStyle(Theme.textSecondary)
                        Spacer()
                    }
                    .padding(.horizontal, 14).frame(minHeight: 56).background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain).accessibilityLabel("Play recording, \(PodcastFormat.spoken(length))").accessibilityIdentifier("podcast-edit-recording")
            }
            Text("To change the recording, delete the post and record again.").font(Theme.caption).foregroundStyle(Theme.textSecondary)
        }
    }

    private func play() {
        guard let item = NowPlaying.shared.makeItem(for: post, store: store) else { return }
        NowPlaying.shared.start(item)
        Task { await item.controller.toggle(data: { await store.jamAttachmentData(item.postID, item.file.attachmentId) }) }
    }

    private func update() {
        saving = true; problem = nil
        Task {
            let markdown = composer.textView.map { ComposerDocument.markdown(from: $0.textStorage, post: true) } ?? composer.markdown()
            let ok = await store.editJamPost(post, title: title, subtitle: subtitle, markdown: markdown, added: newFiles + (newCover.map { [$0] } ?? []),
                                             displayAs: postAsJam == nil ? "person" : "jam", removeCover: removeCover && newCover == nil,
                                             coauthors: Set(coauthors.map(\.id)) == Set(initialHosts) ? nil : coauthors.map(\.id))
            saving = false
            if ok { dismiss() } else { problem = "Could not update the podcast." }
        }
    }
}
