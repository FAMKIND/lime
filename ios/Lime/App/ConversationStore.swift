import SwiftUI

/// What the signed-in phone talks to: LimeCore's network and a fresh access token for each call.
struct BackendLink: Sendable {
    let transport: Transport
    let token: @Sendable () async throws -> String
}

/// Where the navigation stack can be sent besides a chat.
enum MessagesRoute: Hashable { case requests, search }

/// The app's view of its conversations. The data lives in LimeCore's encrypted local store; every
/// store call runs off the main thread and the UI updates here, on the main actor. Once the phone is
/// signed in and registered (`connect`), a message you send is queued locally ("Sending…"), delivered
/// as an end-to-end encrypted message ("Sent"), and the mailbox is fetched on a nudge, on foreground
/// and on pull-to-refresh. Without a backend (tests, previews) a send stays on the phone.
@MainActor
@Observable
final class ConversationStore {
    var conversations: [Conversation] = []
    /// Announces new messages (banner, tick, local notification); set by the app.
    @ObservationIgnored var notifications: NotificationCoordinator?
    @ObservationIgnored private var detector = ArrivalDetector()
    var banner: String?
    /// What each accepted contact last told this phone about their status (periods that ended are left out).
    var statuses: [String: PeerStatus] = [:]
    /// The phone is nearly full: automatic downloads are paused (Messages says so).
    var lowStorage = false
    /// Until when the server still has an attachment (`.some(nil)`: it is gone), as asked this session.
    var availability: [String: Date??] = [:]
    /// Attachments being downloaded because someone tapped them (their tile shows a ring).
    var downloading: Set<String> = []
    /// True once the store has opened and the first load has finished.
    private(set) var isLoaded = false
    /// Set when the encrypted store could not be opened (the About sheet reports it).
    private(set) var storageError: String?
    private(set) var databasePath: String?
    /// Shown on Messages after the previous data could not be opened and a fresh store was made.
    private(set) var showsRecoveryNotice = false

    private(set) var core: LimeStore?
    private var bannerTask: Task<Void, Never>?

    /// The screens pushed on Messages (chats by id, the Requests list).
    var path = NavigationPath()
    private(set) var link: BackendLink?
    /// How the signed-in person is shown (set by the account session): core calls them "me".
    var meProvider: @MainActor () -> Person = { SampleData.me }
    /// The threads that are open on screen: the root message, then its replies. Kept fresh by `reload()`.
    var threads: [String: [Message]] = [:]
    private var openThreadIDs: Set<String> = []
    private var isSyncing = false
    private var syncAgain = false
    /// Why the last call to the server failed, in true words; nil once one succeeds. A session that
    /// ended asks the person to sign in again (their chats and keys stay on the phone meanwhile).
    private(set) var problem: ConnectionProblem?
    /// Registers this device when it is not connected yet (set by the account session), so a phone
    /// that was offline at launch, or whose first attempt failed, connects on the next sync.
    var registrar: (@MainActor () async -> Void)?
    #if DEBUG
    /// Debug builds only (`-lime-demo-chat`): made-up conversations that live in memory, for screenshots and UI tests.
    private(set) var isDemo = false
    /// Debug demo: my photo and who may see it (no server).
    /// Debug demo: the decrypted bytes of the demo attachments, by id, and whether the composer opens with drafts.
    var demoAttachmentData: [String: Data] = [:]
    var demoDrafts = false
    var demoTransfer: [String: TransferProgress] = [:]
    #endif
    /// The picture viewer and the file opener that are showing (LIME-98c).
    var attachmentViewer: AttachmentViewerRequest?
    var openedFile: AttachmentItem?
    var playingVideo: VideoRequest?
    #if DEBUG
    var demoMyPhoto: Data?
    var demoPhotoVisibility: PhotoVisibility = .everyone
    #endif

    /// The one call at a time (LIME-111). UI tests and demo mode use stand-ins with no system call screen.
    @ObservationIgnored private var callManager: CallManager?
    /// My account's user id (for the call rule that settles crossed calls).
    @ObservationIgnored var myUserID: String?
    var calls: CallManager {
        if let callManager { return callManager }
        var quiet = false
        #if DEBUG
        quiet = ProcessInfo.processInfo.arguments.contains("-lime-skip-sign-in") || ProcessInfo.processInfo.arguments.contains("-lime-fake-auth")
        #endif
        let system: CallSystem = quiet ? QuietCallSystem() : CallKitSystem()
        let manager = CallManager(signalling: StoreSignalling(store: self), system: system, sounds: quiet ? QuietCallSounds() : SystemCallSounds(),
                                  isQuiet: { StatusSettings.shared.plan().isQuiet }, myID: { [weak self] in self?.myUserID }, makeMedia: { WebRTCMedia(manualAudio: !quiet) })
        manager.fetchNow = { [weak self] in await self?.fetchCallOps() }
        callManager = manager
        return manager
    }

    /// A light fetch while a call is ringing or connecting: the mailbox and the call ops, nothing else, and never skipped because a
    /// full sync is running.
    func fetchCallOps() async {
        guard let core, let link else { return }
        let diag = CallDiagnostics.shared
        let started = Date()
        do {
            let token = try await link.token()
            let found = try await Task.detached(priority: .userInitiated) { try core.fetchCallOps(transport: link.transport, authToken: token) }.value
            diag.log("fetch ok \(Int(Date().timeIntervalSince(started) * 1000)) ms: downloaded \(core.takeDownloaded()), stored \(found), pending [\((try? core.pendingSummary()) ?? "?")]")
        } catch {
            diag.log("fetch failed \(Int(Date().timeIntervalSince(started) * 1000)) ms: \(error)")
        }
        let waited = core.takeLockWaitMs()
        if waited > 250 { diag.log("waited \(waited) ms for the core lock") }
        await deliverCallEvents()
    }

