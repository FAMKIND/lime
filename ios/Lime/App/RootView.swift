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
        .overlay(alignment: .top) { ComingSoonBanner() }
        .overlay(alignment: .top) { IncomingBannerView() }
        .fullScreenCover(isPresented: Binding(get: { store.calls.inCall }, set: { _ in })) { CallView() }
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
        NavigationStack(path: $store.path) {
            MessagesView()
                .navigationDestination(for: Conversation.ID.self) { id in
                    ChatView(conversationID: id)
                }
                .navigationDestination(for: GroupTarget.self) { target in
                    GroupDetailsView(target: target)
                }
                .navigationDestination(for: ThreadTarget.self) { target in
                    ThreadView(target: target)
                }
                .navigationDestination(for: ChatTarget.self) { target in
                    ChatView(conversationID: target.conversationID, focusMessageID: target.messageID, focusWords: target.words)
                }
                .navigationDestination(for: MessagesRoute.self) { route in
                    switch route {
                    case .requests: RequestsView()
                    case .search: MessageSearchScreen()
                    }
                }
        }
        .tint(Theme.text)
        .sheet(isPresented: $explaining) { NotificationExplainerSheet() }
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
                .font(Theme.secondary.weight(.medium))
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
