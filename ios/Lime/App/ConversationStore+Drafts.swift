import Foundation

/// Drafts written with others (LIME-233b): the instant path (Realtime broadcast) and the durable flush, from the app's side.
extension ConversationStore {
    /// Opens the socket for the drafts I write in. Called once the account is live.
    func startDraftRealtime(_ config: BackendConfig) {
        #if DEBUG
        if isDemo { return }
        #endif
        guard core != nil else { return }
        draftRealtime = DraftRealtime(baseURL: config.url, apiKey: config.apiKey) { [weak self] channel, wire in
            Task { @MainActor in self?.receiveInstant(channel: channel, wire: wire) }
        }
        refreshDraftChannels()
    }

    /// Joins the channels of the drafts I am an author of (after an invitation, a removal, a new draft).
    func refreshDraftChannels() {
        guard let core, let realtime = draftRealtime else { return }
        let channels = Set(((try? core.draftChannels()) ?? []).map(\.channelId))
        Task { await realtime.setChannels(channels) }
    }

    private func receiveInstant(channel: String, wire: Data) {
        guard let core, let event = (try? core.draftInstantReceive(channelId: channel, wire: wire)) ?? nil else { return }
        draftRevision += 1
        draftEventSink?(event)
    }

    /// The editor changed the draft: the change goes out at once on the instant path (the durable path follows within seconds).
    func sendDraftChangeInstantly(_ draftID: String) {
        guard let core, let realtime = draftRealtime else { return }
        guard let wire = (try? core.draftInstantChange(draftId: draftID)) ?? nil,
              let channel = ((try? core.draftChannels()) ?? []).first(where: { $0.draftId == draftID })?.channelId else { return }
        Task { await realtime.broadcast(channel: channel, wire: wire) }
    }

    /// My caret and selection, instantly.
    func sendDraftPresence(_ draftID: String, _ presence: DraftPresence) {
        guard let core, let realtime = draftRealtime else { return }
        guard let wire = (try? core.draftInstantPresence(draftId: draftID, presence: presence)) ?? nil,
              let channel = ((try? core.draftChannels()) ?? []).first(where: { $0.draftId == draftID })?.channelId else { return }
        Task { await realtime.broadcast(channel: channel, wire: wire) }
    }

    /// Sends what is due on the durable path now.
    func flushDrafts() async {
        guard let core, let link, let token = try? await link.token() else { return }
        _ = try? await Task.detached { try core.flushDrafts(transport: link.transport, authToken: token) }.value
    }
}

// MARK: The article editor's draft (LIME-233c)

extension ConversationStore {
    /// The core that holds drafts: the real one, or (in demo runs) a throwaway one, so the editor can be tested without an account.
    var draftCore: LimeStore? {
        if let core { return core }
        #if DEBUG
        if isDemo {
            if demoDraftCore == nil {
                demoDraftCore = try? LimeStore.open(path: NSTemporaryDirectory() + "demo-drafts-\(UUID().uuidString).db", key: Data(repeating: 7, count: 32))
            }
            return demoDraftCore
        }
        #endif
        return nil
    }

    /// A session for the article being written or edited; nil when co-editing is off.
    func coeditSession(existingID: String?, forPost post: JamPostInfo?, title: String, subtitle: String, markdown: String) -> CoEditSession? {
        guard FeatureFlags.coedit, let core = draftCore else { return nil }
        if let existingID, (try? core.draftMeta(draftId: existingID)) != nil { return CoEditSession(draftID: existingID, store: self) }
        if let post, let found = ((try? core.listDrafts()) ?? []).first(where: { $0.postId == post.postId }) { return CoEditSession(draftID: found.draftId, store: self) }
        guard let id = try? core.createDraft(title: title, subtitle: subtitle, markdown: markdown) else { return nil }
        if let post { try? core.draftLinkPost(draftId: id, postId: post.postId) }
        return CoEditSession(draftID: id, store: self)
    }

    func coeditReconcile(_ id: String, title: String, subtitle: String, markdown: String) -> Bool {
        guard let core = draftCore else { return false }
        return (try? core.draftReconcile(draftId: id, title: title, subtitle: subtitle, markdown: markdown)) != nil
    }

    // Publishing and pictures (LIME-233e)

    func coeditStatus(_ id: String) -> DraftStatus? { try? draftCore?.draftStatus(draftId: id) }
    func coeditSetReady(_ id: String, _ ready: Bool) { try? draftCore?.draftSetReady(draftId: id, ready: ready); Task { await flushDrafts() } }
    func coeditAddFile(_ id: String, _ file: OutgoingAttachment) -> UInt32? { try? draftCore?.draftAddFile(draftId: id, file: file) }
    func coeditFiles(_ id: String) -> [DraftFileInfo] { (try? draftCore?.draftFiles(draftId: id)) ?? [] }