    /// Hands the call ops that arrived to the call manager (after a sync).
    func deliverCallEvents() async {
        guard let core, let events = try? core.takeCallEvents(), !events.isEmpty else { return }
        let infos = events.map { event -> CallEventInfo in
            let payload = (try? JSONSerialization.jsonObject(with: Data(event.payload.utf8))) as? [String: Any] ?? [:]
            let name = conversations.first { $0.members.count == 1 && $0.members.first?.id == event.peer }?.title ?? "Someone"
            return CallEventInfo(op: event.op, callID: event.callId, peerID: event.peer, peerName: name, payload: payload)
        }
        // Handled in the call manager's own queue, not inside this sync, so a slow step never holds up the next fetch.
        Task { @MainActor in await calls.handle(infos) }
    }

    /// Accepted conversations (the Messages list) and strangers' first messages (the Requests list).
    var chats: [Conversation] { conversations.filter { !$0.isRequest } }
    var requests: [Conversation] { conversations.filter(\.isRequest) }

    /// Where the database lives (tests use a temporary folder; nil is Application Support).
    private let storageLocation: StorageBootstrap.Location?

    init(storageLocation: StorageBootstrap.Location? = nil) {
        self.storageLocation = storageLocation
    }

    /// For tests: use an already opened store.
    init(store: LimeStore, path: String? = nil) {
        storageLocation = nil
        core = store
        databasePath = path
    }

    // MARK: Loading

    /// Opens the encrypted store (creating it and seeding the sample data on first launch).
    func bootstrap(arguments: [String] = ProcessInfo.processInfo.arguments) async {
        if core == nil {
            let resetStore = StorageBootstrap.resetRequested(arguments: arguments, debugBuild: StorageBootstrap.isDebugBuild)
            let location = storageLocation
            do {
                let opened = try await Task.detached(priority: .userInitiated) {
                    StorageBootstrap.applyDebugHooks(arguments: arguments)
                    return try StorageBootstrap.open(at: location, resetFirst: resetStore)
                }.value
                core = opened.store
                databasePath = opened.path
                if opened.startedFresh { UserDefaults.standard.set(true, forKey: Self.noticePendingKey) }
                showsRecoveryNotice = UserDefaults.standard.bool(forKey: Self.noticePendingKey)
            } catch {
                storageError = "Storage could not be opened."
                isLoaded = true
                return
            }
        }
        await reload()
    }

    private static let noticePendingKey = "lime.recoveryNoticePending"

    /// The notice is on screen now: it will not come back on the next launch.
    func recoveryNoticeAppeared() {
        UserDefaults.standard.removeObject(forKey: Self.noticePendingKey)
    }

    func dismissRecoveryNotice() {
        UserDefaults.standard.removeObject(forKey: Self.noticePendingKey)
        showsRecoveryNotice = false
    }

    /// Registers this device with the backend (idempotent) and tops up its one-time keys.
    func registerDevice(transport: Transport, token: String) async throws -> DeviceInfo {
        guard let core else { throw AuthError.network }
        let info = try await Task.detached(priority: .userInitiated) {
            try core.registerDevice(transport: transport, authToken: token)
        }.value
        // The last 4 characters, to match this phone against the server's device list.
        CallDiagnostics.shared.log("app start: device …\(info.deviceId.suffix(4))")
        return info
    }

    /// The phone is registered: from now on sends are delivered and the mailbox is fetched.
    func connect(_ link: BackendLink) {
        self.link = link
        problem = nil
    }

    /// The session ended on this phone: stop talking to the server but keep the chats and keys, so
    /// signing in again as the same person loses nothing.
    func disconnect() {
        link = nil
        path = NavigationPath()
    }

    /// Records why a call failed (and shows it on Messages).
    func report(_ failure: ConnectionProblem) {
        problem = failure
    }

    var isConnected: Bool { link != nil }

    /// Delivers what is waiting to be sent, then fetches the mailbox and refreshes the list. Calls
    /// that arrive while one is running are folded into one more round afterwards.
    func syncNow() async {
        if link == nil, let registrar { await registrar() }
        guard let core, let link else { return }
        if isSyncing { syncAgain = true; return }
        isSyncing = true
        defer { isSyncing = false }
        repeat {
        repeat {
            syncAgain = false
            do {
                let token = try await link.token()
                // Sends first (they keep their order); a failure leaves them "Not sent" for a retry.
                _ = try? await Task.detached(priority: .userInitiated) {
                    try core.deliverQueued(transport: link.transport, authToken: token)
                }.value
                let report = try await Task.detached(priority: .userInitiated) {
                    try core.sync(transport: link.transport, authToken: token)
                }.value
                let downloaded = core.takeDownloaded()
                if downloaded > 0 || report.pending > 0 {
                    CallDiagnostics.shared.log("sync: downloaded \(downloaded), stored \(report.received), pending [\((try? core.pendingSummary()) ?? "?")]")
                }
                problem = nil
            } catch {
                problem = ConnectionProblem.from(error)
            }
            await reload()
            await deliverCallEvents()
        } while syncAgain
        // Other people's photos, at most hourly each; this is off the critical path of the messages.
        await refreshPhotos()
        await refreshGroupPhotos()
        await downloadRecentImages()
        // A nudge that came in while the photo work above ran is not lost: sync again.
        } while syncAgain
    }

    /// Sends what is queued (a message that failed is retried here).
    func deliverNow() async {
        guard let core, let link else { return }
        publishStatus()
        do {
            let token = try await link.token()
            _ = try await Task.detached(priority: .userInitiated) {
                try core.deliverQueued(transport: link.transport, authToken: token)
            }.value
            problem = nil
        } catch {
            // A key change is shown in the chat itself; everything else on Messages.
            if case StoreError.KeyMismatch = error {} else { problem = ConnectionProblem.from(error) }
        }
        await reload()
    }

