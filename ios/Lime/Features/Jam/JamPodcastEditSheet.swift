import SwiftUI

/// Edit decides which editor a post gets (LIME-212): a recording opens a **podcast page**, everything else the writing screen.
struct JamEditSheet: View {
    let post: JamPostInfo
    var body: some View {
        if post.kind == "record" { JamPodcastEditSheet(post: post) } else { JamComposeSheet(editing: post) }
    }
}

/// Editing a podcast (LIME-212): who it is from, the cover, the recording (playable here), title, subtitle and description. No formatting bar, no
/// article. The recording itself is not replaced here. Update saves it as today's edit does and, with a new cover, replaces `cover.jpg`.
struct JamPodcastEditSheet: View {
    let post: JamPostInfo
    @Environment(ConversationStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var subtitle: String
    @State private var details: String
    @State private var newCover: OutgoingAttachment?
    @State private var removeCover = false
    @State private var postAsJam: String?
    @State private var postingAs = false
    @State private var picking = false
    @State private var saving = false
    @State private var problem: String?

    init(post: JamPostInfo) {
        self.post = post
        _title = State(initialValue: post.title)
        _subtitle = State(initialValue: post.subtitle)
        _details = State(initialValue: post.markdown)
        _postAsJam = State(initialValue: post.displayAs == "jam" ? post.jamId : nil)
    }

    private var files: [JamAttachmentInfo] { store.jamAttachments(post.postId) }
    private var recording: JamAttachmentInfo? { files.first { $0.kind == "audio" } ?? files.first { $0.kind == "video" } }
    private var hasOwnCover: Bool { files.contains(where: JamCover.isCover) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    postAsChip
                    cover
                    recordingRow
                    field("Title", text: $title, limit: 120, id: "podcast-edit-title")
                    field("Subtitle", text: $subtitle, limit: 160, id: "podcast-edit-subtitle")
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Description").font(Theme.caption).foregroundStyle(Theme.textSecondary)
                        TextField("Description", text: $details, axis: .vertical).lineLimit(3...10).font(Theme.body)
                            .padding(14).background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .accessibilityIdentifier("podcast-edit-description")
                    }
                    if let problem { Text(problem).font(Theme.secondary).foregroundStyle(.red) }
                }
                .padding(20)
            }
            .background(Theme.canvas)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Edit").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.accessibilityIdentifier("podcast-edit-cancel") }
                ToolbarItem(placement: .confirmationAction) { Button("Update") { update() }.fontWeight(.semibold).disabled(saving || title.trimmingCharacters(in: .whitespaces).isEmpty).accessibilityIdentifier("podcast-edit-update") }
            }
            .sheet(isPresented: $postingAs) { PostAsSheet(selection: $postAsJam) }
            .fullScreenCover(isPresented: $picking) {
                MediaLibraryPicker(limit: 1, onPick: { images, _ in
                    picking = false
                    if let image = images.first, let made = AttachmentProcessing.photo(image, name: JamCover.name) { newCover = made; removeCover = false }
                }, onCancel: { picking = false }).ignoresSafeArea()
            }
        }
    }

    private var postAsChip: some View {
        let jam = postAsJam.flatMap { id in store.jamsMine.first { $0.jamId == id } }
        let name = jam?.title ?? store.meProvider().name
        return Button { postingAs = true } label: {
            HStack(spacing: 8) {
                if let jam { JamInitialTile(title: jam.title, size: 32).accessibilityHidden(true) } else { AvatarView(person: store.meProvider(), size: 32).accessibilityHidden(true) }
                Text(name).font(Theme.font(.subheadline, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.textSecondary)
            }
            .frame(minHeight: 44)
        }
        .buttonStyle(.plain).accessibilityLabel("Posting as \(name)").accessibilityIdentifier("jam-post-as")
    }

    /// The cover at about 160 pt with Change cover and Remove (for a video, its poster until a cover is chosen).
    private var cover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Group {
                if let newCover, let image = UIImage(data: newCover.bytes) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else if removeCover {
                    CoverArt(image: nil, person: store.teacher(post.author), org: store.orgName(post))
                } else {
                    PostCover(postID: post.postId)
                }
            }
            .frame(width: 160, height: 160).clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .accessibilityLabel("Cover").accessibilityIdentifier("podcast-edit-cover")
            HStack(spacing: 10) {
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

    private func field(_ label: String, text: Binding<String>, limit: Int, id: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(Theme.caption).foregroundStyle(Theme.textSecondary)
            TextField(label, text: text).font(Theme.body).padding(14)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .onChange(of: text.wrappedValue) { _, now in if now.count > limit { text.wrappedValue = String(now.prefix(limit)) } }
                .accessibilityIdentifier(id)
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
            let ok = await store.editJamPost(post, title: title, subtitle: subtitle, markdown: details, added: newCover.map { [$0] } ?? [],
                                             displayAs: postAsJam == nil ? "person" : "jam", removeCover: removeCover && newCover == nil)
            saving = false
            if ok { dismiss() } else { problem = "Could not update the podcast." }
        }
    }
}
