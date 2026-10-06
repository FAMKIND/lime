import SwiftUI

// MARK: Splash and welcome

struct SplashView: View {
    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()
            Image("LimeLogo")
                .resizable().scaledToFit()
                .frame(width: 112, height: 112)
                .accessibilityHidden(true)
        }
        .accessibilityIdentifier("splash")
    }
}

struct WelcomeView: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)
            Image("LimeWelcomeLogo")
                .resizable().scaledToFit()
                .frame(maxWidth: 190, maxHeight: 230)
                .accessibilityHidden(true)
                .accessibilityIdentifier("welcome-logo")
            Spacer(minLength: 24)
            VStack(spacing: 10) {
                Text("Connect All Teachers")
                    .font(.system(.title, design: .default, weight: .bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.text)
                    .accessibilityIdentifier("welcome-headline")
                Text("A secure messenger made for teachers.")
                    .font(Theme.body)
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 24)
            Spacer(minLength: 24)
            VStack(spacing: 16) {
                (Text("By continuing, you agree to Lime's ")
                    + Text("[Terms](https://famkind.com)").underline()
                    + Text(" and ")
                    + Text("[Privacy Policy](https://famkind.com)").underline() + Text("."))
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .tint(Theme.text)
                PrimaryButton(title: "Continue", identifier: "welcome-continue", action: onContinue)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
        }
        .background(Theme.canvas.ignoresSafeArea())
    }
}

// MARK: The flow

struct OnboardingFlow: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        Group {
            switch model.step {
            case .welcome:
                WelcomeView { model.start() }
            case .identifier:
                IdentifierScreen(model: model)
            case .code:
                CodeScreen(model: model)
            case .password:
                PasswordScreen(model: model)
            case .profile:
                ProfileScreen(model: model)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.step)
        .sheet(isPresented: Binding(get: { model.confirmation != nil }, set: { if !$0 { model.editIdentifier() } })) {
            ConfirmationSheet(model: model)
        }
    }
}

// MARK: Your email or username

struct IdentifierScreen: View {
    @Bindable var model: OnboardingModel
    @FocusState private var focused: Bool

    private var note: String? {
        switch model.identifierKind {
        case .phone: "Phone sign-in is coming later. Use your email for now."
        case .invalid(let message): message
        default: nil
        }
    }

    var body: some View {
        OnboardingScaffold(
            title: "Your email or username",
            subtitle: "We'll send you a code to confirm it's you.",
            canNext: model.canSubmitIdentifier, isBusy: model.isBusy, errorMessage: model.errorMessage,
            onBack: { model.back() }, onNext: { Task { await model.submitIdentifier() } }
        ) {
            OnboardingField(label: "Email or username", text: $model.identifier, prompt: "you@example.com",
                            identifier: "identifier-field", contentType: .username, keyboard: .emailAddress, submit: .next) {
                Task { await model.submitIdentifier() }
            }
            .focused($focused)
            if let note {
                Text(note)
                    .font(Theme.secondary)
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityIdentifier("identifier-note")
            }
        }
        .onAppear { focused = true }
    }
}

