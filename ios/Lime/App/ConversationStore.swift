import SwiftUI

/// What the signed-in phone talks to: LimeCore's network and a fresh access token for each call.
struct BackendLink: Sendable {
    let transport: Transport
    let token: @Sendable () async throws -> String
}

/// Where the navigation stack can be sent besides a chat.
enum MessagesRoute: Hashable { case requests }

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
    private var isSyncing = false
    private var syncAgain = false
    /// Set when the last send or sync could not reach the server.
    private(set) var isOffline = false
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
    }

    var isConnected: Bool { link != nil }

    /// Delivers what is waiting to be sent, then fetches the mailbox and refreshes the list. Calls
    /// that arrive while one is running are folded into one more round afterwards.
    func syncNow() async {
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
                isOffline = false
            } catch {
                isOffline = true
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
            isOffline = false
        } catch {
            isOffline = true
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
                : FoundUser(userId: "grace", displayName: "Grace Hopper", username: "grace.h", school: "Naval Academy", isSelf: false)
        }
        #endif
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
        do {
            conversations = try await Task.detached(priority: .userInitiated) {
                try core.listConversations().map { summary in
                    Conversation(summary, messages: try core.listMessages(conversationId: summary.id))
                }
            }.value
        } catch {
            storageError = "Storage could not be read."
        }
        isLoaded = true
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
        let ada = Person(id: "ada", name: "Ada Lovelace", tone: 2)
        let sam = Person(id: "sam", name: "Sam Park", tone: 5)
        conversations = [
            Conversation(id: "dm:ada", title: ada.name, members: [ada], messages: [
                Message(id: "d1", senderID: "ada", text: "Hello! Do you have the field trip forms?", date: now.addingTimeInterval(-600)),
            ], unread: 1, isRequest: true),
            Conversation(id: "dm:sam", title: sam.name, members: [sam], messages: [
                Message(id: "s1", senderID: "sam", text: "Are you coming to the staff meeting?", date: now.addingTimeInterval(-3600)),
                Message(id: "s2", senderID: nil, text: "Yes, see you there", date: now.addingTimeInterval(-3000), state: .sent),
                Message(id: "s3", senderID: nil, text: "Bringing the new schedule", date: now.addingTimeInterval(-60), state: .sending),
            ]),
        ]
        isLoaded = true
        switch screen {
        case "requests": path.append(MessagesRoute.requests)
        case "request-chat": path.append(MessagesRoute.requests); path.append("dm:ada")
        case "chat": path.append("dm:sam")
        case "new-message", "new-message-found": demoSheet = screen
        default: break
        }
    }

    /// Debug demo: a screen that opens as a sheet.
    private(set) var demoSheet: String?

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

    private func demoSetRequest(_ id: Conversation.ID, accepted: Bool) {
        guard let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        if accepted { conversations[index].isRequest = false } else { conversations.remove(at: index) }
    }

    private func demoStartChat(_ person: FoundUser) {
        let id = "dm:\(person.userId)"
        if !conversations.contains(where: { $0.id == id }) {
            let who = Person(id: person.userId, name: person.displayName, tone: 3)
            conversations.insert(Conversation(id: id, title: who.name, members: [who], messages: []), at: 0)
        }
        path.append(id)
    }
    #endif
}