    /// New message: finds one person by exact username or email. `nil` means nobody (or they chose
    /// not to be found).
    func find(_ query: String) async throws -> FoundUser? {
        #if DEBUG
        if isDemo {
            try? await Task.sleep(for: .milliseconds(300))
            return query.lowercased().contains("nobody") ? nil
                : FoundUser(userId: "grace", displayName: "Grace Hopper", username: "grace.h", school: "Naval Academy", aboutEmoji: "⚓", aboutText: "Debugging since 1947", isSelf: false)
        }
        #endif
        if link == nil, let registrar { await registrar() }
        guard let link else { throw AuthError.network }
        let token = try await link.token()
        return try await Task.detached(priority: .userInitiated) {
            try findUser(transport: link.transport, authToken: token, query: query)
        }.value
    }

    /// Opens (creating if needed) the chat with a person found by `find`, and shows it.
    func startChat(with person: FoundUser) async {
        guard let core else { return }
        #if DEBUG
        if isDemo { demoStartChat(person); return }
        #endif
        let id = try? await Task.detached(priority: .userInitiated) {
            try core.startDm(userId: person.userId, displayName: person.displayName)
        }.value
        await reload()
        if let id { path.append(id) }
        // A chat you start gives them your delivery key (so they can send you sealed messages).
        Task { await deliverNow() }
    }

    /// Compares a scanned QR code's fingerprint with the key the server holds for `userId`; a match marks
    /// them "Verified in person" (kept on this phone).
    func verifyInPerson(userId: String, fingerprint: String) async throws -> ScanVerdict {
        #if DEBUG
        if isDemo {
            let matches = QRPayload.compact(fingerprint) == ConversationStore.demoGraceFingerprint
            if matches, let index = conversations.firstIndex(where: { $0.id == "dm:\(userId)" }) { conversations[index].verified = true }
            return matches ? .verified : .mismatch
        }
        #endif
        if link == nil, let registrar { await registrar() }
        guard let core, let link else { throw AuthError.network }
        let token = try await link.token()
        let result = try await Task.detached(priority: .userInitiated) {
            try core.verifyInPerson(transport: link.transport, authToken: token, userId: userId, fingerprint: fingerprint)
        }.value
        await reload()
        switch result {
        case .verified: return .verified
        case .mismatch: return .mismatch
        case .keyChanged: return .keyChanged
        }
    }

    /// The code the demo person "Grace" shows (Debug builds only).
    static let demoGraceFingerprint = "1111222233334444AAAA"

    func accept(_ id: Conversation.ID) async {
        #if DEBUG
        if isDemo { demoSetRequest(id, accepted: true); return }
        #endif
        guard let core else { return }
        try? await Task.detached(priority: .userInitiated) { try core.acceptRequest(conversationId: id) }.value
        await reload()
        // Accepting sends them your delivery key, so their later messages can be sealed.
        Task { await deliverNow() }
    }

    /// Blocks the sender: the conversation disappears and its new messages are not kept.
    func block(_ id: Conversation.ID) async {
        #if DEBUG
        if isDemo { demoSetRequest(id, accepted: false); return }
        #endif
        guard let core else { return }
        try? await Task.detached(priority: .userInitiated) { try core.blockSender(conversationId: id) }.value
        await reload()
        // Blocking rotates your delivery key: the server has to learn the new one, and your other contacts get it.
        Task { await deliverNow() }
    }

    // MARK: Search (on this phone only: nothing here touches the network)

    /// Chats whose name or title match, then messages whose text does.
    func search(_ query: String) async -> SearchResults {
        #if DEBUG
        if isDemo { return demoSearch(query) }
        #endif
        guard let core else { return SearchResults() }
        let found = try? await Task.detached(priority: .userInitiated) {
            (try core.searchConversations(query: query), try core.searchMessages(query: query, conversationId: nil, limit: 60))
        }.value
        guard let (chatMatches, hits) = found else { return SearchResults() }
        let byID = Dictionary(uniqueKeysWithValues: conversations.map { ($0.id, $0) })
        return SearchResults(
            chats: chatMatches.compactMap { byID[$0.conversationId] },
            messages: hits.map { hit in
                MessageHit(messageID: hit.messageId, conversationID: hit.conversationId,
                           conversationTitle: byID[hit.conversationId]?.title ?? "", marked: hit.snippet,
                           date: Date(timeIntervalSince1970: Double(hit.time) / 1000), fromMe: hit.fromMe, threadRoot: hit.threadRoot)
            })
    }

    /// The matches inside one chat, oldest first (for "3 of 12" and the up and down arrows).
    func findInChat(_ query: String, in id: Conversation.ID) async -> [MessageHit] {
        #if DEBUG
        if isDemo { return demoSearch(query, only: id).messages }
        #endif
        guard let core else { return [] }
        let title = conversation(id)?.title ?? ""
        // The chat's own timeline and the replies in its threads, in the order they were written.
        let (main, replies) = await Task.detached(priority: .userInitiated) { () -> ([SearchHit], [SearchHit]) in
            ((try? core.searchMessages(query: query, conversationId: id, limit: 500)) ?? [],
             (try? core.searchReplies(query: query, conversationId: id, root: nil, limit: 500)) ?? [])
        }.value
        return (main + replies).sorted { $0.time < $1.time }.map {
            MessageHit(messageID: $0.messageId, conversationID: $0.conversationId, conversationTitle: title, marked: $0.snippet,
                       date: Date(timeIntervalSince1970: Double($0.time) / 1000), fromMe: $0.fromMe, threadRoot: $0.threadRoot)
        }
    }

