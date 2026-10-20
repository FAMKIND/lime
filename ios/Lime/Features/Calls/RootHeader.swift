import SwiftUI

/// The header every tab's root shares (LIME-121d): the lime logo on the left; search and your avatar on the right; nothing else.
/// Messages draws the same header itself (its list needs the veil and margins); Calls and jam use this.
struct RootHeader: ViewModifier {
    @Environment(ConversationStore.self) private var store
    @Environment(AccountSession.self) private var session
    let searchID: String
    /// Draw the header over the content (which then scrolls under it, with the same veil as Messages) instead of reserving room for it.
    var overlays = false
    let search: () -> Void
    @State private var showStatus = false
    @State private var showSettings = false
    @State private var settingsAfterStatus = false
    #if DEBUG
    @State private var showAbout = false
    #endif

    func body(content: Content) -> some View {
        Group {
            if #available(iOS 26, *) {
                content
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button { store.comingSoon() } label: {
                                Image("LimeLogo").renderingMode(.original).resizable().scaledToFit()
                                    .frame(width: 30, height: 30).contentShape(Rectangle())
                                    #if DEBUG
                                    .onLongPressGesture(minimumDuration: 0.6) { showAbout = true }
                                    #endif
                            }
                            .accessibilityLabel("Lime menu")
                        }
                        ToolbarItemGroup(placement: .topBarTrailing) {
                            Button(action: search) { Image(systemName: "magnifyingglass") }
                                .accessibilityLabel("Search")
                                .accessibilityIdentifier(searchID)
                            Button { store.openMyProfile() } label: { AvatarView(person: session.mePerson, size: 30, showsStatus: true, badgeKeepsColours: true) }
                                .accessibilityLabel("Settings")
                                .accessibilityIdentifier("settings-button")
                        }
                    }
            } else {
                let controls = TopControls(onAbout: {
                    #if DEBUG
                    showAbout = true
                    #endif
                }, onSearch: search, onSettings: { store.openMyProfile() }, searchID: searchID)
                if overlays {
                    content
                        .overlay(alignment: .top) { TopFade() }
                        .overlay(alignment: .top) { controls }
                        .toolbar(.hidden, for: .navigationBar)
                } else {
                    content
                        .safeAreaInset(edge: .top, spacing: 0) { controls }
                        .toolbar(.hidden, for: .navigationBar)
                }
            }
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showStatus, onDismiss: { if settingsAfterStatus { settingsAfterStatus = false; showSettings = true } }) {
            StatusSheet(openSettings: { settingsAfterStatus = true })
        }
        #if DEBUG
        .sheet(isPresented: $showAbout) { AboutView() }
        #endif
    }
}

extension View {
    /// The shared root header (logo left; search and avatar right) for a tab other than Messages.
    func rootHeader(searchID: String, overlays: Bool = false, search: @escaping () -> Void) -> some View { modifier(RootHeader(searchID: searchID, overlays: overlays, search: search)) }
}
