import Foundation
import Observation

/// Changing the password from Settings: the current password and the new one (twice), then the emailed
/// code. The new password only leaves the phone together with the code.
@MainActor
@Observable
final class ChangePasswordModel {
    enum Step: Equatable { case passwords, code, done }

    var step: Step = .passwords
    var current = "" { didSet { if current != oldValue { errorMessage = nil } } }
    var newPassword = "" { didSet { if newPassword != oldValue { errorMessage = nil } } }
    var confirmation = "" { didSet { if confirmation != oldValue { errorMessage = nil } } }
    var code = "" { didSet { if code != oldValue { errorMessage = nil } } }
    private(set) var isBusy = false
    private(set) var errorMessage: String?

    private let start: @MainActor (String) async throws -> Void
    private let finish: @MainActor (String, String) async throws -> Void

    init(start: @escaping @MainActor (String) async throws -> Void, finish: @escaping @MainActor (String, String) async throws -> Void) {
        self.start = start
        self.finish = finish
    }

    var checks: PasswordChecks { PasswordChecks(password: newPassword, confirmation: confirmation, creating: true) }

    var canSend: Bool {
        !isBusy && !current.isEmpty && checks.isAcceptable && newPassword != current
    }

    /// Why the new password cannot be used yet, for the hint.
    var hint: String {
        if !newPassword.isEmpty, newPassword == current { return "Choose a password different from your current one." }
        if !confirmation.isEmpty, !checks.matches { return "The two new passwords don't match." }
        return checks.hint
    }

    var canVerify: Bool { !isBusy && OnboardingModel.codeLengths.contains(code.count) && code.allSatisfy(\.isNumber) }

    func sendCode() async {
        guard canSend else { return }
        await run {
            try await self.start(self.current)
            self.step = .code
        }
    }

    func verify() async {
        guard canVerify else { return }
        await run {
            try await self.finish(self.code, self.newPassword)
            self.current = ""; self.newPassword = ""; self.confirmation = ""; self.code = ""
            self.step = .done
        }
    }

    func back() {
        if step == .code { step = .passwords; code = "" }
    }

    private func run(_ work: @MainActor () async throws -> Void) async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do { try await work() } catch let error as AuthError {
            errorMessage = error == .invalidCredentials ? "That isn't your current password." : ConnectionProblem.from(error) == .other ? error.message : ConnectionProblem.from(error).message
        } catch {
            errorMessage = ConnectionProblem.from(error).message
        }
    }
}