struct ConfirmationSheet: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        VStack(spacing: 20) {
            if let confirmation = model.confirmation {
                VStack(spacing: 8) {
                    Text(confirmation.isUnknownUsername ? confirmation.title : (confirmation.title.hasSuffix(":") ? confirmation.title : confirmation.title))
                        .font(Theme.body)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                    Text(confirmation.detail)
                        .font(.system(.title3, design: .default, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("confirmation-detail")
                    if !confirmation.isUnknownUsername {
                        Text("Is this correct?").font(Theme.body).foregroundStyle(Theme.textSecondary)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("confirmation-text")
                if confirmation.isUnknownUsername {
                    PrimaryButton(title: "Use your email instead", identifier: "confirm-edit") { model.editIdentifier() }
                } else {
                    VStack(spacing: 10) {
                        PrimaryButton(title: "Yes", identifier: "confirm-yes", isBusy: model.isBusy) { Task { await model.confirmIdentifier() } }
                        Button("Edit") { model.editIdentifier() }
                            .font(Theme.body.weight(.semibold))
                            .foregroundStyle(Theme.text)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .accessibilityIdentifier("confirm-edit")
                    }
                }
                if let error = model.errorMessage {
                    Text(error).font(Theme.secondary).foregroundStyle(Color(red: 0.72, green: 0.17, blue: 0.2))
                        .accessibilityIdentifier("error-message")
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(Theme.canvas.ignoresSafeArea())
        .presentationDetents([.height(320)])
    }
}

// MARK: The code

struct CodeScreen: View {
    @Bindable var model: OnboardingModel
    @FocusState private var focused: Bool
    @State private var now = Date()
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        OnboardingScaffold(
            title: "Enter the code",
            subtitle: "We sent a code to \(model.codeDestination).",
            canNext: model.canSubmitCode, isBusy: model.isBusy, errorMessage: model.errorMessage,
            onBack: { model.back() }, onNext: { Task { await model.submitCode() } }
        ) {
            ZStack {
                // The real field (one-time-code autofill); the boxes below only display it.
                TextField("", text: $model.code)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .focused($focused)
                    .opacity(0.01)
                    .frame(height: 56)
                    .accessibilityIdentifier("code-field")
                    .accessibilityLabel("Code from the email")
                    .onChange(of: model.code) { old, value in
                        let digits = String(value.filter(\.isNumber).prefix(8))
                        if digits != value { model.code = digits }
                        // A whole code arriving at once (autofill from the email, or a paste) is sent
                        // straight away; a code typed digit by digit waits for Next, because the digits
                        // typed so far might be only the start of a longer code.
                        if digits.count - old.count >= 6 && OnboardingModel.codeLengths.contains(digits.count) {
                            Task { await model.submitCode() }
                        }
                    }
                HStack(spacing: 10) {
                    ForEach(0..<model.codeBoxCount, id: \.self) { index in
                        let characters = Array(model.code)
                        Text(index < characters.count ? String(characters[index]) : "")
                            .font(.system(model.codeBoxCount > 6 ? .title3 : .title, design: .monospaced, weight: .semibold))
                            .foregroundStyle(Theme.text)
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(index == characters.count ? Theme.text : Theme.hairline, lineWidth: index == characters.count ? 1.5 : 0.5))
                    }
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
            .onTapGesture { focused = true }

            HStack {
                let seconds = model.resendSeconds(at: now)
                Button(seconds == 0 ? "Resend code" : "Resend code in \(seconds)s") { Task { await model.resendCode() } }
                    .font(Theme.secondary.weight(.semibold))
                    .foregroundStyle(seconds == 0 ? Theme.text : Theme.textSecondary)
                    .disabled(seconds > 0 || model.isBusy)
                    .accessibilityIdentifier("resend-code")
                Spacer()
                Button("Edit") { model.back() }
                    .font(Theme.secondary.weight(.semibold))
                    .foregroundStyle(Theme.text)
                    .accessibilityIdentifier("code-edit")
            }
        }
        .onAppear { focused = true }
        .onReceive(tick) { now = $0 }
    }
}

// MARK: Passwords

struct PasswordScreen: View {
    @Bindable var model: OnboardingModel
    @FocusState private var focused: Field?
    enum Field { case password, confirm }

    private var title: String {
        switch model.intent {
        case .signUp: "Create a password"
        case .signIn: "Enter your password"
        case .reset: "Choose a new password"
        }
    }

    var body: some View {
        OnboardingScaffold(
            title: title,
            subtitle: model.intent == .signIn ? "Then we'll email you a code." : "Use at least 10 characters.",
            canNext: model.canSubmitPassword, isBusy: model.isBusy, errorMessage: model.errorMessage,
            onBack: { model.back() }, onNext: { Task { await model.submitPassword() } }
        ) {
            if model.intent == .signIn {
                OnboardingField(label: "Password", text: $model.password, prompt: "Your password", isSecure: true,
                                identifier: "password-field", contentType: .password, submit: .go) {
                    Task { await model.submitPassword() }
                }
                .focused($focused, equals: .password)
                Button("Forgot password?") { Task { await model.forgotPassword() } }
                    .font(Theme.secondary.weight(.semibold))
                    .foregroundStyle(Theme.text)
                    .accessibilityIdentifier("forgot-password")
            } else {
                OnboardingField(label: "Password", text: $model.password, prompt: "At least 10 characters", isSecure: true,
                                identifier: "password-field", contentType: .newPassword, submit: .next) { focused = .confirm }
                    .focused($focused, equals: .password)
                OnboardingField(label: "Confirm password", text: $model.confirmPassword, prompt: "Type it again", isSecure: true,
                                identifier: "confirm-password-field", contentType: .newPassword, submit: .go) {
                    Task { await model.submitPassword() }
                }
                .focused($focused, equals: .confirm)
                let checks = model.passwordChecks
                VStack(alignment: .leading, spacing: 4) {
                    Text(checks.hint)
                        .font(Theme.secondary)
                        .foregroundStyle(checks.longEnough ? Theme.text : Theme.textSecondary)
                        .accessibilityIdentifier("password-hint")
                    if !model.confirmPassword.isEmpty && !checks.matches {
                        Text("The two passwords don't match.")
                            .font(Theme.secondary)
                            .foregroundStyle(Color(red: 0.72, green: 0.17, blue: 0.2))
                            .accessibilityIdentifier("password-mismatch")
                    }
                }
            }
        }
        .onAppear { focused = .password }
    }
}

// MARK: A new account's profile

struct ProfileScreen: View {
    @Bindable var model: OnboardingModel
    @FocusState private var focused: Bool

    var body: some View {
        OnboardingScaffold(
            title: "Your name",
            subtitle: "This is how other teachers will see you.",
            showsBack: false, canNext: model.canSubmitProfile, isBusy: model.isBusy, errorMessage: model.errorMessage,
            onNext: { Task { await model.submitProfile() } }
        ) {
            OnboardingField(label: "Name", text: $model.displayName, prompt: "Your name", identifier: "name-field", contentType: .name)
                .focused($focused)
            OnboardingField(label: "Username (optional)", text: $model.username, prompt: "e.g. ms.park", identifier: "username-field",
                            contentType: .username)
            if let problem = model.usernameProblem {
                Text(problem).font(Theme.secondary).foregroundStyle(Color(red: 0.72, green: 0.17, blue: 0.2))
                    .accessibilityIdentifier("username-problem")
            }
            OnboardingField(label: "School (optional)", text: $model.school, prompt: "Where you teach", identifier: "school-field",
                            contentType: .organizationName, submit: .done) {
                Task { await model.submitProfile() }
            }
        }
        .onAppear { focused = true }
    }
}
