import SwiftUI

@main
struct LimeApp: App {
    @State private var store: ConversationStore
    @State private var session: AccountSession
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
        _store = State(initialValue: store)
        _session = State(initialValue: AccountSession(auth: auth, config: config, store: store))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(session)
                .preferredColorScheme(AppearanceSetting(rawValue: appearance)?.colorScheme)
                .task { await session.resume() }
        }
    }
}
