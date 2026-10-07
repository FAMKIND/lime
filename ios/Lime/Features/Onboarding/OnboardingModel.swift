import Foundation
import Observation

/// What the one-field first screen made of what was typed.
enum IdentifierKind: Equatable {
    case empty
    case email
    case username
    /// Digits and a leading "+": phone sign-in is not built yet (the user is told).
    case phone
    case invalid(String)
}

/// The sign-up / sign-in flow (DESIGN-03): one question per screen. The server checks the password and
/// the emailed code; this holds the screens' state and what to do next.
///
///   sign up:   identifier, [confirm], code, create password, profile
///   sign in:   identifier, [confirm], password, code
///   forgot:    (from the password screen) code, new password
@MainActor
@Observable
final class OnboardingModel {
    enum Step: Hashable { case welcome, identifier, code, password, profile }
    enum Intent { case signUp, signIn, reset }

    /// The confirmation sheet's content: "Is this correct?"
    struct Confirmation: Equatable {
        var title: String
        var detail: String
        var isUnknownUsername = false
    }

    // The screens' state
    /// Moving to another screen clears any error: a message belongs to the screen that caused it.
    private(set) var step: Step = .welcome {
        didSet { if step != oldValue { errorMessage = nil } }
    }
    private(set) var intent: Intent = .signUp
    // Editing a field clears the error that was about it.
    var identifier = "" { didSet { if identifier != oldValue { errorMessage = nil } } }
    var code = "" { didSet { if code != oldValue { errorMessage = nil } } }
    var password = "" { didSet { if password != oldValue { errorMessage = nil } } }
    var confirmPassword = "" { didSet { if confirmPassword != oldValue { errorMessage = nil } } }
    var displayName = "" { didSet { if displayName != oldValue { errorMessage = nil } } }
    var username = "" { didSet { if username != oldValue { errorMessage = nil } } }
    var school = "" { didSet { if school != oldValue { errorMessage = nil } } }
    private(set) var confirmation: Confirmation?
    private(set) var errorMessage: String?
    private(set) var isBusy = false
    private(set) var maskedEmail: String?
    private(set) var resendAvailableAt = Date.distantPast

    // Where the flow is
    private var email: String?
    private var tokens: AuthTokens?
    private var identified: IdentifyResult?

    private let auth: any AuthService
    private let now: @Sendable () -> Date
    private let onComplete: @MainActor (AuthTokens, Profile?) async -> Void

    nonisolated static let resendDelay: TimeInterval = 30
    nonisolated static let minimumPasswordLength = 10

    init(auth: any AuthService, now: @escaping @Sendable () -> Date = { Date() },
         onComplete: @escaping @MainActor (AuthTokens, Profile?) async -> Void) {
        self.auth = auth
        self.now = now
        self.onComplete = onComplete
    }

    // MARK: Derived

    var identifierKind: IdentifierKind { Self.classify(identifier) }

    var canSubmitIdentifier: Bool {
        switch identifierKind {
        case .email, .username: !isBusy
        default: false
        }
    }

    /// The code is 6 digits as configured here, but the hosted project's own setting can differ (it once
    /// sent 8): accept 6 to 8 digits, and show as many boxes as were typed.
    nonisolated static let codeLengths = 6...8
    var canSubmitCode: Bool { Self.codeLengths.contains(code.count) && code.allSatisfy(\.isNumber) && !isBusy }
    var codeBoxCount: Int { code.count > 6 ? 8 : 6 }

    var passwordChecks: PasswordChecks { PasswordChecks(password: password, confirmation: confirmPassword, creating: intent != .signIn) }

    var canSubmitPassword: Bool {
        guard !isBusy else { return false }
        return intent == .signIn ? !password.isEmpty : passwordChecks.isAcceptable
    }

    var canSubmitProfile: Bool {
        let name = displayName.trimmingCharacters(in: .whitespaces)
        guard !isBusy, !name.isEmpty, name.count <= Profile.maxNameLength else { return false }
        let handle = typedUsername
        return handle.isEmpty || Self.usernameError(handle) == nil
    }