    /// The matches inside one thread (its root message and its replies), oldest first, for the Replies screen's find.
    func findInThread(_ query: String, root: String, in id: Conversation.ID) async -> [MessageHit] {
        #if DEBUG
        if isDemo {
            let words = SearchText.words(query)
            return (threads[root] ?? []).filter { message in words.allSatisfy { message.text.localizedCaseInsensitiveContains($0) } }.map {
                MessageHit(messageID: $0.id, conversationID: id, conversationTitle: "", marked: $0.text, date: $0.date, fromMe: $0.isOwn, threadRoot: root)
            }
        }
        #endif
        guard let core else { return [] }
        let hits = (try? await Task.detached(priority: .userInitiated) {
            try core.searchReplies(query: query, conversationId: id, root: root, limit: 500)
        }.value) ?? []
        return hits.map {
            MessageHit(messageID: $0.messageId, conversationID: $0.conversationId, conversationTitle: "", marked: $0.snippet,
                       date: Date(timeIntervalSince1970: Double($0.time) / 1000), fromMe: $0.fromMe, threadRoot: $0.threadRoot)
        }
    }

    // MARK: Settings: blocked people and this device's keys

    /// The people you blocked, for Settings.
    func blockedPeople() async -> [BlockedPerson] {
        #if DEBUG
        if isDemo { return demoBlocked }
        #endif
        guard let core else { return [] }
        return (try? await Task.detached(priority: .userInitiated) { try core.listBlocked() }.value) ?? []
    }

    /// Unblocks someone: their conversation, and what was stored before the block, comes back.
    func unblock(_ id: Conversation.ID) async {
        #if DEBUG
        if isDemo {
            demoBlocked.removeAll { $0.conversationId == id }
            return
        }
        #endif
        guard let core else { return }
        try? await Task.detached(priority: .userInitiated) { try core.unblock(conversationId: id) }.value
        await reload()
        Task { await deliverNow() }
    }

    /// How many contacts can be sent to sealed (Debug-only row in About).
    func sealedContactCount() async -> Int {
        #if DEBUG
        if isDemo { return 2 }
        #endif
        guard let core else { return 0 }
        return Int((try? await Task.detached(priority: .userInitiated) { try core.sealedContactCount() }.value) ?? 0)
    }

    /// When this phone's keys were made, and a short fingerprint of the account's key.
    func keyInfo() async -> KeyInfo? {
        #if DEBUG
        if isDemo { return KeyInfo(fingerprint: "A1B2 C3D4 E5F6 0718 293A", createdAt: Int64(Date().addingTimeInterval(-86_400 * 3).timeIntervalSince1970 * 1000)) }
        #endif
        guard let core else { return nil }
        return try? await Task.detached(priority: .userInitiated) { try core.keyInfo() }.value ?? nil
    }

    /// The person accepts the other's new security key; held-back messages are read and queued ones go.
    func trustKey(_ id: Conversation.ID) async {
        #if DEBUG
        if isDemo {
            if let index = conversations.firstIndex(where: { $0.id == id }) { conversations[index].keyChangePending = false }
            return
        }
        #endif
        guard let core else { return }
        try? await Task.detached(priority: .userInitiated) { try core.trustNewKey(conversationId: id) }.value
        await reload()
        await syncNow()
    }

    /// Sends a message again (one that failed, or that was never delivered).
    func resend(_ messageID: String) async {
        #if DEBUG
        if isDemo { demoResend(messageID); return }
        #endif
        guard let core else { return }
        try? await Task.detached(priority: .userInitiated) { try core.retryMessage(messageId: messageID) }.value
        await reload()
        await deliverNow()
    }

    /// The chat is open: its unread count goes to zero.
    func markRead(_ id: Conversation.ID) async {
        // Unread by new messages or by a hand-made mark: opening the chat clears either (a chat marked unread has no number).
        guard let index = conversations.firstIndex(where: { $0.id == id }), conversations[index].isUnread else { return }
        conversations[index].unread = 0
        conversations[index].markedUnread = false
        if let notifications { await notifications.chatOpened(id); await notifications.updateBadge(unreadChats: conversations.filter(\.isUnread).count) }
        #if DEBUG
        if isDemo { return }
        #endif
        guard let core else { return }
        try? await Task.detached(priority: .userInitiated) { try core.markRead(conversationId: id) }.value
        // A reload that started before the store was told may have brought the old state back: say it again, so the row never goes stale.
        if let again = conversations.firstIndex(where: { $0.id == id }), conversations[again].isUnread {
            conversations[again].unread = 0
            conversations[again].markedUnread = false
        }
    }

    #if DEBUG
    /// Debug builds only: the made-up sample chats (a developer row in About, and a test launch argument).
    func loadSampleChats() async {
        guard let core else { return }
        try? await Task.detached(priority: .userInitiated) { try core.seedSampleDataIfEmpty() }.value
        await reload()
    }
    #endif

    /// Signing out: forget everything on this device (the database, its key) and start empty.
    func wipe() {
        core = nil
        link = nil
        problem = nil
        path = NavigationPath()
        databasePath = nil
        conversations = []
        isLoaded = false
        storageError = nil
        showsRecoveryNotice = false
        detector.reset()
        notifications?.settings.reset()
        AvatarCache.shared.reset()
        AttachmentImages.shared.reset()
        StorageBootstrap.wipe(at: storageLocation)
    }

