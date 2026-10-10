import SwiftUI

/// Where Settings can go.
enum SettingsRoute: Hashable {
    case profile, account, privacy, blocked, keys, devices, notifications, customize, about, acknowledgements, changePassword, myQR, photo, storage, workHours
    case chatMedia(String)
}

/// The words shown before signing out (here and in Account).
enum SignOutCopy {
    static let warning = "Signing out removes your messages and keys from this iPhone. Your contacts will see that your security key changed."
}

/// Settings (design 05): a sheet with a glass ✕, the profile card, and grouped rows.
struct SettingsView: View {
    @Environment(AccountSession.self) private var session
    @Environment(ConversationStore.self) private var store
    @Environment(NotificationCoordinator.self) private var notifications
    @Environment(\.dismiss) private var dismiss
    @State private var path: [SettingsRoute] = []
    @State private var confirmingSignOut = false

    var body: some View {
        NavigationStack(path: $path) {
            root
                .navigationDestination(for: SettingsRoute.self) { route in
                    switch route {
                    case .profile: ProfileSettingsScreen()
                    case .account: AccountScreen(onClose: { dismiss() })
                    case .privacy: PrivacyScreen()
                    case .blocked: BlockedScreen()
                    case .keys: KeysScreen()
                    case .devices: LinkedDevicesScreen()
                    case .notifications: NotificationsScreen()
                    case .customize: CustomizeScreen()
                    case .about: AboutScreen()
                    case .acknowledgements: AcknowledgementsScreen()
                    case .changePassword: ChangePasswordScreen()
                    case .myQR: MyQRScreen()
                    case .photo: ProfilePhotoScreen()
                    case .storage: StorageScreen()
                    case .workHours: WorkHoursScreen()
                    case .chatMedia(let id): ChatMediaScreen(conversationID: id)
                    }
                }
        }
        .tint(Theme.text)
        .background(Theme.canvas.ignoresSafeArea())
        #if DEBUG
        .task { path = Self.route(from: store.demoSettingsRoute) }
        #endif
    }

    #if DEBUG
    /// Debug demo: open straight to a screen for screenshots ("profile", "privacy", "blocked", ...).
    static func route(from names: [String]) -> [SettingsRoute] {
        let table: [String: SettingsRoute] = [
            "profile": .profile, "account": .account, "privacy": .privacy, "blocked": .blocked, "keys": .keys, "devices": .devices,
            "notifications": .notifications, "customize": .customize, "about": .about, "ack": .acknowledgements, "password": .changePassword, "my-qr": .myQR, "photo": .photo, "crop": .photo, "storage": .storage, "work-hours": .workHours,
        ]
        return names.compactMap { table[$0] }
    }
    #endif

    private var root: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                NavigationLink(value: SettingsRoute.profile) { profileCard }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings-profile")
                SettingsCard {
                    SettingsRow(symbol: "person.crop.circle", title: "Account", route: .account, id: "settings-account")
                    SettingsRow(symbol: "hand.raised", title: "Privacy", route: .privacy, id: "settings-privacy")
                    SettingsRow(symbol: "internaldrive", title: "Storage", route: .storage, id: "settings-storage")
                    SettingsRow(symbol: "iphone", title: "Linked Devices", route: .devices, id: "settings-devices")
                    if let donate = DonateLink.current {
                        Link(destination: donate) {
                            SettingsRowLabel(symbol: "heart", title: "Donate to lime", showsDivider: false)
                        }
                        .accessibilityIdentifier("settings-donate")
                    }
                }
                SettingsCard {
                    SettingsRow(symbol: "bell", title: "Notifications", value: notifications.settings.enabled ? "On" : "Off",
                                route: .notifications, id: "settings-notifications")
                    SettingsRow(symbol: "clock", title: "Work hours", value: StatusSettings.shared.hours.enabled ? "On" : "Off", route: .workHours, id: "settings-work-hours")
                    SettingsRow(symbol: "paintpalette", title: "Customize", route: .customize, id: "settings-customize", showsDivider: false)
                }
                SettingsCard {
                    SettingsRow(symbol: "info.circle", title: "About", route: .about, id: "settings-about", showsDivider: false)
                }
                // Sign out is easy to find here as well as in Account; it says honestly what it does to this phone's keys.
                SettingsCard {
                    Button { confirmingSignOut = true } label: {
                        SettingsRowLabel(symbol: "rectangle.portrait.and.arrow.right", title: "Sign out", showsDivider: false, destructive: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings-sign-out")
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .background(Theme.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityIdentifier("settings-root")
        .confirmationDialog("Sign out of Lime?", isPresented: $confirmingSignOut, titleVisibility: .visible) {
            Button("Sign out and remove messages from this iPhone", role: .destructive) {
                dismiss()
                Task { await session.signOut() }
            }
            .accessibilityIdentifier("settings-sign-out-confirm")
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(SignOutCopy.warning)
        }
    }

    private var header: some View {
        ZStack {
            Text("Settings").font(.system(.title3, design: .default, weight: .bold)).foregroundStyle(Theme.text)
                .accessibilityAddTraits(.isHeader)
            HStack {
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .frame(width: 44, height: 44)
                        .limeGlass()
                }
                .accessibilityLabel("Close")
                .accessibilityIdentifier("settings-close")
            }
        }
        .padding(.top, 16)
    }

    private var profileCard: some View {
        HStack(spacing: 14) {
            AvatarView(person: session.mePerson, size: 60, showsStatus: true)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.profile?.displayName ?? "Your profile").font(Theme.title).foregroundStyle(Theme.text)
                    .accessibilityIdentifier("settings-card-name")
                if let username = session.profile?.username {
                    Text("@\(username)").font(Theme.secondary).foregroundStyle(Theme.textSecondary)
                }
                if let about = session.profile?.about {
                    Text(about).font(Theme.secondary).foregroundStyle(Theme.textSecondary).lineLimit(2)
                        .accessibilityIdentifier("settings-card-about")
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.textSecondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

// MARK: Pieces

struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) { content }
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

struct SettingsRowLabel: View {
    let symbol: String
    let title: String
    var value: String? = nil
    var showsDivider = true
    var destructive = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: symbol).font(.system(size: 20)).frame(width: 28)
                    .foregroundStyle(destructive ? Color.red : Theme.text)
                Text(title).font(Theme.body).foregroundStyle(destructive ? Color.red : Theme.text)
                Spacer(minLength: 8)
                if let value { Text(value).font(Theme.secondary).foregroundStyle(Theme.textSecondary).lineLimit(1) }
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textSecondary.opacity(0.7))
                    .opacity(destructive ? 0 : 1)
            }
            .padding(.horizontal, 18).frame(minHeight: 58)
            if showsDivider { Divider().overlay(Theme.hairline).padding(.leading, 60) }
        }
        .contentShape(Rectangle())
    }
}

struct SettingsRow: View {
    let symbol: String
    let title: String
    var value: String? = nil
    let route: SettingsRoute
    let id: String
    var showsDivider = true

    var body: some View {
        NavigationLink(value: route) { SettingsRowLabel(symbol: symbol, title: title, value: value, showsDivider: showsDivider) }
            .buttonStyle(.plain)
            .accessibilityIdentifier(id)
    }
}

/// A pushed Settings page: the canvas, a title in the navigation bar, scrolling content.
struct SettingsPage<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            VStack(spacing: 16) { content }
                .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 32)
        }
        .background(Theme.canvas.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }
}

struct SettingsFootnote: View {
    let text: String
    var body: some View {
        Text(text).font(Theme.caption).foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12)
            .fixedSize(horizontal: false, vertical: true)
    }
}