    /// The username as typed, without spaces or a leading "@".
    private var typedUsername: String {
        username.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "@"))
    }

    var usernameProblem: String? {
        let handle = typedUsername
        return handle.isEmpty ? nil : Self.usernameError(handle)
    }

    /// Seconds until a new code can be asked for (0 when it can).
    func resendSeconds(at date: Date? = nil) -> Int {
        max(0, Int((resendAvailableAt.timeIntervalSince(date ?? now())).rounded(.up)))
    }

    /// Where the code was sent, for the code screen's text.
    var codeDestination: String {
        switch intent {
        case .signUp: email ?? ""
        case .signIn, .reset: maskedEmail ?? email ?? ""
        }
    }

    // MARK: Moves

    func start() { step = .identifier }

    func back() {
        errorMessage = nil
        confirmation = nil
        switch step {
        case .welcome: break
        case .identifier: step = .welcome
        case .code:
            code = ""
            // Back from the code screen of a sign-in returns to the password; of the others, to the start.
            step = intent == .signIn ? .password : .identifier
            if intent == .reset { intent = .signIn }
        case .password:
            password = ""
            confirmPassword = ""
            // After a sign-up's code is verified there is nothing to go back to but the start; a
            // password reset goes back to its code; a sign-in goes back to the identifier.
            if intent == .reset {
                step = .code
                code = ""
            } else {
                tokens = nil
                step = .identifier
            }
        case .profile: break // an account that has its password goes forward only
        }
    }

    /// Next on the identifier screen: ask the server what this is, then show the confirmation sheet.
    func submitIdentifier() async {
        guard canSubmitIdentifier else { return }
        let typed = identifier.trimmingCharacters(in: .whitespaces)
        await run {
            let result = try await self.auth.identify(typed)
            self.identified = result
            switch result {
            case .newEmail:
                self.email = typed.lowercased()
                self.intent = .signUp
                self.confirmation = Confirmation(title: "We'll send a code to:", detail: typed.lowercased())
            case .existingEmail:
                self.email = typed.lowercased()
                self.intent = .signIn
                self.confirmation = Confirmation(title: "Sign in as:", detail: typed.lowercased())
            case .existingUsername(let hint):
                self.email = nil
                self.maskedEmail = hint
                self.intent = .signIn
                self.confirmation = Confirmation(title: "Sign in as @\(typed.trimmingCharacters(in: CharacterSet(charactersIn: "@")))", detail: "The code goes to \(hint)")
            case .unknownUsername:
                self.confirmation = Confirmation(title: "No account with that username", detail: "Check the spelling, or use your email.", isUnknownUsername: true)
            }
        }
    }

    /// "Yes" on the confirmation sheet.
    func confirmIdentifier() async {
        guard let confirmation, !confirmation.isUnknownUsername else { return }
        self.confirmation = nil
        switch intent {
        case .signUp:
            guard let email else { return }
            await run {
                try await self.auth.startSignUp(email: email)
                self.maskedEmail = nil
                self.beginCodeStep()
            }
        case .signIn, .reset:
            password = ""
            step = .password
        }
    }

    /// "Edit" on the confirmation sheet (or the unknown-username sheet's button).
    func editIdentifier() {
        confirmation = nil
        errorMessage = nil
    }

    /// Next on the code screen.
    func submitCode() async {
        guard canSubmitCode else { return }
        let entered = code
        switch intent {
        case .signUp:
            guard let email else { return }
            await run {
                self.tokens = try await self.auth.verifySignUpCode(email: email, code: entered)
                self.password = ""
                self.confirmPassword = ""
                self.step = .password
            }
        case .signIn:
            guard let tokens else { return }
            await run {
                try await self.auth.verifySignInCode(entered, tokens: tokens)
                try await self.finish(tokens)
            }
        case .reset:
            // The code and the new password are checked together on the next screen.
            password = ""
            confirmPassword = ""
            step = .password
        }
    }

    /// Resend the code (after the 30-second wait).
    func resendCode() async {
        guard resendSeconds() == 0, !isBusy else { return }
        await run {
            switch self.intent {
            case .signUp:
                if let email = self.email { try await self.auth.startSignUp(email: email) }
            case .signIn:
                if let tokens = self.tokens { try await self.auth.resendSignInCode(tokens: tokens) }
            case .reset:
                try await self.auth.startReset(identifier: self.identifier.trimmingCharacters(in: .whitespaces))
            }
            self.code = ""
            self.resendAvailableAt = self.now().addingTimeInterval(Self.resendDelay)
        }
    }

    /// Next on the password screen.
    func submitPassword() async {
        guard canSubmitPassword else { return }
        let typed = identifier.trimmingCharacters(in: .whitespaces)
        switch intent {
        case .signUp:
            guard let tokens else { return }
            await run {
                self.tokens = try await self.auth.setInitialPassword(self.password, tokens: tokens)
                self.step = .profile
            }
        case .signIn:
            await run {
                let result = try await self.auth.signIn(identifier: typed, password: self.password)
                self.tokens = result.tokens
                self.maskedEmail = result.maskedEmail
                self.password = ""
                self.beginCodeStep()
            }
        case .reset:
            let entered = code
            await run {
                let fresh = try await self.auth.finishReset(identifier: typed, code: entered, newPassword: self.password)
                try await self.finish(fresh)
            }
        }
    }

    /// "Forgot password?" on the sign-in password screen.
    func forgotPassword() async {
        let typed = identifier.trimmingCharacters(in: .whitespaces)
        await run {
            try await self.auth.startReset(identifier: typed)
            self.intent = .reset
            self.password = ""
            self.beginCodeStep()
        }
    }

    /// Next on the "Your name" screen (a new account).
    func submitProfile() async {
        guard canSubmitProfile, let tokens else { return }
        let draft = ProfileDraft(
            displayName: displayName.trimmingCharacters(in: .whitespaces),
            username: username.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "@")).nilIfEmpty,
            school: school.trimmingCharacters(in: .whitespaces).nilIfEmpty)
        await run {
            let profile = try await self.auth.saveProfile(draft, tokens: tokens)
            await self.onComplete(tokens, profile)
        }
    }

    // MARK: Pieces

    private func beginCodeStep() {
        code = ""
        resendAvailableAt = now().addingTimeInterval(Self.resendDelay)
        step = .code
    }

    /// Both steps are done: look for the account's profile. A new account still has to make one.
    private func finish(_ tokens: AuthTokens) async throws {
        self.tokens = tokens
        if let profile = try await auth.loadProfile(tokens: tokens) {
            await onComplete(tokens, profile)
        } else {
            step = .profile
        }
    }

    private func run(_ work: @escaping @MainActor () async throws -> Void) async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            try await work()
        } catch let error as AuthError {
            errorMessage = error.message
        } catch {
            errorMessage = AuthError.network.message
        }
    }

    // MARK: Rules

    static func classify(_ text: String) -> IdentifierKind {
        let value = text.trimmingCharacters(in: .whitespaces)
        if value.isEmpty { return .empty }
        if value.contains("@") && !value.hasPrefix("@") {
            let parts = value.split(separator: "@", omittingEmptySubsequences: false)
            let ok = parts.count == 2 && !parts[0].isEmpty && parts[1].contains(".") && !parts[1].hasPrefix(".") && !parts[1].hasSuffix(".") && !value.contains(" ")
            return ok ? .email : .invalid("Enter a full email address.")
        }
        let digitsOnly = value.allSatisfy { $0.isNumber || "+-() .".contains($0) }
        if digitsOnly && value.contains(where: \.isNumber) { return .phone }
        let handle = value.trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        if let problem = usernameError(handle) { return .invalid(problem) }
        return .username
    }

    /// The web app's username rules (`public/js/store.js`).
    static func usernameError(_ value: String) -> String? {
        let reserved: Set<String> = ["admin", "administrator", "lime", "support", "help", "root", "system", "moderator", "mod", "staff", "team",
                                     "official", "security", "abuse", "postmaster", "webmaster", "null", "undefined", "api", "www", "mail", "info",
                                     "contact", "billing", "settings", "account", "me", "you", "everyone", "all", "here", "famkind"]
        if value.count < 3 || value.count > 20 { return "Use 3 to 20 characters." }
        if !value.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "_") }) { return "Use only letters, numbers, dots and underscores." }
        if value.hasPrefix(".") || value.hasSuffix(".") { return "A username can't start or end with a dot." }
        if reserved.contains(value.lowercased()) { return "That username is reserved. Try another." }
        return nil
    }
}

/// What a new password has and lacks, for the screen's hint.
struct PasswordChecks: Equatable {
    var password: String
    var confirmation: String
    var creating: Bool

    var longEnough: Bool { password.count >= OnboardingModel.minimumPasswordLength }
    var matches: Bool { !creating || (!confirmation.isEmpty && confirmation == password) }
    var isAcceptable: Bool { longEnough && matches }

    enum Strength: String { case tooShort = "Too short", fair = "Fair", good = "Good", strong = "Strong" }

    var strength: Strength {
        guard longEnough else { return .tooShort }
        var kinds = 0
        if password.contains(where: \.isLowercase) { kinds += 1 }
        if password.contains(where: \.isUppercase) { kinds += 1 }
        if password.contains(where: \.isNumber) { kinds += 1 }
        if password.contains(where: { !$0.isLetter && !$0.isNumber }) { kinds += 1 }
        if password.count >= 16 || kinds >= 3 { return password.count >= 16 && kinds >= 2 ? .strong : .good }
        return .fair
    }

    var hint: String {
        if password.isEmpty { return "At least 10 characters." }
        if !longEnough { return "\(OnboardingModel.minimumPasswordLength - password.count) more to go." }
        return "\(strength.rawValue). A few random words make a good password."
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
