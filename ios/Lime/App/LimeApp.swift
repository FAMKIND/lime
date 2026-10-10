import SwiftUI

@main
struct LimeApp: App {
    @State private var store: ConversationStore
    @State private var session: AccountSession
    @State private var notifications: NotificationCoordinator
    @AppStorage(AppearanceSetting.storageKey) private var appearance = AppearanceSetting.system.rawValue

    init() {
        let store = ConversationStore()
        let config = BackendConfig.current
        var auth: (any AuthService)? = config.map { LiveAuthService(config: $0) }
        #if DEBUG
        // UI tests and screenshots: a stand-in backend with no network.
        if ProcessInfo.processInfo.arguments.contains("-lime-fake-auth") || ProcessInfo.processInfo.arguments.contains("-lime-skip-sign-in") {
            auth = FakeAuthService()
        }
        #endif
        let coordinator = Self.makeNotifications()
        store.notifications = coordinator
        coordinator.onOpen = { [weak store] conversation, thread in store?.openFromNotification(conversation, thread: thread) }
        #if DEBUG
        NearbyTest.resumeIfNeeded() // iOS may relaunch the app for Bluetooth (LIME-103 field test)
        #endif
        _store = State(initialValue: store)
        _notifications = State(initialValue: coordinator)
        _session = State(initialValue: AccountSession(auth: auth, config: config, store: store))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(session)
                .environment(notifications)
                .preferredColorScheme(AppearanceSetting(rawValue: appearance)?.colorScheme)
                .task { await session.resume() }
        }
    }

    /// The real notification centre, or (UI tests and screenshots) a stand-in with no system prompts.
    private static func makeNotifications() -> NotificationCoordinator {
        let arguments = ProcessInfo.processInfo.arguments
        #if DEBUG
        if arguments.contains("-lime-skip-sign-in") || arguments.contains("-lime-fake-auth") {
            // Allowed unless a test asks otherwise (so the explainer never covers an unrelated test).
            let status: NotificationAuthorization = arguments.contains("-lime-notif-denied") ? .denied
                : arguments.contains("-lime-notif-undetermined") ? .notDetermined : .authorized
            let demo = DemoNotifications(status: status)
            // A throwaway suite, so a test never reads or leaves a real phone's choices.
            let suite = UserDefaults(suiteName: "lime.demo.notifications") ?? .standard
            if arguments.contains("-lime-reset-session") { suite.removePersistentDomain(forName: "lime.demo.notifications") }
            return NotificationCoordinator(settings: NotificationSettings(defaults: suite), center: demo, feedback: demo)
        }
        #endif
        let system = SystemNotifications()
        let feedback = SystemArrivalFeedback()
        let coordinator = NotificationCoordinator(center: system, feedback: feedback)
        // The chosen message sound: the bundled chime, one of the person's own files, or the system's.
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
