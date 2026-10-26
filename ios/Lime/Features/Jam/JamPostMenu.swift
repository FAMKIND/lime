import SwiftUI

/// Which posts are marked played on this phone (LIME-199); never sent anywhere.
enum JamPlayed {
    static let key = "lime.jam.playedPosts"
    static func contains(_ id: String) -> Bool { (UserDefaults.standard.stringArray(forKey: key) ?? []).contains(id) }
    static func toggle(_ id: String) {
        var now = UserDefaults.standard.stringArray(forKey: key) ?? []
        if let at = now.firstIndex(of: id) { now.remove(at: at) } else { now.append(id) }
        UserDefaults.standard.set(now, forKey: key)
    }
}

/// The ⋯ at the top right of every card (LIME-199): a compact system menu, groups separated: **share** (with Edit when it is yours), **playback** for a
/// recording (Play now, Play next, Add to queue, Mark as played), **keep** (Save), for someone else's post **Hide post**, and last, alone, **Delete** (yours). No Copy link (posts are
/// end-to-end encrypted: there is no public link until LIME-190), no Like until LIME-189.
struct JamPostMenu: View {
    let post: JamPostInfo
    @Environment(ConversationStore.self) private var store
    @AppStorage(JamSaved.key) private var savedList = ""
    @AppStorage(JamPlayed.key) private var playedList = ""
    @State private var editing: JamPostInfo?
    @State private var openDraft: DraftRoute?
    @State private var confirmingDelete = false
    @State private var sharing = false
    @State private var reporting: ReportTarget?

    var body: some View {
        let mine = post.author == store.meProvider().id
        let saved = JamSaved.contains(post.postId)
        let played = JamPlayed.contains(post.postId)
        let playable = post.kind == "record" && post.state == "ready" && NowPlaying.shared.makeItem(for: post, store: store) != nil
        Menu {
            Section {
                if let draft = store.sharedDraft(forPost: post.postId) { Button { openDraft = DraftRoute(id: draft) } label: { Label("Open draft", systemImage: "doc.text") }.accessibilityIdentifier("card-open-draft") }
                if mine { Button { editing = post } label: { Label("Edit", systemImage: "pencil") }.accessibilityIdentifier("card-edit") }
                Button { sharing = true } label: { Label("Share in lime\u{2026}", systemImage: "square.and.arrow.up") }.accessibilityIdentifier("card-share")
            }
            if playable {
                Section {
                    Button { play() } label: { Label("Play now", systemImage: "play") }.accessibilityIdentifier("card-play-now")
                    Button { if let item = NowPlaying.shared.makeItem(for: post, store: store) { NowPlaying.shared.playNext(item) } } label: { Label("Play next", systemImage: "text.insert") }.accessibilityIdentifier("card-play-next")
                    Button { if let item = NowPlaying.shared.makeItem(for: post, store: store) { NowPlaying.shared.enqueue(item) } } label: { Label("Add to queue", systemImage: "text.badge.plus") }.accessibilityIdentifier("card-add-queue")
                    Button { JamPlayed.toggle(post.postId); playedList = JamPlayed.contains(post.postId) ? "1" : "0" } label: {
                        Label(played ? "Mark as unplayed" : "Mark as played", systemImage: played ? "circle" : "checkmark.circle")
                    }.accessibilityIdentifier("card-played")
                }
            }
            Section {
                Button { JamSaved.toggle(post.postId); savedList = JamSaved.contains(post.postId) ? "1" : "0" } label: { Label(saved ? "Saved \u{2713}" : "Save", systemImage: saved ? "bookmark.fill" : "bookmark") }.accessibilityIdentifier("card-save")
            }
            if !mine {
                Section {
                    Button { store.hideJamPost(post.postId) } label: { Label("Hide post", systemImage: "eye.slash") }.accessibilityIdentifier("card-hide")
                    Button(role: .destructive) { reporting = store.reportTarget(post: post) } label: { Label("Report", systemImage: "flag") }.accessibilityIdentifier("card-report")
                }
            }
            // Delete is last, alone in its group (LIME-218).
            if mine {
                Section {
                    Button(role: .destructive) { confirmingDelete = true } label: { Label("Delete", systemImage: "trash") }.accessibilityIdentifier("card-delete")
                }
            }
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.textSecondary).frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .accessibilityLabel("More").accessibilityIdentifier("card-more-\(post.postId)")
        .fullScreenCover(item: $editing) { JamEditSheet(post: $0) }
        .fullScreenCover(item: $openDraft) { JamComposeSheet(openDraft: $0.id) }
        .sheet(isPresented: $sharing) { JamShareSheet(post: post) }
        .reportSheet($reporting)
        .confirmationDialog("Delete this post for everyone?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { Task { _ = await store.deleteJamPost(post.postId) } }.accessibilityIdentifier("card-delete-confirm")
            Button("Cancel", role: .cancel) {}
        } message: { Text("Subscribers' copies are removed.") }
    }

    private func play() {
        guard let item = NowPlaying.shared.makeItem(for: post, store: store) else { return }
        NowPlaying.shared.start(item)
        NowPlaying.shared.showsScreen = true
        Task { await item.controller.toggle(data: { await store.jamAttachmentData(item.postID, item.file.attachmentId) }) }
    }
}
