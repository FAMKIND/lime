import SwiftUI

@main
struct LimeApp: App {
    @State private var store = ConversationStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
        }
    }
}
