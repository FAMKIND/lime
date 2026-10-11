import SwiftUI

/// The jam tab (coming soon): a calm page, no banner. "Notify me" is kept on this phone only.
struct JamPage: View {
    @AppStorage("lime.jamNotify") private var notify = false
    @Environment(ConversationStore.self) private var store

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Image(systemName: "book").font(.system(size: 44)).foregroundStyle(Theme.textSecondary).accessibilityHidden(true)
                    Text("A place for teachers to share what works: posts, articles and recordings, by teachers, for teachers. Coming soon.")
                        .font(Theme.body).foregroundStyle(Theme.text)
                        .accessibilityIdentifier("jam-text")
                    Toggle(isOn: $notify) {
                        Text("Notify me").font(Theme.body).foregroundStyle(Theme.text)
                    }
                    .tint(Theme.accent)
                    .accessibilityIdentifier("jam-notify")
                }
                .padding(24)
            }
            .background(Theme.canvas)
            .navigationBarTitleDisplayMode(.inline)
            .rootHeader(searchID: "jam-search-button") { store.jamSearching = true }
            .navigationDestination(isPresented: Binding(get: { store.jamSearching }, set: { store.jamSearching = $0 })) {
                Text("Nothing to search in jam yet.")
                    .font(Theme.body).foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.canvas)
                    .accessibilityIdentifier("jam-search-empty")
            }
        }
    }
}
