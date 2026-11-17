import SwiftUI

/// lime on the Mac (Mac Catalyst, "Optimize for Mac"). The same objects `ios/Lime/App/LimeApp.swift` creates, minus the phone-only ones:
/// no mesh/Bluetooth (`MeshService`, `NearbyTest`), no tab bar styling (`TabBadgeStyle`), and no UI-test stand-in backends.
@main
struct MacApp: App {
    @UIApplicationDelegateAdaptor(MacAppDelegate.self) private var appDelegate
    @State private var store: ConversationStore
    @State private var session: AccountSession
    @State private var notifications: NotificationCoordinator
    @State private var nav = MacNavigation()
    @AppStorage(AppearanceSetting.storageKey) private var appearance = AppearanceSetting.system.rawValue

    init() {
        FontRegistrar.registerAll()   // lime's own typefaces, before the first text is drawn
        let store = ConversationStore()
        let config = BackendConfig.current
        let auth: (any AuthService)? = config.map { LiveAuthService(config: $0) }
        let coordinator = Self.makeNotifications()
        store.notifications = coordinator
        coordinator.onOpen = { [weak store] conversation, thread in store?.openFromNotification(conversation, thread: thread) }
        _store = State(initialValue: store)
        _notifications = State(initialValue: coordinator)
        _session = State(initialValue: AccountSession(auth: auth, config: config, store: store))
    }

    var body: some Scene {
        WindowGroup {
            MacRootView()
                .frame(minWidth: 720, minHeight: 480)
                .buttonStyle(.plain)   // iOS's own look: on the Mac idiom a bare Button otherwise gets a grey square behind lime's capsules
                .menuIndicator(.hidden)   // Catalyst draws a chevron on every Menu button by itself; Apple Messages shows none (an environment value, so every Menu below inherits it)
                .limeTextSize()
                .onAppear { WindowTextSize.start(); AppIconChoice.migrateIfNeeded(); Self.limitWindowSize() }
                .environment(store)
                .environment(session)
                .environment(notifications)
                .environment(nav)
                .preferredColorScheme(ThemeStore.shared.background.forcesDark ? .dark : AppearanceSetting(rawValue: appearance)?.colorScheme)
                .task {
                    await session.resume()
                    #if DEBUG
                    await MacTestAccount.replaceSessionIfHandedOver(session: session)
                    #endif
                }
        }
        .defaultSize(width: 1000, height: 700)
        .commands { MacCommands(nav: nav, store: store) }
    }

    /// The window never gets smaller than 720 x 480 (both panes stay usable).
    private static func limitWindowSize() {
        for scene in UIApplication.shared.connectedScenes {
            (scene as? UIWindowScene)?.sizeRestrictions?.minimumSize = CGSize(width: 720, height: 480)
        }
    }

    /// The real notification centre (the Mac has no UI-test stand-in here).
    private static func makeNotifications() -> NotificationCoordinator {
        let system = SystemNotifications()
        let feedback = SystemArrivalFeedback()
        let coordinator = NotificationCoordinator(center: system, feedback: feedback)
        system.soundFile = { [weak coordinator] in coordinator?.settings.sound.fileName }
        feedback.soundURL = { [weak coordinator] in
            switch coordinator?.settings.sound {
            case .limeChime: Bundle.main.url(forResource: "lime-chime", withExtension: "caf")
            case .custom(let id): CustomSounds.shared.fileURL(id)
            default: nil
            }
        }
        coordinator.isQuiet = { now in MainActor.assumeIsolated { StatusSettings.shared.plan(now: now).isQuiet } }
        system.onTap = { [weak coordinator] conversation, thread in coordinator?.open(conversationID: conversation, threadRoot: thread) }
        return coordinator
    }
}

/// Which chat the Mac window shows, and the sidebar's visibility (the menu bar changes both).
@MainActor
@Observable
final class MacNavigation {
    /// A chat's id, or `requestsID` for the Requests list.
    var selection: String?
    var columns: NavigationSplitViewVisibility = .all
    static let requestsID = "lime.requests"
}

/// The Mac menu bar (SwiftUI `.commands`). lime: the system's About, Hide, Quit (no Settings yet). File: Close Window. Edit and Window: the system's.
/// View: Show/Hide Sidebar. Chat: Next and Previous Chat. Help: the system's, no items yet.
struct MacCommands: Commands {
    let nav: MacNavigation
    let store: ConversationStore

    var body: some Commands {
        // Nothing to create yet: no File > New.
        CommandGroup(replacing: .newItem) {}
        CommandGroup(replacing: .sidebar) {
            Button(nav.columns == .detailOnly ? "Show Sidebar" : "Hide Sidebar") {
                nav.columns = nav.columns == .detailOnly ? .all : .detailOnly
            }
            .keyboardShortcut("s", modifiers: [.control, .command])
        }
        CommandMenu("Chat") {
            Button("Next Chat") { move(by: 1) }.keyboardShortcut("]", modifiers: .command)
            Button("Previous Chat") { move(by: -1) }.keyboardShortcut("[", modifiers: .command)
        }
    }

    private func move(by step: Int) {
        let ids = store.chats.map(\.id)
        guard !ids.isEmpty else { return }
        let at = nav.selection.flatMap { ids.firstIndex(of: $0) }
        nav.selection = ids[min(max((at ?? (step > 0 ? -1 : ids.count)) + step, 0), ids.count - 1)]
    }
}
