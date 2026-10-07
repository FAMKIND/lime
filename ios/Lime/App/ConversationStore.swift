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
    var banner: String?
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
    private var link: BackendLink?
    /// How the signed-in person is shown (set by the account session): core calls them "me".
    var meProvider: @MainActor () -> Person = { SampleData.me }
    /// The threads that are open on screen: the root message, then its replies. Kept fresh by `reload()`.
    private(set) var threads: [String: [Message]] = [:]
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
    #endif

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
        return try await Task.detached(priority: .userInitiated) {
            try core.registerDevice(transport: transport, authToken: token)
        }.value
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
            syncAgain = false
            do {
                let token = try await link.token()
                // Sends first (they keep their order); a failure leaves them "Not sent" for a retry.
                _ = try? await Task.detached(priority: .userInitiated) {
                    try core.deliverQueued(transport: link.transport, authToken: token)
                }.value
                _ = try await Task.detached(priority: .userInitiated) {
                    try core.sync(transport: link.transport, authToken: token)
                }.value
                problem = nil
            } catch {
                problem = ConnectionProblem.from(error)
            }
            await reload()
        } while syncAgain
    }

    /// Sends what is queued (a message that failed is retried here).
    func deliverNow() async {
        guard let core, let link else { return }
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
    }

    func accept(_ id: Conversation.ID) async {
        #if DEBUG
        if isDemo { demoSetRequest(id, accepted: true); return }
        #endif
        guard let core else { return }
        try? await Task.detached(priority: .userInitiated) { try core.acceptRequest(conversationId: id) }.value
        await reload()
    }

    /// Blocks the sender: the conversation disappears and its new messages are not kept.
    func block(_ id: Conversation.ID) async {
        #if DEBUG
        if isDemo { demoSetRequest(id, accepted: false); return }
        #endif
        guard let core else { return }
        try? await Task.detached(priority: .userInitiated) { try core.blockSender(conversationId: id) }.value
        await reload()
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
        let hits = (try? await Task.detached(priority: .userInitiated) {
            try core.searchMessages(query: query, conversationId: id, limit: 500)
        }.value) ?? []
        return hits.map {
            MessageHit(messageID: $0.messageId, conversationID: $0.conversationId, conversationTitle: title, marked: $0.snippet,
                       date: Date(timeIntervalSince1970: Double($0.time) / 1000), fromMe: $0.fromMe)
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
        guard let index = conversations.firstIndex(where: { $0.id == id }), conversations[index].unread > 0 else { return }
        conversations[index].unread = 0
        #if DEBUG
        if isDemo { return }
        #endif
        guard let core else { return }
        try? await Task.detached(priority: .userInitiated) { try core.markRead(conversationId: id) }.value
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
        StorageBootstrap.wipe(at: storageLocation)
    }

    func reload() async {
        #if DEBUG
        if isDemo { return }
        #endif
        guard let core else { return }
        let open = openThreadIDs
        do {
            let loaded = try await Task.detached(priority: .userInitiated) { () -> ([Conversation], [String: [ThreadSummary]], [String: [MessageItem]]) in
                var summaries: [String: [ThreadSummary]] = [:]
                let conversations = try core.listConversations().map { summary in
                    summaries[summary.id] = try core.listThreadSummaries(conversationId: summary.id)
                    return Conversation(summary, messages: try core.listMessages(conversationId: summary.id))
                }
                var threadItems: [String: [MessageItem]] = [:]
                for root in open { threadItems[root] = try? core.listThread(rootId: root) }
                return (conversations, summaries, threadItems)
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
        } catch {
            storageError = "Storage could not be read."
        }
        isLoaded = true
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
        case "new-message", "new-message-found", "new-message-filter", "new-message-empty", "find-username", "find-username-found":
            demoSheet = screen
            if screen == "new-message-empty" {
                conversations = []
            } else {
                // A longer list of teachers, so the A–Z sections and the rail have something to show.
                for name in ["Ben Okafor", "Chloe Diaz", "Maya Singh", "Noah Bell", "Priya Nair", "Zoe Adler", "Éloïse Martin", "Lena Ito"] {
                    let who = Person(id: name.lowercased().replacingOccurrences(of: " ", with: "."), name: name)
                    conversations.append(Conversation(id: "dm:\(who.id)", title: name, members: [who], messages: []))
                }
            }
        default:
            // "settings", "settings/profile", "settings/profile/edit-about", "settings/privacy/blocked", ...
            if let screen, screen.hasPrefix("settings") {
                demoSheet = "settings"
                demoSettingsRoute = screen.split(separator: "/").dropFirst().map(String.init)
            }
        }
    }

    /// Debug demo: where Settings opens (route names, e.g. ["profile", "edit-about"]).
    private(set) var demoSettingsRoute: [String] = []

    /// Debug demo: the threads (root, then replies) by root id.
    private(set) var demoThreads: [String: [Message]] = [:]

    /// Debug demo: open the composer with some text selected, so the formatting toolbar is up (for screenshots).
    private(set) var demoCompose = false

    /// Debug demo: a search or find that is already typed (for screenshots).
    private(set) var demoQuery: String?

    /// Debug demo: a screen that opens as a sheet.
    private(set) var demoSheet: String?
    /// Debug demo: people "blocked" for the Settings screens.
    private(set) var demoBlocked: [BlockedPerson] = []

    private func demoSend(_ text: String, in id: Conversation.ID) {
        guard let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        let message = Message(id: UUID().uuidString, senderID: nil, text: text, date: Date(), state: .sending)
        conversations[index].messages.append(message)
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
        if id == nil {
            // Replies in threads are found too, and open their thread.
            for (root, items) in demoThreads {
                guard let conversation = conversations.first(where: { $0.messages.contains { $0.id == root } }) else { continue }
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
        let reply = Message(id: UUID().uuidString, senderID: nil, text: text, date: Date(), state: .sending)
        demoThreads[root, default: []].append(reply)
        threads[root] = demoThreads[root]
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
        if accepted { conversations[index].isRequest = false } else { conversations.remove(at: index) }
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