    func reload() async {
        refreshStorageState()
        refreshStatuses()
        #if DEBUG
        if isDemo { return }
        #endif
        guard let core else { return }
        let open = openThreadIDs
        do {
            let loaded = try await Task.detached(priority: .userInitiated) { () -> ([Conversation], [String: [ThreadSummary]], [String: [MessageItem]], [UnreadReplies]) in
                var summaries: [String: [ThreadSummary]] = [:]
                var replies: [UnreadReplies] = []
                let conversations = try core.listConversations().map { summary in
                    let threads = try core.listThreadSummaries(conversationId: summary.id)
                    summaries[summary.id] = threads
                    // Replies live outside the timeline: read the threads with something new, to announce them.
                    for thread in threads where thread.unread > 0 {
                        replies.append(UnreadReplies(conversationID: summary.id, root: thread.rootId, items: (try? core.listThread(rootId: thread.rootId)) ?? []))
                    }
                    return Conversation(summary, messages: try core.listMessages(conversationId: summary.id))
                }
                var threadItems: [String: [MessageItem]] = [:]
                for root in open { threadItems[root] = try? core.listThread(rootId: root) }
                return (conversations, summaries, threadItems, replies)
            }.value
            let me = meProvider()
            conversations = loaded.0.map { conversation in
                var conversation = conversation
                let byRoot = Dictionary(uniqueKeysWithValues: (loaded.1[conversation.id] ?? []).map { ($0.rootId, ThreadInfo($0, me: me)) })
                for index in conversation.messages.indices {
                    conversation.messages[index].thread = byRoot[conversation.messages[index].id]
                }
                return conversation
            }
            for (root, items) in loaded.2 { threads[root] = items.map(Message.init) }
            await announceArrivals(unreadReplies: loaded.3)
        } catch {
            storageError = "Storage could not be read."
        }
        await loadCachedPhotos()
        isLoaded = true
    }

    // MARK: Notifications

    /// A tapped banner or notification: the chat (and the thread in it) opens from Messages.
    func openFromNotification(_ conversationID: String, thread root: String?) {
        guard conversation(conversationID) != nil else { return }
        var fresh = NavigationPath()
        fresh.append(conversationID)
        if let root { fresh.append(ThreadTarget(conversationID: conversationID, rootID: root)) }
        path = fresh
    }

    /// Replies from others in the threads that have something unread (read from the core in `reload`).
    private struct UnreadReplies: Sendable {
        let conversationID: String
        let root: String
        let items: [MessageItem]
    }

    /// Tells the notification coordinator about messages that arrived since the last look, and sets the badge.
    private func announceArrivals(unreadReplies: [UnreadReplies]) async {
        guard let notifications else { return }
        var candidates: [IncomingMessage] = []
        for conversation in conversations {
            func make(_ message: Message, root: String?) -> IncomingMessage? {
                guard let sender = message.senderID, !message.isSystem else { return nil }
                return IncomingMessage(
                    id: message.id, conversationID: conversation.id, conversationTitle: conversation.title, senderID: sender,
                    senderName: person(sender, in: conversation)?.name ?? conversation.title,
                    text: messagePlainText(text: message.text), threadRoot: root, isGroup: conversation.isGroup,
                    isRequest: conversation.isRequest, date: message.date)
            }
            candidates += conversation.messages.compactMap { make($0, root: nil) }
            for thread in unreadReplies where thread.conversationID == conversation.id {
                candidates += thread.items.filter { $0.id != thread.root }.map(Message.init).compactMap { make($0, root: thread.root) }
            }
        }
        let arrivals = detector.arrivals(among: candidates)
        if !arrivals.isEmpty { await notifications.announce(arrivals) }
        await notifications.updateBadge(unreadChats: conversations.filter(\.isUnread).count)
    }

    // MARK: Threads

    /// A thread is on screen: load it, and keep it fresh as replies arrive.
    func openThread(_ root: String) async {
        openThreadIDs.insert(root)
        #if DEBUG
        if isDemo {
            if demoThreads[root] == nil, let message = conversations.flatMap(\.messages).first(where: { $0.id == root }) {
                demoThreads[root] = [message] // a message nobody has replied to yet: its thread is just itself
            }
            threads[root] = demoThreads[root]
            return
        }
        #endif
        guard let core else { return }
        let loaded = try? await Task.detached(priority: .userInitiated) { try core.listThread(rootId: root) }.value
        if let items = loaded { threads[root] = items.map(Message.init) }
    }

    func closeThread(_ root: String) {
        openThreadIDs.remove(root)
        threads[root] = nil
    }

    /// The thread has been looked at: its unread count goes to zero.
    func markThreadRead(_ root: String, in conversationID: Conversation.ID) async {
        if let c = conversations.firstIndex(where: { $0.id == conversationID }),
           let m = conversations[c].messages.firstIndex(where: { $0.id == root }), let info = conversations[c].messages[m].thread, info.unread > 0 {
            conversations[c].messages[m].thread = ThreadInfo(replyCount: info.replyCount, lastReplyAt: info.lastReplyAt, repliers: info.repliers, unread: 0)
            // Those replies were part of the chat's unread number.
            conversations[c].unread = max(conversations[c].unread - info.unread, 0)
        }
        #if DEBUG
        if isDemo { return }
        #endif
        guard let core else { return }
        try? await Task.detached(priority: .userInitiated) { try core.markThreadRead(rootId: root) }.value
    }

