import SwiftUI

/// The jam tab (coming soon): a calm page, no banner. "Notify me" is kept on this phone only.
struct JamPage: View {
    @AppStorage("lime.jamNotify") private var notify = false
    @Environment(ConversationStore.self) private var store

    var body: some View {
        @Bindable var store = store
        return NavigationStack(path: $store.jamPath) {
            VStack(spacing: 14) {
                Image(systemName: "book.pages").font(.system(size: 80, weight: .regular)).foregroundStyle(Theme.textSecondary)
                    .padding(.bottom, 10).accessibilityHidden(true)
                Text("Jam is coming").font(.title.weight(.bold)).foregroundStyle(Theme.text).multilineTextAlignment(.center)
                    .accessibilityIdentifier("jam-title")
                Text("A space for teachers to share lessons, stories and videos. Teachers learn best by watching teachers teach.")
                    .font(Theme.body).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center).lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("jam-text")
                Button { notify.toggle() } label: {
                    Text(notify ? "We\u{2019}ll let you know \u{2713}" : "Notify me")
                        .font(Theme.title).foregroundStyle(notify ? Theme.text : Theme.accentInk)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(notify ? Theme.surface : Theme.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 14)
                .accessibilityValue(notify ? "On" : "Off")
                .accessibilityIdentifier("jam-notify")
            }
            .padding(.horizontal, 32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.bottom, 60)
            .background(Theme.canvas)
            .navigationBarTitleDisplayMode(.inline)
            .rootHeader(searchID: "jam-search-button") { store.jamSearching = true }
            .navigationDestination(for: ProfileRoute.self) { ProfileView(route: $0) }
            .navigationDestination(for: SharedListRoute.self) { SharedListView(route: $0) }
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
