import SwiftUI

/// "About Lime": the app and LimeCore versions, and a live run of LimeCore's encryption self-test
/// (real vodozemac Olm and Megolm round trips, in memory). Opened by long-pressing the logo.
struct AboutView: View {
    private enum Result {
        case running
        case finished(SelfTestReport)

        var passed: Bool {
            if case .finished(let report) = self { return report.olmOk && report.megolmOk }
            return false
        }
    }

    @State private var result: Result = .running
    /// nil while checking; then whether the database on disk is encrypted.
    @State private var storageEncrypted: Bool?
    @Environment(ConversationStore.self) private var store
    @Environment(AccountSession.self) private var session
    @State private var confirmingSignOut = false
    @Environment(\.dismiss) private var dismiss

    #if DEBUG
    private var developerLine: String {
        guard session.hasBackend else { return "Developer: staging · Not connected" }
        let who = session.maskedEmail ?? session.profile?.username.map { "@\($0)" } ?? "—"
        return "Developer: staging · Signed in as \(who) · device registered \(session.deviceRegistered ? "✓" : "✗")"
    }
    #endif

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    var body: some View {
        VStack(spacing: 20) {
            Image("LimeLogo")
                .resizable().scaledToFit()
                .frame(width: 72, height: 72)
                .accessibilityHidden(true)
            VStack(spacing: 4) {
                Text("About Lime").font(Theme.title)
                Text("Lime \(appVersion) · Core \(coreVersion())")
                    .font(Theme.secondary)
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityIdentifier("about-versions")
            }
            VStack(spacing: 6) {
                switch result {
                case .running:
                    ProgressView()
                    Text("Encryption self-test: running…")
                        .accessibilityIdentifier("self-test-result")
                case .finished(let report):
                    Text(result.passed ? "Encryption self-test: passed ✓" : "Encryption self-test: failed")
                        .font(Theme.body.weight(.semibold))
                        .foregroundStyle(Theme.text)
                        .accessibilityIdentifier("self-test-result")
                    Text(report.detail)
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }
            Group {
                switch storageEncrypted {
                case nil: Text("Storage: checking…")
                case true?: Text("Storage: encrypted ✓")
                case false?: Text("Storage: not encrypted")
                }
            }
            .font(Theme.body.weight(.semibold))
            .foregroundStyle(Theme.text)
            .accessibilityIdentifier("storage-result")
            #if DEBUG
            // Debug builds only: the staging backend's state.
            Text(developerLine)
                .font(Theme.caption)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("developer-staging")
            Button("Load sample chats") { Task { await store.loadSampleChats() } }
                .font(Theme.secondary.weight(.semibold))
                .foregroundStyle(Theme.text)
                .accessibilityIdentifier("load-sample-chats")
            #endif
            Button("Sign out", role: .destructive) { confirmingSignOut = true }
                .font(Theme.secondary.weight(.semibold))
                .accessibilityIdentifier("sign-out")
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .tint(Theme.primary)
                .foregroundStyle(Theme.primaryInk)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.canvas.ignoresSafeArea())
        .presentationDetents([.large])
        .confirmationDialog("Sign out of Lime?", isPresented: $confirmingSignOut, titleVisibility: .visible) {
            Button("Sign out and remove chats from this phone", role: .destructive) {
                dismiss()
                Task { await session.signOut() }
            }
            .accessibilityIdentifier("sign-out-confirm")
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(SignOutCopy.warning)
        }
        .task {
            // Off the main thread: real key generation and encryption.
            let report = await Task.detached(priority: .userInitiated) { encryptionSelfTest() }.value
            result = .finished(report)
            storageEncrypted = await store.storageIsEncrypted()
        }
    }
}
