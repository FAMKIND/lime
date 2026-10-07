import SwiftUI

// MARK: Account

struct AccountScreen: View {
    @Environment(AccountSession.self) private var session
    @State private var confirmingSignOut = false
    let onClose: () -> Void

    var body: some View {
        SettingsPage(title: "Account") {
            SettingsCard {
                HStack(spacing: 14) {
                    Image(systemName: "envelope").font(.system(size: 20)).frame(width: 28).foregroundStyle(Theme.text)
                    Text("Email").font(Theme.body).foregroundStyle(Theme.text)
                    Spacer()
                    Text(session.profile?.maskedEmail ?? session.maskedEmail ?? "—").font(Theme.secondary).foregroundStyle(Theme.textSecondary)
                        .accessibilityIdentifier("account-email")
                }
                .padding(.horizontal, 18).frame(minHeight: 58)
                Divider().overlay(Theme.hairline).padding(.leading, 60)
                SettingsRow(symbol: "key", title: "Change Password", route: .changePassword, id: "account-change-password", showsDivider: false)
            }
            SettingsFootnote(text: "Your email is only used to sign in and to send you codes. Other teachers never see it.")
            SettingsCard {
                Button { confirmingSignOut = true } label: {
                    SettingsRowLabel(symbol: "rectangle.portrait.and.arrow.right", title: "Sign Out", showsDivider: false, destructive: true)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("account-sign-out")
            }
        }
        .confirmationDialog("Sign out of Lime?", isPresented: $confirmingSignOut, titleVisibility: .visible) {
            Button("Sign out and remove messages from this iPhone", role: .destructive) {
                onClose()
                Task { await session.signOut() }
            }
            .accessibilityIdentifier("account-sign-out-confirm")
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(SignOutCopy.warning)
        }
    }
}

// MARK: Change password

struct ChangePasswordScreen: View {
    @Environment(AccountSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var model: ChangePasswordModel?

    var body: some View {
        Group {
            if let model { content(model) } else { Color.clear }
        }
        .task {
            if model == nil {
                let account = session
                model = ChangePasswordModel(
                    start: { try await account.startPasswordChange(current: $0) },
                    finish: { try await account.finishPasswordChange(code: $0, newPassword: $1) })
            }
        }
    }

    private func content(_ model: ChangePasswordModel) -> some View {
        @Bindable var model = model
        return SettingsPage(title: "Change Password") {
            switch model.step {
            case .passwords:
                VStack(spacing: 12) {
                    secure("Current password", $model.current, id: "pw-current", type: .password)
                    secure("New password", $model.newPassword, id: "pw-new", type: .newPassword)
                    secure("Confirm new password", $model.confirmation, id: "pw-confirm", type: .newPassword)
                }
                SettingsFootnote(text: model.hint)
                if let message = model.errorMessage { error(message) }
                primary("Send code", enabled: model.canSend, busy: model.isBusy, id: "pw-send") { await model.sendCode() }
            case .code:
                SettingsFootnote(text: "We emailed you a code. Enter it to finish changing your password.")
                TextField("Code", text: $model.code)
                    .keyboardType(.numberPad).textContentType(.oneTimeCode)
                    .selectionTint()
                    .font(.system(.title3, design: .monospaced, weight: .semibold))
                    .padding(.horizontal, 18).frame(minHeight: 56)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .accessibilityIdentifier("pw-code")
                if let message = model.errorMessage { error(message) }
                primary("Change password", enabled: model.canVerify, busy: model.isBusy, id: "pw-verify") { await model.verify() }
                Button("Back") { model.back() }.font(Theme.secondary.weight(.semibold)).foregroundStyle(Theme.text)
                    .accessibilityIdentifier("pw-back")
            case .done:
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 48)).foregroundStyle(Theme.accent)
                    Text("Your password was changed.").font(Theme.title).foregroundStyle(Theme.text)
                        .accessibilityIdentifier("pw-done")
                    Text("You are still signed in on this iPhone. Other phones will need the new password.")
                        .font(Theme.secondary).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
                }
                .padding(.top, 24)
                primary("Done", enabled: true, busy: false, id: "pw-finish") { dismiss() }
            }
        }
    }

    private func secure(_ label: String, _ text: Binding<String>, id: String, type: UITextContentType) -> some View {
        SecureField(label, text: text)
            .textContentType(type)
            .padding(.horizontal, 18).frame(minHeight: 56)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityIdentifier(id)
    }

    private func error(_ message: String) -> some View {
        Text(message).font(Theme.secondary).foregroundStyle(Color.red)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12)
            .accessibilityIdentifier("pw-error")
    }

    private func primary(_ title: String, enabled: Bool, busy: Bool, id: String, action: @escaping @MainActor () async -> Void) -> some View {
        Button { Task { await action() } } label: {
            HStack {
                if busy { ProgressView().tint(Theme.accentInk) }
                Text(title).font(Theme.title)
            }
            .foregroundStyle(Theme.accentInk.opacity(enabled ? 1 : 0.5))
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(Theme.accent.opacity(enabled ? 1 : 0.4), in: Capsule())
        }
        .disabled(!enabled)
        .accessibilityIdentifier(id)
    }
}

