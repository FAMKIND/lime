import SwiftUI

struct RootView: View {
    @Environment(ConversationStore.self) private var store
    @Environment(AccountSession.self) private var session

    var body: some View {
        Group {
            switch session.phase {
            case .launching:
                SplashView()
            case .signedOut:
                SignedOutView()
                    .id(session.onboardingGeneration)
            case .signedIn:
                SignedInView()
            }
        }
        .alert("Call", isPresented: Binding(get: { store.calls.notice != nil }, set: { if !$0 { store.calls.notice = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(store.calls.notice ?? "") }
        .overlay(alignment: .top) { ComingSoonBanner() }
        .overlay(alignment: .top) { IncomingBannerView() }
        .overlay(alignment: .top) { GroupIncomingBanner() }
        .sheet(isPresented: Binding(get: { store.groupCalls.invite != nil && !store.groupCalls.inCall }, set: { if !$0 { store.groupCalls.dismissInvite() } })) { GroupInviteSheet() }
        .alert("Group call", isPresented: Binding(get: { store.groupCalls.notice != nil }, set: { if !$0 { store.groupCalls.notice = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(store.groupCalls.notice ?? "") }
        .fullScreenCover(isPresented: Binding(get: { store.groupCalls.inCall && !store.groupCalls.minimized }, set: { _ in })) { GroupCallView() }
        .fullScreenCover(isPresented: Binding(get: { store.calls.inCall && !store.calls.minimized }, set: { _ in })) { CallView() }
    }
}

/// Messages and the screens pushed from it. Leaving the app stops the nudge listener (there is no
/// push yet); coming back listens again and catches up.
private struct SignedInView: View {
    @Environment(ConversationStore.self) private var store
    @Environment(AccountSession.self) private var session
    @Environment(NotificationCoordinator.self) private var notifications
    @Environment(\.scenePhase) private var scenePhase
    @State private var explaining = false

    var body: some View {
        @Bindable var store = store
        TabView(selection: Binding(get: { store.section }, set: { store.select($0) })) {
            linkTab(path: $store.path)
                .tabItem { tabLabel("link", TabSymbols.link) }
                .badge(store.chats.filter(\.isUnread).count)
                .tag(ConversationStore.Section.link)
            callTab(path: $store.callPath)
                .tabItem { tabLabel("call", TabSymbols.call) }
                .badge(store.missedCalls)
                .tag(ConversationStore.Section.call)
            JamPage().callMiniPlayerInset()
                .tabItem { tabLabel("jam", TabSymbols.jam) }
                .tag(ConversationStore.Section.jam)
        }
        .tint(Theme.text)
        .modifier(TabBarMinimize())
        .background(TabRetapObserver { index in
            let sections = ConversationStore.Section.allCases
            if index < sections.count, sections[index] == store.section { store.select(sections[index]) }
        })
        .sheet(isPresented: $explaining) { NotificationExplainerSheet() }
        .onAppear {
            // Minimising a group call opens that group's chat (unless it is already open), so the person can type while talking.
            let store = store, notifications = notifications
            store.groupCalls.isViewingChat = { notifications.viewing?.conversationID == $0 }
            store.groupCalls.onMinimize = { conversationID in
                guard notifications.viewing?.conversationID != conversationID else { return }
                store.select(.link)
                var path = NavigationPath()
                path.append(conversationID)
                store.path = path
            }
        }
        .task {
            // Once, after signing in: why Lime would like to notify, before the system's prompt.
            await notifications.refreshAuthorization()
            if notifications.shouldExplain { explaining = true }
        }
        .onChange(of: scenePhase) { _, phase in
            notifications.isActive = phase == .active
            Task {
                switch phase {
                case .active:
                    store.refreshStorageState()
                    await store.statusSettingsChanged()
                    await notifications.releaseHeld()
                    await notifications.refreshAuthorization()
                    await session.appBecameActive()
                case .background: await session.appLeftForeground()
                default: break
                }
            }
        }
    }

    /// A tab's label: always the outlined symbol (the selection shows through the system's tint and highlight, never a filled glyph);
    /// symbol variants are switched off so the system does not fill the selected one.
    private func tabLabel(_ title: String, _ symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .environment(\.symbolVariants, .none)
    }

    private func linkTab(path: Binding<NavigationPath>) -> some View {
        NavigationStack(path: path) {
            MessagesView().callMiniPlayerInset()
                .navigationDestination(for: Conversation.ID.self) { id in
                    ChatView(conversationID: id).toolbar(.hidden, for: .tabBar)
                }
                .navigationDestination(for: GroupTarget.self) { target in
                    GroupDetailsView(target: target).callMiniPlayerInset().toolbar(.hidden, for: .tabBar)
                }
                .navigationDestination(for: ThreadTarget.self) { target in
                    ThreadView(target: target).toolbar(.hidden, for: .tabBar)
                }
                .navigationDestination(for: ChatTarget.self) { target in
                    ChatView(conversationID: target.conversationID, focusMessageID: target.messageID, focusWords: target.words)
                        .toolbar(.hidden, for: .tabBar)
                }
                .navigationDestination(for: ProfileRoute.self) { ProfileView(route: $0).callMiniPlayerInset() }
                .navigationDestination(for: OrgRoute.self) { OrgProfileView(route: $0).callMiniPlayerInset() }
                .navigationDestination(for: SharedListRoute.self) { SharedListView(route: $0).callMiniPlayerInset() }
                .navigationDestination(for: MessagesRoute.self) { route in
                    switch route {
                    case .requests: RequestsView().callMiniPlayerInset()
                    case .search: MessageSearchScreen().callMiniPlayerInset()
                    }
                }
        }
    }

    private func callTab(path: Binding<NavigationPath>) -> some View {
        NavigationStack(path: path) {
            CallHistoryView().callMiniPlayerInset()
                .navigationDestination(for: CallSearchRoute.self) { _ in MessageSearchScreen(callsFirst: true).callMiniPlayerInset() }
                .navigationDestination(for: Conversation.ID.self) { id in ChatView(conversationID: id).toolbar(.hidden, for: .tabBar) }
                .navigationDestination(for: ChatTarget.self) { target in
                    ChatView(conversationID: target.conversationID, focusMessageID: target.messageID, focusWords: target.words).toolbar(.hidden, for: .tabBar)
                }
                .navigationDestination(for: ThreadTarget.self) { target in ThreadView(target: target).toolbar(.hidden, for: .tabBar) }
                .navigationDestination(for: GroupTarget.self) { target in
                    GroupDetailsView(target: target).callMiniPlayerInset().toolbar(.hidden, for: .tabBar)
                }
                .navigationDestination(for: ProfileRoute.self) { ProfileView(route: $0).callMiniPlayerInset() }
                .navigationDestination(for: OrgRoute.self) { OrgProfileView(route: $0).callMiniPlayerInset() }
                .navigationDestination(for: SharedListRoute.self) { SharedListView(route: $0).callMiniPlayerInset() }
        }
    }
}


/// The tab symbols: the outline ones, in every state.
enum TabSymbols {
    static let link = "message"
    static let call = "phone"
    static let jam = "book.pages"
    static let all = [link, call, jam]
}

/// iOS 26: the tab bar stays open while a list scrolls (it never shrinks). Earlier systems have the standard bar.
private struct TabBarMinimize: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) { content.tabBarMinimizeBehavior(.never) } else { content }
    }
}

/// The onboarding flow for a phone with no account on it yet.
private struct SignedOutView: View {
    @Environment(AccountSession.self) private var session
    @State private var model: OnboardingModel?

    var body: some View {
        Group {
            if let model {
                OnboardingFlow(model: model)
            } else {
                SplashView()
            }
        }
        .task {
            guard model == nil else { return }
            let account = session
            let auth: any AuthService = account.auth ?? NoBackendAuthService()
            let created = OnboardingModel(auth: auth) { tokens, profile in
                await account.completeSignIn(tokens: tokens, profile: profile)
            }
            #if DEBUG
            DebugOnboarding.apply(to: created)
            #endif
            model = created
        }
    }
}

/// Used when the app was built without a backend: every step says so.
struct NoBackendAuthService: AuthService {
    private var unavailable: AuthError { .server("This build isn't connected to a backend yet.") }
    func identify(_ identifier: String) async throws -> IdentifyResult { throw unavailable }
    func signIn(identifier: String, password: String) async throws -> PasswordSignIn { throw unavailable }
    func verifySignInCode(_ code: String, tokens: AuthTokens) async throws { throw unavailable }
    func resendSignInCode(tokens: AuthTokens) async throws { throw unavailable }
    func startSignUp(email: String) async throws { throw unavailable }
    func verifySignUpCode(email: String, code: String) async throws -> AuthTokens { throw unavailable }
    func setInitialPassword(_ password: String, tokens: AuthTokens) async throws -> AuthTokens { throw unavailable }
    func startReset(identifier: String) async throws { throw unavailable }
    func finishReset(identifier: String, code: String, newPassword: String) async throws -> AuthTokens { throw unavailable }
    func startPasswordChange(current: String, tokens: AuthTokens) async throws { throw unavailable }
    func finishPasswordChange(code: String, newPassword: String, tokens: AuthTokens) async throws -> AuthTokens { throw unavailable }
    func saveProfile(_ draft: ProfileDraft, tokens: AuthTokens) async throws -> Profile { throw unavailable }
    func loadProfile(tokens: AuthTokens) async throws -> Profile? { throw unavailable }
    func refresh(_ tokens: AuthTokens) async throws -> AuthTokens { throw unavailable }
    func signOut(tokens: AuthTokens) async {}
}

struct ComingSoonBanner: View {
    @Environment(ConversationStore.self) private var store

    var body: some View {
        if let text = store.banner {
            Text(text)
                .font(Theme.font(.subheadline, weight: .medium))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .limeGlass()
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .accessibilityIdentifier("coming-soon-banner")
                .accessibilityAddTraits(.updatesFrequently)
        }
    }
}