    /// The bytes of a draft's picture, fetched from the server if this phone does not have them.
    func coeditFileData(_ id: String, _ number: UInt32) async -> Data? {
        guard let core = draftCore else { return nil }
        if let link, let token = try? await link.token() {
            return try? await Task.detached { try core.draftFileData(transport: link.transport, authToken: token, draftId: id, number: number) }.value
        }
        return nil
    }

    /// The writer's post is out (or updated): the other authors are told.
    func coeditPublished(_ id: String, postID: String) { try? draftCore?.draftMarkPublished(draftId: id, postId: postID); Task { await flushDrafts() } }

    func coeditSeen(_ id: String) { try? draftCore?.markDraftSeen(draftId: id) }
    func coeditBlocks(_ id: String) -> [DraftBlock] { (try? draftCore?.draftBlocks(draftId: id)) ?? [] }
    /// The people (ids) who write the draft, me included, not those who left or were removed.
    func coeditAuthors(_ id: String) -> [String] { ((try? draftCore?.draftAuthors(draftId: id)) ?? []).filter { $0.status == "active" }.map(\.userId) }

    /// Draft invitations that have not been opened: "Shem invited you to write <title>" in Activity.
    func draftInvites() -> [DraftInvite] {
        _ = draftRevision
        guard let core = draftCore else { return [] }
        return ((try? core.unseenDraftInvites()) ?? []).compactMap { id in
            guard let meta = try? core.draftMeta(draftId: id) else { return nil }
            let writer = ((try? core.draftAuthors(draftId: id)) ?? []).first(where: \.isWriter)?.userId ?? ""
            return DraftInvite(draftID: id, writer: writer, title: meta.title)
        }
    }

    /// A shared draft the post was made from (for the post's ⋯ "Open draft"): one I write in.
    func sharedDraft(forPost postID: String) -> String? {
        guard let core = draftCore, let info = ((try? core.listDrafts()) ?? []).first(where: { $0.postId == postID }) else { return nil }
        return ((try? core.draftChannels()) ?? []).contains(where: { $0.draftId == info.draftId }) ? info.draftId : nil
    }

    /// The co-authors I picked write the draft too: each is invited (the invitation is sealed to them like a message).
    func coeditShare(_ id: String, with people: [String]) {
        guard let core = draftCore, !people.isEmpty else { return }
        try? core.shareDraft(draftId: id, authors: people)
        refreshDraftChannels()
    }

    func coeditMarkdown(_ id: String) -> String? { try? draftCore?.draftMarkdown(draftId: id) }
    func coeditMeta(_ id: String) -> DraftMeta? { try? draftCore?.draftMeta(draftId: id) }
    func coeditTakePatches(_ id: String) -> [DraftPatch] { (try? draftCore?.draftTakePatches(draftId: id)) ?? [] }

    /// The post went out: a draft nobody else writes in is no longer needed.
    func coeditFinish(_ id: String) {
        guard let core = draftCore else { return }
        if ((try? core.draftChannels()) ?? []).contains(where: { $0.draftId == id }) { return }
        try? core.deleteDraft(draftId: id)
    }

    /// Debug/test hook: another author's words arrive (applied to the draft as a remote change).
    #if DEBUG
    func coeditSimulateRemote(_ id: String, mutate: (String) -> String) {
        func log(_ text: String) { NSLog("COEDIT %@", text) }
        log("simulate start \(id)")
        guard let core = draftCore, let markdown = try? core.draftMarkdown(draftId: id), let snapshot = try? core.draftSnapshot(draftId: id) else { log("no core/markdown/snapshot"); return }
        let dir = NSTemporaryDirectory() + "demo-remote-\(UUID().uuidString).db"
        guard let other = try? LimeStore.open(path: dir, key: Data(repeating: 9, count: 32)) else { log("no other"); return }
        do { try other.joinDraft(draftId: id, snapshot: snapshot) } catch { log("join failed \(error)") }
        do { try other.draftReconcile(draftId: id, title: (try? other.draftMeta(draftId: id).title) ?? "", subtitle: (try? other.draftMeta(draftId: id).subtitle) ?? "", markdown: mutate(markdown)) } catch { log("reconcile failed \(error)") }
        log("other now: \((try? other.draftMarkdown(draftId: id)) ?? "?")")
        if let heads = try? core.draftHeads(draftId: id), let changes = try? other.draftChangesSince(draftId: id, heads: heads) {
            log("changes \(changes.count) bytes")
            do { _ = try core.draftApplyChanges(draftId: id, bytes: changes) } catch { log("apply failed \(error)") }
            log("core now: \((try? core.draftMarkdown(draftId: id)) ?? "?")")
            draftRevision += 1
        }
    }
    #endif
}


/// "Shem invited you to write <title>".
struct DraftInvite: Identifiable {
    let draftID: String
    let writer: String
    let title: String
    var id: String { draftID }
}
