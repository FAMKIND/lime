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
        if event.presence?.away == true { draftLive[event.draftId]?[event.fromUser] = nil } else { draftLive[event.draftId, default: [:]][event.fromUser] = .now }
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
    func sharedDraft(forPost post: JamPostInfo) -> String? {
        // Cheap checks first: this runs while every card is drawn.
        let me = meProvider().id
        guard FeatureFlags.coedit, post.author == me || post.coauthors.contains(me), let core else { return nil }
        let postID = post.postId
        guard let info = ((try? core.listDrafts()) ?? []).first(where: { $0.postId == postID }) else { return nil }
        return ((try? core.draftChannels()) ?? []).contains(where: { $0.draftId == info.draftId }) ? info.draftId : nil
    }

    /// The co-authors I picked write the draft too: each is invited (the invitation is sealed to them like a message).
    func coeditShare(_ id: String, with people: [String]) {
        guard let core = draftCore, !people.isEmpty else { return }
        try? core.shareDraft(draftId: id, authors: people)
        refreshDraftChannels()
    }

    /// The editor's text goes into the draft from where the editor last matched it; returns the draft's heads now.
    func coeditMerge(_ id: String, base: [String], title: String, subtitle: String, markdown: String) -> [String]? {
        try? draftCore?.draftMergeEditor(draftId: id, base: base, title: title, subtitle: subtitle, markdown: markdown)
    }

    func coeditHeads(_ id: String) -> [String] { (try? draftCore?.draftHeads(draftId: id)) ?? [] }
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


// MARK: Drafts in jam, and the invitation banner (LIME-233g)

/// One line of jam's Drafts.
struct DraftRow: Identifiable {
    let draftID: String
    let title: String
    let authors: [Person]
    let updatedAt: Int64
    /// The other authors writing in it now (heard in the last 25 s).
    let live: [Person]
    let pinned: Bool
    /// I am the writer (a draft nobody shares counts): Delete removes it for everyone; otherwise the row says Leave.
    let isWriter: Bool
    var id: String { draftID }
}

extension ConversationStore {
    /// Your drafts and the drafts you are invited to: pinned first, then newest first. A draft made to edit a published post that nobody else writes in
    /// is not listed.
    func draftRows(now: Date = .now) -> [DraftRow] {
        _ = draftRevision
        guard let core = draftCore else { return [] }
        let channels = Set(((try? core.draftChannels()) ?? []).map(\.draftId))
        let me = meProvider()
        let rows: [DraftRow] = ((try? core.listDrafts()) ?? [])
            .filter { $0.postId == nil || channels.contains($0.draftId) }
            .map { info in
                let all = (try? core.draftAuthors(draftId: info.draftId)) ?? []
                var others = all.filter { $0.status == "active" }.map(\.userId).filter { $0 != me.id }.map { teacher($0) }
                var isWriter = (all.first(where: \.isWriter)?.userId).map { $0 == me.id } ?? true
                #if DEBUG
                if let sim = simDraftAuthors[info.draftId] { others = sim.others; isWriter = sim.isWriter }
                #endif
                let live = others.filter { person in draftLive[info.draftId]?[person.id].map { now.timeIntervalSince($0) < 25 } ?? false }
                return DraftRow(draftID: info.draftId, title: info.title, authors: [me] + others, updatedAt: info.updatedAt, live: live,
                                pinned: draftPins.contains(info.draftId), isWriter: isWriter)
            }
        return rows.sorted { ($0.pinned ? 1 : 0, $0.updatedAt) > ($1.pinned ? 1 : 0, $1.updatedAt) }
    }

    func togglePin(_ ids: [String]) {
        let allPinned = ids.allSatisfy { draftPins.contains($0) }
        for id in ids { if allPinned { draftPins.remove(id) } else { draftPins.insert(id) } }
        UserDefaults.standard.set(Array(draftPins), forKey: "lime.draft.pins")
        draftRevision += 1
    }

    /// A new private draft with the same words; returns its id.
    @discardableResult func copyDraft(_ id: String) -> String? {
        let copy = try? draftCore?.copyDraft(draftId: id)
        draftRevision += 1
        return copy
    }

    /// The writer's Delete removes the draft for every author; a co-author's Leave takes their copy away and leaves the others to it.
    func removeDraft(_ row: DraftRow) {
        guard let core = draftCore else { return }
        if isDemo { try? core.deleteDraft(draftId: row.draftID) }
        else if row.isWriter { try? core.deleteDraftForEveryone(draftId: row.draftID) } else { try? core.leaveAndDeleteDraft(draftId: row.draftID) }
        draftPins.remove(row.draftID); draftSelection.remove(row.draftID)
        refreshDraftChannels()
        draftRevision += 1
        Task { await flushDrafts() }
    }

    func exitDraftSelection() { draftSelecting = false; draftSelection = [] }

    /// After a sync: an invitation I have not been told about is announced once, in the app's glass banner.
    func announceNewDraftInvites() {
        let told = Set(UserDefaults.standard.stringArray(forKey: "lime.draft.invites.announced") ?? [])
        let fresh = draftInvites().filter { !told.contains($0.draftID) }
        guard let first = fresh.first else { return }
        UserDefaults.standard.set(Array(told.union(fresh.map(\.draftID))), forKey: "lime.draft.invites.announced")
        draftInviteBanner = first
    }

    func openDraftFromBanner() {
        guard let banner = draftInviteBanner else { return }
        draftInviteBanner = nil
        openDraftRoute = DraftRoute(id: banner.draftID)
    }
}

#if DEBUG
extension ConversationStore {
    /// Tests only: `-lime-drafts-sim` makes three drafts (one with three authors, Jean writing in it now; one a co-author's; one private).
    func simulateDraftsIfAsked() {
        guard isDemo, ProcessInfo.processInfo.arguments.contains("-lime-drafts-sim"), !simulatedDrafts, let core = draftCore else { return }
        simulatedDrafts = true
        for old in (try? core.listDrafts()) ?? [] { try? core.deleteDraft(draftId: old.draftId) }   // the demo's core may be kept between runs
        let jean = Person(id: "sim-jean", name: "Jean Park", tone: 4), fam = Person(id: "sim-fam", name: "FAM Kind", tone: 2), lee = Person(id: "sim-lee", name: "Lee Wong", tone: 6)
        if let id = try? core.createDraft(title: "The roots of the lime tree", subtitle: "", markdown: "Roots.") {
            simDraftAuthors[id] = (others: [jean, fam], isWriter: true)
            draftLive[id] = ["sim-jean": .now]
        }
        if let id = try? core.createDraft(title: "Fractions plan", subtitle: "", markdown: "Plan.") { simDraftAuthors[id] = (others: [lee], isWriter: false) }
        _ = try? core.createDraft(title: "My private notes", subtitle: "", markdown: "Notes.")
        draftRevision += 1
    }

    /// Tests only: `-lime-coedit-sim-invite` makes a shared draft appear as if Jean had just invited this account to write it.
    func simulateDraftInviteIfAsked() {
        guard isDemo, ProcessInfo.processInfo.arguments.contains("-lime-coedit-sim-invite"), draftInviteBanner == nil, !simulatedInvite, let core = draftCore else { return }
        simulatedInvite = true
        guard let id = try? core.createDraft(title: "The roots of the lime tree", subtitle: "", markdown: "Hello from Jean.") else { return }
        draftInviteBanner = DraftInvite(draftID: id, writer: "sim-jean", title: "The roots of the lime tree")
    }
}
#endif
