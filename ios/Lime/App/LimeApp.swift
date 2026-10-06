import SwiftUI

@main
struct LimeApp: App {
    @State private var store = ConversationStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .task {
                    // `-lime-reset-store` starts from a fresh sample database (used by UI tests).
                    await store.bootstrap(resetStore: ProcessInfo.processInfo.arguments.contains("-lime-reset-store"))
                }
        }
    }
}
