import SwiftUI

@main
struct LimeApp: App {
    @State private var store: ConversationStore
    @State private var session: AccountSession
    @State private var notifications: NotificationCoordinator
    @AppStorage(AppearanceSetting.storageKey) private var appearance = AppearanceSetting.system.rawValue

    init() {
        FontRegistrar.registerAll()   // lime's own typefaces (LIME-168), before the first text is drawn
        let store = ConversationStore()
        let config = BackendConfig.current
        var auth: (any AuthService)? = config.map { LiveAuthService(config: $0) }
        #if DEBUG
        // UI tests and screenshots: a stand-in backend with no network.
        if ProcessInfo.processInfo.arguments.contains("-lime-fake-auth") || ProcessInfo.processInfo.arguments.contains("-lime-skip-sign-in") {
            auth = FakeAuthService()
        }
        #endif
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-lime-fake-lock-auth") { AppLock.shared.authenticator = FakeLockAuthenticator(); AppLock.shared.asksOnReturn = false }
        #endif
        let coordinator = Self.makeNotifications()
        store.notifications = coordinator
        coordinator.onOpen = { [weak store] conversation, thread in store?.openFromNotification(conversation, thread: thread) }
        #if DEBUG
        NearbyTest.resumeIfNeeded() // iOS may relaunch the app for Bluetooth (LIME-103 field test)
        MeshService.shared.bootstrap(store: store) // the mesh runs by itself (LIME-141, 142)
        #endif
        TabBadgeStyle.install()
        _store = State(initialValue: store)
        _notifications = State(initialValue: coordinator)
        _session = State(initialValue: AccountSession(auth: auth, config: config, store: store))
    }

    #if DEBUG
    private static var demoWindowWidth: CGFloat? {
        let args = ProcessInfo.processInfo.arguments
        return args.firstIndex(of: "-lime-demo-window-width").flatMap { args.indices.contains($0 + 1) ? Double(args[$0 + 1]) : nil }.map { CGFloat($0) }
    }
    #endif

    var body: some Scene {
        WindowGroup {
            RootView()
                #if DEBUG
                .overlay { if AXProbe.enabled { AXProbeOverlay() } }
                #endif
                #if DEBUG
                // `-lime-demo-window-width <pt>` lays lime out in a window that wide (a narrow Stage Manager window), for screenshots.
                .frame(width: Self.demoWindowWidth)
                #endif
                .onGeometryChange(for: CGSize.self) { $0.size } action: { WindowMetrics.shared.size = $0 }
                .limeTextSize()
                .onAppear { WindowTextSize.start(); AppIconChoice.migrateIfNeeded() }
                .environment(store)
                .environment(session)
                .environment(notifications)
                .preferredColorScheme(ThemeStore.shared.background.forcesDark ? .dark : AppearanceSetting(rawValue: appearance)?.colorScheme)
                // The window itself too (LIME-277g): sheets, navigation titles, menus, alerts and the keyboard are drawn by the system and follow the window, so on
                // Chalkboard they read light on dark.
                .onChange(of: "\(ThemeStore.shared.background.forcesDark)|\(appearance)", initial: true) {
                    WindowStyle.apply(ThemeStore.shared.background.forcesDark ? .dark : (AppearanceSetting(rawValue: appearance)?.colorScheme == .dark ? .dark : AppearanceSetting(rawValue: appearance)?.colorScheme == .light ? .light : .unspecified))
                }
                .task { await session.resume() }
                #if DEBUG
                // LIME-111-fix4: `-lime-callkit-selftest` runs the CallKit self-test at launch (log in the call diagnostics).
                .task {
                    let arguments = ProcessInfo.processInfo.arguments
                    if let at = arguments.firstIndex(of: "-lime-start-tab"), at + 1 < arguments.count, let tab = ConversationStore.Section(rawValue: arguments[at + 1]) {
                        store.section = tab
                    }
                    if arguments.contains("-lime-skip-sign-in") {
                        // The call history lives in the (persistent) test store: start every UI-test launch from a known list.
                        var waited = 0
                        while !store.isLoaded && waited < 100 { try? await Task.sleep(for: .milliseconds(100)); waited += 1 }
                        CallLog.shared.clear()
                        if arguments.contains("-lime-demo-calls") { CallLog.shared.seedDemo(many: arguments.contains("-lime-demo-calls-many")) }
                    }
                    if let at = arguments.firstIndex(of: "-lime-demo-call"), at + 1 < arguments.count {
                        try? await Task.sleep(for: .seconds(1))
                        let kind = arguments[at + 1]
                        if kind.hasPrefix("incoming") {
                            store.calls.demoIncoming(video: kind.contains("video"), systemRings: !kind.contains("ios-refused"))
                        } else {
                        store.calls.demo(video: kind == "video", remoteMuted: arguments.contains("-lime-demo-call-remote-muted"), remoteCameraOff: arguments.contains("-lime-demo-call-remote-camera-off"))
                        }
                    }
                    if ProcessInfo.processInfo.arguments.contains("-lime-callkit-selftest") {
                        try? await Task.sleep(for: .seconds(2))
                        await (store.calls.system as? CallKitSystem)?.selfTest()
                    }
                }
                #endif
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
