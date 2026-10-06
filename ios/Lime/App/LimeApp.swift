import SwiftUI

@main
struct LimeApp: App {
    @State private var store = ConversationStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .task {
                    // Debug builds honour `-lime-reset-store` and the key test hooks (UI tests).
                    await store.bootstrap()
                }
        }
    }
}
