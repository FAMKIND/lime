import SwiftUI

/// Settings → Account → Delete account (LIME-113, App Store rule 5.1.1(v)): what happens, then type DELETE, then your password, then the emailed code.
@MainActor
@Observable
final class DeleteAccountModel {
    enum Step: Equatable { case explain, confirm, code }

    var step: Step = .explain
    var typed = "" { didSet { if typed != oldValue { errorMessage = nil } } }
    var password = "" { didSet { if password != oldValue { errorMessage = nil } } }
    var code = "" { didSet { if code != oldValue { errorMessage = nil } } }
    private(set) var isBusy = false
    private(set) var errorMessage: String?

    private let start: @MainActor (String) async throws -> Void
    private let finish: @MainActor (String, String) async throws -> Void

    init(start: @escaping @MainActor (String) async throws -> Void, finish: @escaping @MainActor (String, String) async throws -> Void) {
        self.start = start
        self.finish = finish
    }

    var canContinue: Bool { !isBusy && typed == "DELETE" && !password.isEmpty }
    var canDelete: Bool { !isBusy && OnboardingModel.codeLengths.contains(code.count) && code.allSatisfy(\.isNumber) }

    func sendCode() async {
        guard canContinue else { return }
        await run { try await self.start(self.password); self.step = .code }
    }

    func delete() async {
        guard canDelete else { return }
        await run { try await self.finish(self.password, self.code) }
    }

    func back() { if step == .code { step = .confirm; code = "" } else if step == .confirm { step = .explain } }

    private func run(_ work: @MainActor () async throws -> Void) async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do { try await work() } catch let error as AuthError {
            errorMessage = error == .invalidCredentials ? "That isn\u{2019}t your password." : ConnectionProblem.from(error) == .other ? error.message : ConnectionProblem.from(error).message
        } catch {
            errorMessage = ConnectionProblem.from(error).message
        }
    }
}

struct DeleteAccountScreen: View {
    @Environment(AccountSession.self) private var session
    let onClose: () -> Void
    @State private var model: DeleteAccountModel?

    var body: some View {
        Group {
            if let model { content(model) } else { Color.clear }
        }
        .task {
            if model == nil {
                let account = session
                model = DeleteAccountModel(
                    start: { try await account.startAccountDeletion(password: $0) },
                    finish: { password, code in try await account.deleteAccount(password: password, code: code) })
            }
        }
    }

    private func content(_ model: DeleteAccountModel) -> some View {
        @Bindable var model = model
        return SettingsPage(title: "Delete Account") {
            switch model.step {
            case .explain:
                VStack(alignment: .leading, spacing: 14) {
                    Text("This deletes your lime account for good.").font(Theme.title).foregroundStyle(Theme.text)
                        .accessibilityIdentifier("delete-title")
                    point("Your profile, jam and org pages, posts on lime\u{2019}s server and your account are deleted.")
                    point("Your contacts are told. Your chats with them show \u{201C}This account was deleted\u{201D}.")
                    point("What other people already have on their phones stays there: messages and posts they downloaded. lime can\u{2019}t reach into their phones.")
                    point("You\u{2019}ll be signed out on every device, and this iPhone forgets everything.")
                    point("Your username is kept for 30 days so nobody else can take it. You can sign up again with the same email right away.")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                destructive("Continue", enabled: true, busy: false, id: "delete-continue") { model.step = .confirm }
            case .confirm:
                SettingsFootnote(text: "Type DELETE and enter your password. We\u{2019}ll email you a code to finish.")
                TextField("Type DELETE", text: $model.typed)
                    .textInputAutocapitalization(.characters).autocorrectionDisabled()
                    .font(Theme.body).padding(.horizontal, 18).frame(minHeight: 56)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .accessibilityIdentifier("delete-type")
                RevealablePassword(prompt: "Password", text: $model.password, identifier: "delete-password", contentType: .password, submit: .done, minHeight: 56)
                if let message = model.errorMessage { error(message) }
                destructive("Send code", enabled: model.canContinue, busy: model.isBusy, id: "delete-send") { await model.sendCode() }
                backButton(model)
            case .code:
                SettingsFootnote(text: "We emailed you a code. Enter it to delete your account. This can\u{2019}t be undone.")
                TextField("Code", text: $model.code)
                    .keyboardType(.numberPad).textContentType(.oneTimeCode)
                    .font(.system(.title3, design: .monospaced, weight: .semibold))
                    .padding(.horizontal, 18).frame(minHeight: 56)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .accessibilityIdentifier("delete-code")
                if let message = model.errorMessage { error(message) }
                destructive("Delete my account", enabled: model.canDelete, busy: model.isBusy, id: "delete-confirm") { await model.delete() }
                backButton(model)
            }
        }
    }

    private func point(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\u{2022}").font(Theme.body).foregroundStyle(Theme.textSecondary)
            Text(text).font(Theme.body).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func error(_ message: String) -> some View {
        Text(message).font(Theme.secondary).foregroundStyle(Color.red)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12)
            .accessibilityIdentifier("delete-error")
    }

    private func backButton(_ model: DeleteAccountModel) -> some View {
        Button("Back") { model.back() }.font(Theme.font(.subheadline, weight: .semibold)).foregroundStyle(Theme.text)
            .accessibilityIdentifier("delete-back")
    }

    /// Red, not lime: lime is for the one primary, everyday action.
    private func destructive(_ title: String, enabled: Bool, busy: Bool, id: String, action: @escaping @MainActor () async -> Void) -> some View {
        Button { Task { await action() } } label: {
            HStack {
                if busy { ProgressView().tint(.white) }
                Text(title).font(Theme.title)
            }
            .foregroundStyle(Color.white.opacity(enabled ? 1 : 0.6))
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(Color.red.opacity(enabled ? 1 : 0.4), in: Capsule())
        }
        .disabled(!enabled)
        .accessibilityIdentifier(id)
    }
}