// MARK: Privacy

struct PrivacyScreen: View {
    @Environment(ConversationStore.self) private var store
    @State private var blockedCount: Int?

    var body: some View {
        SettingsPage(title: "Privacy") {
            SettingsCard {
                SettingsRow(symbol: "nosign", title: "Blocked", value: blockedCount.map { $0 == 0 ? "None" : "\($0)" }, route: .blocked, id: "privacy-blocked")
                SettingsRow(symbol: "key.viewfinder", title: "Safety Numbers", route: .keys, id: "privacy-keys", showsDivider: false)
            }
            SettingsFootnote(text: "Messages are end-to-end encrypted: only you and the person you message can read them.")
        }
        .task { blockedCount = await store.blockedPeople().count }
    }
}

struct BlockedScreen: View {
    @Environment(ConversationStore.self) private var store
    @State private var blocked: [BlockedPerson]?

    var body: some View {
        SettingsPage(title: "Blocked") {
            if let blocked {
                if blocked.isEmpty {
                    Text("No one is blocked.").font(Theme.body).foregroundStyle(Theme.textSecondary).padding(.top, 40)
                        .accessibilityIdentifier("blocked-empty")
                } else {
                    SettingsCard {
                        ForEach(blocked, id: \.conversationId) { person in
                            VStack(spacing: 0) {
                                HStack(spacing: 14) {
                                    AvatarView(person: Person(id: String(person.conversationId.dropFirst(3)), name: person.name), size: 44)
                                    Text(person.name).font(Theme.body).foregroundStyle(Theme.text).lineLimit(1)
                                    Spacer(minLength: 8)
                                    Button("Unblock") {
                                        Task {
                                            await store.unblock(person.conversationId)
                                            self.blocked = await store.blockedPeople()
                                        }
                                    }
                                    .font(Theme.secondary.weight(.semibold)).foregroundStyle(Theme.accentInk)
                                    .padding(.horizontal, 14).frame(minHeight: 36)
                                    .background(Theme.accent, in: Capsule())
                                    .accessibilityIdentifier("unblock-\(person.conversationId)")
                                }
                                .padding(.horizontal, 18).frame(minHeight: 66)
                                if person.conversationId != blocked.last?.conversationId { Divider().overlay(Theme.hairline).padding(.leading, 76) }
                            }
                        }
                    }
                    SettingsFootnote(text: "Blocked people can't reach you on this iPhone. Unblocking brings back your earlier messages with them.")
                }
            }
        }
        .task { blocked = await store.blockedPeople() }
    }
}

struct KeysScreen: View {
    @Environment(ConversationStore.self) private var store
    @State private var info: KeyInfo?
    @State private var loaded = false

    var body: some View {
        SettingsPage(title: "Safety Numbers") {
            if let info {
                SettingsCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Your key was set on \(Self.date(info.createdAt))").font(Theme.body).foregroundStyle(Theme.text)
                            .accessibilityIdentifier("keys-date")
                        Text(info.fingerprint).font(.system(.title3, design: .monospaced, weight: .semibold)).foregroundStyle(Theme.text)
                            .textSelection(.enabled).accessibilityIdentifier("keys-fingerprint")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(18)
                }
                SettingsFootnote(text: "This short code identifies your account's key. Comparing it with a contact is coming later; for now it is read-only.")
            } else if loaded {
                Text("This iPhone has no keys yet. They are made when you sign in.").font(Theme.body).foregroundStyle(Theme.textSecondary).padding(.top, 40)
            }
        }
        .task { info = await store.keyInfo(); loaded = true }
    }

    static func date(_ milliseconds: Int64) -> String {
        Date(timeIntervalSince1970: Double(milliseconds) / 1000).formatted(date: .long, time: .omitted)
    }
}