    /// Sends a reply in a thread: it shows as "Sending…" in the thread at once, then is delivered.
    func sendReply(_ text: String, root: String, in conversationID: Conversation.ID) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        #if DEBUG
        if isDemo { demoReply(trimmed, root: root, in: conversationID); return }
        #endif
        guard let core, link != nil else { return }
        let queued = try? await Task.detached(priority: .userInitiated) {
            try core.queueReply(conversationId: conversationID, rootId: root, text: trimmed)
        }.value
        guard let item = queued else { return }
        threads[root, default: []].append(Message(item))
        await deliverNow()
    }

    // MARK: Reading

    func conversation(_ id: Conversation.ID) -> Conversation? {
        conversations.first { $0.id == id }
    }

    func person(_ id: String?, in conversation: Conversation) -> Person? {
        guard let id else { return SampleData.me }
        return conversation.members.first { $0.id == id }
    }

    // MARK: Writing

    /// Queues the message in the local store (off the main thread) and shows it as "Sending…"; the
    /// delivery follows and flips it to "Sent". With no backend it is a local-only message.
    func send(_ text: String, in id: Conversation.ID) {
        Task { await sendNow(text, in: id) }
    }

    func sendNow(_ text: String, in id: Conversation.ID) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        #if DEBUG
        if isDemo { demoSend(trimmed, in: id); return }
        #endif
        guard let core else { return }
        let connected = link != nil
        let item = try? await Task.detached(priority: .userInitiated) {
            connected ? try core.queueText(conversationId: id, text: trimmed)
                      : try core.sendLocalMessage(conversationId: id, text: trimmed)
        }.value
        guard let item, let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[index].messages.append(Message(item))
        if connected { await deliverNow() }
    }

    // MARK: About

    /// Whether the on-disk database is encrypted: the store opened with our key, and the same file
    /// refuses a wrong one.
    func storageIsEncrypted() async -> Bool {
        guard core != nil, let path = databasePath else { return false }
        return await Task.detached(priority: .userInitiated) {
            StorageBootstrap.rejectsWrongKey(path: path)
        }.value
    }

    /// A short note at the top of the screen ("Forwarded").
    func showBanner(_ text: String) {
        banner = text
        bannerTask?.cancel()
        bannerTask = Task {
            try? await Task.sleep(for: .seconds(2))
            if !Task.isCancelled { banner = nil }
        }
    }

    /// "Coming next": for the entry points whose screens are the next brief's.
    func comingNext(_ what: String) {
        banner = "\(what): coming next"
        bannerTask?.cancel()
        bannerTask = Task {
            try? await Task.sleep(for: .seconds(2))
            if !Task.isCancelled { banner = nil }
        }
    }

    func comingSoon(_ what: String = "This") {
        banner = "\(what) is coming soon"
        bannerTask?.cancel()
        bannerTask = Task {
            try? await Task.sleep(for: .seconds(2))
            if !Task.isCancelled { banner = nil }
        }
    }

    #if DEBUG
    // MARK: Debug demo (screenshots and UI tests)

    /// Made-up conversations in memory: a request waiting, a chat with a message in each delivery state.
    /// `screen` opens one screen for a screenshot: `requests`, `request-chat`, `chat`, `new-message`, `new-message-found`.
    func loadDemo(screen: String? = nil) {
        isDemo = true
        let now = Date()
        let ada = Person(id: "ada", name: "Ada Lovelace")
        let sam = Person(id: "sam", name: "Sam Park")
        let lee = Person(id: "lee", name: "Lee Wong")
        conversations = [
            Conversation(id: "dm:ada", title: ada.name, members: [ada], messages: [
                Message(id: "d1", senderID: "ada", text: "Hello! Do you have the field trip forms?", date: now.addingTimeInterval(-600)),
            ], unread: 1, isRequest: true),
            Conversation(id: "dm:sam", title: sam.name, members: [sam], messages: [
                Message(id: "s1", senderID: "sam", text: "Are you coming to the staff meeting?", date: now.addingTimeInterval(-3600)),
                Message(id: "s2", senderID: nil, text: "Yes, see you there", date: now.addingTimeInterval(-3000), state: .sent),
                Message(id: "s3", senderID: nil, text: "Bringing the new schedule", date: now.addingTimeInterval(-60), state: .sending),
            ]),
            Conversation(id: "dm:lee", title: lee.name, members: [lee], messages: [
                Message(id: "l1", senderID: "lee", text: "Can we plan the fractions lesson together?", date: now.addingTimeInterval(-90_000)),
                Message(id: "l2", senderID: nil, text: "Yes! I'll draft the lesson outline tonight", date: now.addingTimeInterval(-89_000), state: .sent),
                Message(id: "l3", senderID: "lee", text: "Great. Should the lesson start with a warm-up?", date: now.addingTimeInterval(-88_000)),
                Message(id: "l4", senderID: nil, text: "A short one, five minutes", date: now.addingTimeInterval(-87_000), state: .sent),
                Message(id: "l5", senderID: "lee", text: "Perfect. Lesson plans are due Friday", date: now.addingTimeInterval(-86_000)),
                Message(id: "l6", senderID: nil, text: "I'll send the lesson plan over in the morning", date: now.addingTimeInterval(-85_000), state: .sent),
            ]),
        ]
        isLoaded = true
        refreshStorageState()
        statuses = ["sam": PeerStatus(state: .dnd, until: nil), "lee": PeerStatus(state: .away, until: nil)]
        demoBlocked = [BlockedPerson(conversationId: "dm:pat", name: "Pat Doe", tone: UInt32(AvatarTone.tone(for: "pat")))]
        switch screen {
        case "requests": path.append(MessagesRoute.requests)
        case "request-chat": path.append(MessagesRoute.requests); path.append("dm:ada")
        case "chat": path.append("dm:sam")
        case "key-change":
            conversations[1].keyChangePending = true
            conversations[1].messages[1].state = .undelivered
            path.append("dm:sam")
        case "session-ended": problem = .sessionEnded
        case "search": demoQuery = "lesson"; path.append(MessagesRoute.search)
        case "search-name": demoQuery = "lee"; path.append(MessagesRoute.search)
        case "chat-focus": path.append(ChatTarget(conversationID: "dm:lee", messageID: "l3"))
        case "chat-find": demoQuery = "lesson"; path.append("dm:lee")
        case "thread", "thread-open":
            // A chat with a thread: "3 replies · Last reply", and the thread itself with its replies.
            let rae = Person(id: "rae", name: "Rae Torres")
            let sam = Person(id: "sam", name: "Sam Park"), lee = Person(id: "lee", name: "Lee Wong")
            let me = meProvider()
            let root = Message(id: "t1", senderID: "rae", text: "Who can cover **recess duty** on Thursday?", date: now.addingTimeInterval(-7_200),
                               thread: ThreadInfo(replyCount: 3, lastReplyAt: now.addingTimeInterval(-1_800), repliers: [me, lee, sam], unread: 1))
            demoThreads = ["t1": [
                Message(id: "t1", senderID: "rae", text: "Who can cover **recess duty** on Thursday?", date: now.addingTimeInterval(-7_200)),
                Message(id: "t1a", senderID: "sam", text: "I can take the first half", date: now.addingTimeInterval(-6_000)),
                Message(id: "t1b", senderID: "lee", text: "I'll do the second half", date: now.addingTimeInterval(-3_600)),
                Message(id: "t1c", senderID: nil, text: "Perfect, thank you both!", date: now.addingTimeInterval(-1_800), state: .sent),
            ]]
            conversations = [Conversation(id: "dm:rae", title: rae.name, members: [rae, sam, lee], messages: [
                root,
                Message(id: "t2", senderID: nil, text: "Also, the book fair starts Monday", date: now.addingTimeInterval(-600), state: .sent),
            ])]
            path.append("dm:rae")
            if screen == "thread-open" { path.append(ThreadTarget(conversationID: "dm:rae", rootID: "t1")) }
        case "links":
            // A link and an underline side by side, in each kind of bubble.
            let pat = Person(id: "pat", name: "Pat Rivera")
            conversations = [Conversation(id: "dm:links", title: pat.name, members: [pat], messages: [
                Message(id: "k1", senderID: "pat", text: "A [link to the policy](https://limechat.org/policy) and some __underlined text__ side by side.", date: now.addingTimeInterval(-900)),
                Message(id: "k2", senderID: nil, text: "A [link to the policy](https://limechat.org/policy) and some __underlined text__ side by side.", date: now.addingTimeInterval(-600), state: .sent),
                Message(id: "k3", senderID: "pat", text: "Email [the office](mailto:office@example.com), **bold**, and plain text.", date: now.addingTimeInterval(-300)),
            ])]
            path.append("dm:links")
        case "compose":
            demoCompose = true
            path.append("dm:sam")
        case "format", "format-http":
            // A chat of formatted messages: styles, a list, a code block, a numbered list, links.
            let pat = Person(id: "pat", name: "Pat Rivera")
            conversations = [Conversation(id: "dm:fmt", title: pat.name, members: [pat], messages: [
                Message(id: "f1", senderID: "pat", text: "Here's the plan for **Friday**:\n\n- bring the *signed* forms\n- check `room 12`\n- read [the policy](https://limechat.org/policy)", date: now.addingTimeInterval(-7_200)),
                Message(id: "f2", senderID: nil, text: "Thanks! I'll run this check:\n\n```\nlet total = forms + permission_slips\nprint(\"a long line that scrolls sideways when it does not fit\")\n```\n\n__Almost__ done.", date: now.addingTimeInterval(-3_600), state: .sent),
                Message(id: "f3", senderID: "pat", text: "~~Cancelled~~ and **__rescheduled__**\n\nSee [the old site](http://example.com/old)", date: now.addingTimeInterval(-1_800)),
                Message(id: "f4", senderID: nil, text: "My steps:\n\n1. copy the forms\n2. sign them\n  - **both** sides\n3. hand them in", date: now.addingTimeInterval(-600), state: .sent),
            ])]
            path.append("dm:fmt")
        case "notif-banner": demoNotification = "banner"
        case "group", "group-details", "new-group", "new-group-name":
            loadDemoTeachers()
            let id = demoMakeGroup(name: "Grade 4 Team", emoji: "🍎", memberIDs: ["lee", "sam", "priya.nair"], owner: true)
            demoSheet = screen == "new-group" || screen == "new-group-name" ? screen : nil
            if screen == "group" {
                demoAddMessages(to: id, [("lee", "Can we plan the field trip on Friday?"), ("sam", "I can bring the permission forms")])
                path.append(id)
            }
            if screen == "group-details" { path.append(id); path.append(GroupTarget(conversationID: id)) }
        case "groups-rows":
            // Two groups to swipe: one I own and one I am only a member of (next to the demo's one-to-one chats).
            loadDemoTeachers()
            let mine = demoMakeGroup(name: "Grade 4 Team", emoji: "🍎", memberIDs: ["lee", "sam"], owner: true)
            let theirs = demoMakeGroup(name: "Staff Social", emoji: "🎉", memberIDs: ["lee", "priya.nair"], owner: false)
            demoAddMessages(to: mine, [("lee", "Field trip on Friday?")])
            demoAddMessages(to: theirs, [("lee", "Pizza at noon")])
        case "scan-verified", "scan-mismatch":
            loadDemoTeachers()
            demoSheet = "scan"
            let key = screen == "scan-verified" ? Self.demoGraceFingerprint : "0000111122223333FFFF"
            demoScanCode = "https://limechat.org/u/grace.h?k=\(key)"
        case "attachments", "attachments-draft", "attachments-media", "attachments-remote", "attachment-viewer":
            loadDemoAttachments(draft: screen == "attachments-draft", screen: screen ?? "attachments")
            path.append("dm:att")
        case "chat-verified":
            let grace = Person(id: "grace", name: "Grace Hopper")
            conversations = [Conversation(id: "dm:grace", title: grace.name, members: [grace], messages: [
                Message(id: "v1", senderID: "grace", text: "Great to meet you in person!", date: Date().addingTimeInterval(-300)),
            ], verified: true)]
            path.append("dm:grace")
        case "new-message", "new-message-found", "new-message-filter", "new-message-empty", "find-username", "find-username-found":
            demoSheet = screen
            if screen == "new-message-empty" {
                conversations = []
            } else {
                loadDemoTeachers()
            }
        default:
            // "settings", "settings/profile", "settings/profile/edit-about", "settings/privacy/blocked", ...
            if let screen, screen.hasPrefix("settings/storage") {
                loadDemoAttachments(draft: false)
            }
            if let screen, screen.hasPrefix("settings") {
                demoSheet = "settings"
                demoSettingsRoute = screen.split(separator: "/").dropFirst().map(String.init)
            }
        }
    }

    /// Debug demo: where Settings opens (route names, e.g. ["profile", "edit-about"]).
    private(set) var demoSettingsRoute: [String] = []

    /// Debug demo: the threads (root, then replies) by root id.
    var demoThreads: [String: [Message]] = [:]

    /// Debug demo: open the composer with some text selected, so the formatting toolbar is up (for screenshots).
    private(set) var demoCompose = false

    /// Debug demo: a search or find that is already typed (for screenshots).
    private(set) var demoQuery: String?

    /// Debug demo: a notification to show on arrival ("banner").
    private(set) var demoNotification: String?

    /// Debug demo: a screen that opens as a sheet.
    private(set) var demoSheet: String?
    /// Debug demo: a QR code's text that the scan screen reads as soon as it opens.
    private(set) var demoScanCode: String?
    /// Debug demo: the groups made in the demo (name, emoji, people and roles), by conversation id.
    var demoGroups: [String: DemoGroup] = [:]
    /// Debug demo: people "blocked" for the Settings screens.
    private(set) var demoBlocked: [BlockedPerson] = []

    private func demoSend(_ text: String, in id: Conversation.ID) {
        guard let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        let message = Message(id: UUID().uuidString, senderID: nil, text: text, date: Date(), state: .sending)
        conversations[index].messages.append(message)
        conversations[index].lastReaction = nil
        conversations[index].activityAt = nil
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            if let c = conversations.firstIndex(where: { $0.id == id }),
               let m = conversations[c].messages.firstIndex(where: { $0.id == message.id }) {
                conversations[c].messages[m].state = .sent
            }
        }
    }

    /// The demo's search: the same word matching, over the in-memory conversations.
    private func demoSearch(_ query: String, only id: String? = nil) -> SearchResults {
        var results = SearchResults()
        guard !SearchText.words(query).isEmpty else { return results }
        for conversation in conversations where !conversation.isRequest || id != nil {
            if id == nil && SearchText.matches(([conversation.title] + conversation.members.map(\.name)).joined(separator: " "), query: query) {
                results.chats.append(conversation)
            }
            guard id == nil || id == conversation.id else { continue }
            for message in conversation.messages where SearchText.matches(message.text, query: query) {
                results.messages.append(MessageHit(
                    messageID: message.id, conversationID: conversation.id, conversationTitle: conversation.title,
                    marked: SearchText.mark(message.text, query: query), date: message.date, fromMe: message.isOwn))
            }
        }
        do {
            // Replies in threads are found too (in the chat's own find as well), and open their thread.
            for (root, items) in demoThreads {
                guard let conversation = conversations.first(where: { $0.messages.contains { $0.id == root } }) else { continue }
                if let id, conversation.id != id { continue }
                for reply in items.dropFirst() where SearchText.matches(reply.text, query: query) {
                    results.messages.append(MessageHit(
                        messageID: reply.id, conversationID: conversation.id, conversationTitle: conversation.title,
                        marked: SearchText.mark(reply.text, query: query), date: reply.date, fromMe: reply.isOwn, threadRoot: root))
                }
            }
        }
        results.messages.sort { $0.date < $1.date }
        if id == nil { results.messages.reverse() }
        return results
    }

    private func demoReply(_ text: String, root: String, in conversationID: String) {
        var reply = Message(id: UUID().uuidString, senderID: nil, text: text, date: Date(), state: .sending)
        reply.threadRoot = root
        demoThreads[root, default: []].append(reply)
        threads[root] = demoThreads[root]
        if let c = conversations.firstIndex(where: { $0.id == conversationID }) {
            conversations[c].latest = reply
            conversations[c].latestIsReply = true
        }
        if let c = conversations.firstIndex(where: { $0.id == conversationID }),
           let m = conversations[c].messages.firstIndex(where: { $0.id == root }) {
            let old = conversations[c].messages[m].thread
            let me = meProvider()
            conversations[c].messages[m].thread = ThreadInfo(
                replyCount: (old?.replyCount ?? 0) + 1, lastReplyAt: reply.date,
                repliers: [me] + (old?.repliers ?? []).filter { $0.id != me.id }.prefix(2), unread: old?.unread ?? 0)
        }
        Task {
            try? await Task.sleep(for: .seconds(1))
            if let i = demoThreads[root]?.firstIndex(where: { $0.id == reply.id }) {
                demoThreads[root]?[i].state = .sent
                threads[root] = demoThreads[root]
            }
        }
    }

    private func demoResend(_ messageID: String) {
        for c in conversations.indices {
            guard let m = conversations[c].messages.firstIndex(where: { $0.id == messageID }) else { continue }
            conversations[c].messages[m].state = .sending
            Task {
                try? await Task.sleep(for: .seconds(1))
                conversations[c].messages[m].state = .sent
            }
        }
    }

    private func demoSetRequest(_ id: Conversation.ID, accepted: Bool) {
        guard let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        if accepted {
            conversations[index].isRequest = false
        } else {
            let gone = conversations.remove(at: index)
            demoBlocked.append(BlockedPerson(conversationId: gone.id, name: gone.title, tone: UInt32(gone.members.first?.tone ?? 0)))
        }
    }

    private func demoStartChat(_ person: FoundUser) {
        let id = "dm:\(person.userId)"
        if !conversations.contains(where: { $0.id == id }) {
            let who = Person(id: person.userId, name: person.displayName)
            conversations.insert(Conversation(id: id, title: who.name, members: [who], messages: []), at: 0)
        }
        path.append(id)
    }
    #endif
}