struct LinkedDevicesScreen: View {
    var body: some View {
        SettingsPage(title: "Linked Devices") {
            SettingsCard {
                HStack(spacing: 14) {
                    Image(systemName: "iphone").font(.system(size: 24)).frame(width: 32).foregroundStyle(Theme.text)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("This iPhone").font(Theme.title).foregroundStyle(Theme.text).accessibilityIdentifier("devices-this")
                        Text("Active now").font(Theme.secondary).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                }
                .padding(18)
            }
            SettingsFootnote(text: "Using Lime on more than one device is coming soon.")
                .accessibilityIdentifier("devices-note")
        }
    }
}

// MARK: Customize

struct CustomizeScreen: View {
    @AppStorage(AppearanceSetting.storageKey) private var stored = AppearanceSetting.system.rawValue

    var body: some View {
        SettingsPage(title: "Customize") {
            SettingsCard {
                ForEach(AppearanceSetting.allCases) { option in
                    Button { stored = option.rawValue } label: {
                        VStack(spacing: 0) {
                            HStack(spacing: 14) {
                                Image(systemName: option.symbol).font(.system(size: 20)).frame(width: 28).foregroundStyle(Theme.text)
                                Text(option.title).font(Theme.body).foregroundStyle(Theme.text)
                                Spacer()
                                if stored == option.rawValue {
                                    Image(systemName: "checkmark").font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.text)
                                }
                            }
                            .padding(.horizontal, 18).frame(minHeight: 58)
                            if option != AppearanceSetting.allCases.last { Divider().overlay(Theme.hairline).padding(.leading, 60) }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("appearance-\(option.rawValue)")
                    .accessibilityAddTraits(stored == option.rawValue ? [.isSelected] : [])
                }
            }
            SettingsFootnote(text: "Appearance applies to the whole app and is kept on this iPhone.")
        }
    }
}

// MARK: About and acknowledgements

struct AboutScreen: View {
    @Environment(ConversationStore.self) private var store
    @State private var showDeveloper = false

    private var appVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?" }

    var body: some View {
        SettingsPage(title: "About") {
            SettingsCard {
                HStack(spacing: 14) {
                    Image("LimeLogo").resizable().scaledToFit().frame(width: 44, height: 44).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Lime").font(Theme.title).foregroundStyle(Theme.text)
                        Text("Version \(appVersion) · Core \(coreVersion())").font(Theme.secondary).foregroundStyle(Theme.textSecondary)
                            .accessibilityIdentifier("about-version")
                    }
                    Spacer()
                }
                .padding(18)
            }
            SettingsCard {
                SettingsRow(symbol: "doc.text", title: "Acknowledgements", route: .acknowledgements, id: "about-acknowledgements")
                Link(destination: URL(string: "https://limechat.org/terms")!) {
                    SettingsRowLabel(symbol: "checkmark.shield", title: "Terms of Service")
                }
                .accessibilityIdentifier("about-terms")
                Link(destination: URL(string: "https://limechat.org/privacy")!) {
                    SettingsRowLabel(symbol: "lock", title: "Privacy Policy", showsDivider: false)
                }
                .accessibilityIdentifier("about-privacy")
            }
            #if DEBUG
            SettingsCard {
                Button { showDeveloper = true } label: {
                    SettingsRowLabel(symbol: "wrench.and.screwdriver", title: "Developer", showsDivider: false)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("about-developer")
            }
            #endif
        }
        #if DEBUG
        .sheet(isPresented: $showDeveloper) { AboutView() }
        #endif
    }
}

struct AcknowledgementsScreen: View {
    @State private var blocks: [String] = []

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    Text(block).font(.system(.caption, design: .monospaced)).foregroundStyle(Theme.text)
                        .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                }
            }
            .padding(16)
            .accessibilityIdentifier("acknowledgements-text")
        }
        .background(Theme.canvas.ignoresSafeArea())
        .navigationTitle("Acknowledgements")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task { blocks = Self.loadBlocks() }
    }

    /// The generated text (core/make-acknowledgements.py), cut into chunks so it scrolls smoothly.
    static func loadBlocks() -> [String] {
        guard let url = Bundle.main.url(forResource: "Acknowledgements", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return ["The acknowledgements could not be loaded."] }
        var result: [String] = []
        var current: [Substring] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            current.append(line)
            if current.count >= 40 { result.append(current.joined(separator: "\n")); current = [] }
        }
        if !current.isEmpty { result.append(current.joined(separator: "\n")) }
        return result
    }
}
