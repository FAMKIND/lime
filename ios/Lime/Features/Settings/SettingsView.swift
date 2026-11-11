import SwiftUI

/// Where Settings can go.
enum SettingsRoute: Hashable {
    case account, privacy, blocked, keys, devices, notifications, calls, customize, appearance, appIcon, textSize, about, acknowledgements, changePassword, moveToNewPhone, myQR, photo, storage, myGIFs, workHours, emergency, links, background, moderation, deleteAccount
    case chatMedia(String)
}

/// The words shown before signing out (here and in Account).
enum SignOutCopy {
    static let warning = "Your chats stay on this device, locked, until you sign in again."
    /// "Remove everything from this device": the red, separate choice.
    static let removeTitle = "Remove everything from this device"
    static let removeWarning = "Your chats, files and keys on this device are deleted. This can't be undone."
}

/// Settings (design 05): a sheet with a glass ✕, the profile card, and grouped rows.
struct SettingsView: View {
    @Environment(AccountSession.self) private var session
    @Environment(ConversationStore.self) private var store
    @Environment(NotificationCoordinator.self) private var notifications
    @Environment(\.dismiss) private var dismiss
    @State private var path: [SettingsRoute]
    @State private var confirmingSignOut = false
    @State private var confirmingRemoval = false
    /// On the server's moderator list (LIME-191): the Moderation row shows for them only.
    @State private var isModerator = false
    /// Open straight on this screen (the profile's Edit profile).
    init(startAt: SettingsRoute? = nil) {
        _path = State(initialValue: startAt.map { [$0] } ?? [])
    }

    var body: some View {
        NavigationStack(path: $path) {
            root
                .task { isModerator = await store.isModerator() }
                .navigationDestination(for: SettingsRoute.self) { route in
                    switch route {
                    case .account: AccountScreen(onClose: { dismiss() })
                    case .privacy: PrivacyScreen()
                    case .blocked: BlockedScreen()
                    case .keys: KeysScreen()
                    case .devices: LinkedDevicesScreen()
                    case .notifications: NotificationsScreen()
                    case .calls: CallSettingsScreen()
                    case .customize: CustomizeScreen()
                    case .appearance: AppearanceScreen()
                    case .appIcon: AppIconScreen()
                    case .textSize: TextSizeScreen()
                    case .about: AboutScreen()
                    case .acknowledgements: AcknowledgementsScreen()
                    case .changePassword: ChangePasswordScreen()
                    case .moveToNewPhone: MoveOldPhoneScreen()
                    case .myQR: MyQRScreen()
                    case .photo: ProfilePhotoScreen()
                    case .links: LinksScreen()
                    case .background: BackgroundScreen()
                    case .storage: StorageScreen()
                    case .myGIFs: MyGIFsSettingsScreen()
                    case .workHours: WorkHoursScreen()
                    case .emergency: EmergencySettingsScreen()
                    case .moderation: ModerationScreen()
                    case .deleteAccount: DeleteAccountScreen(onClose: { dismiss() })
                    case .chatMedia(let id): ChatMediaScreen(conversationID: id)
                    }
                }
        }
        .tint(Theme.text)
        .limeBackground()
        #if DEBUG
        .task { if !store.demoSettingsRoute.isEmpty { path = Self.route(from: store.demoSettingsRoute) } }
        #endif
    }

    #if DEBUG
    /// Debug demo: open straight to a screen for screenshots ("profile", "privacy", "blocked", ...).
    static func route(from names: [String]) -> [SettingsRoute] {
        let table: [String: SettingsRoute] = [
            "account": .account, "privacy": .privacy, "blocked": .blocked, "keys": .keys, "devices": .devices,
            "notifications": .notifications, "customize": .customize, "appearance": .appearance, "app-icon": .appIcon, "text-size": .textSize, "calls": .calls, "about": .about, "ack": .acknowledgements, "password": .changePassword, "move-old": .moveToNewPhone, "my-qr": .myQR, "photo": .photo, "links": .links, "background": .background, "background-set": .background, "crop": .photo, "storage": .storage, "my-gifs": .myGIFs, "work-hours": .workHours, "moderation": .moderation, "delete-account": .deleteAccount,
        ]
        return names.compactMap { table[$0] }
    }
    #endif

    private var root: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                // Your profile edits in place now (LIME-225): the card closes Settings and turns your profile into its editor.
                Button { store.beginProfileEdit(); dismiss() } label: { profileCard }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings-profile")
                SettingsCard {
                    SettingsRow(symbol: "person.crop.circle", title: "Account", route: .account, id: "settings-account")
                    SettingsRow(symbol: "hand.raised", title: "Privacy", route: .privacy, id: "settings-privacy")
                    #if DEBUG
                    SettingsRow(symbol: "exclamationmark.triangle", title: "Emergency", route: .emergency, id: "settings-emergency")
                    #endif
                    SettingsRow(symbol: "internaldrive", title: "Storage", route: .storage, id: "settings-storage")
                    SettingsRow(symbol: "photo.on.rectangle.angled", title: "My GIFs", route: .myGIFs, id: "settings-my-gifs")
                    SettingsRow(symbol: "iphone", title: "Linked Devices", route: .devices, id: "settings-devices")
                    if let donate = DonateLink.current {
                        Link(destination: donate) {
                            SettingsRowLabel(symbol: "heart", title: "Donate to lime", showsDivider: false)
                        }
                        .accessibilityHint("Opens in your browser")
                        .accessibilityIdentifier("settings-donate")
                    }
                }
                SettingsCard {
                    SettingsRow(symbol: "bell", title: "Notifications", value: notifications.settings.enabled ? "On" : "Off",
                                route: .notifications, id: "settings-notifications")
                    SettingsRow(symbol: "clock", title: "Work hours", value: StatusSettings.shared.hours.enabled ? "On" : "Off", route: .workHours, id: "settings-work-hours")
                    SettingsRow(symbol: "phone", title: "Calls", route: .calls, id: "settings-calls")
                    SettingsRow(symbol: "paintpalette", title: "Customize", route: .customize, id: "settings-customize", showsDivider: false)
                }
                if isModerator {
                    SettingsCard { SettingsRow(symbol: "shield", title: "Moderation", route: .moderation, id: "settings-moderation", showsDivider: false) }
                }
                SettingsCard {
                    SettingsRow(symbol: "info.circle", title: "About", route: .about, id: "settings-about", showsDivider: false)
                }
                // Sign out is easy to find here as well as in Account; it says honestly what it does to this phone's keys.
                SettingsCard {
                    Button { confirmingSignOut = true } label: {
                        SettingsRowLabel(symbol: "rectangle.portrait.and.arrow.right", title: "Sign out", showsDivider: false)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings-sign-out")
                    Divider().overlay(Theme.hairline).padding(.leading, 60)
                    Button { confirmingRemoval = true } label: {
                        SettingsRowLabel(symbol: "trash", title: SignOutCopy.removeTitle, showsDivider: false, destructive: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings-remove-everything")
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .limeBackground()
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityIdentifier("settings-root")
        .confirmSheet("Sign out of lime?", isPresented: $confirmingSignOut) {
            Button("Sign out") {
                dismiss()
                Task { await session.signOut() }
            }
            .accessibilityIdentifier("settings-sign-out-confirm")
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(SignOutCopy.warning)
        }
        .confirmSheet(SignOutCopy.removeTitle + "?", isPresented: $confirmingRemoval) {
            Button("Remove everything", role: .destructive) {
                dismiss()
                Task { await session.signOut(removingData: true) }
            }
            .accessibilityIdentifier("settings-remove-everything-confirm")
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(SignOutCopy.removeWarning)
        }
    }

    private var header: some View {
        ZStack {
            Text("Settings").font(Theme.font(.title3, weight: .bold)).foregroundStyle(Theme.text)
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
            Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.textSecondary).accessibilityHidden(true)
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
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: symbol).font(.system(size: 20)).frame(width: 28).accessibilityHidden(true)
                    .foregroundStyle(destructive ? Theme.danger : Theme.text)
                // At accessibility sizes the value goes under the title and wraps; at other sizes it sits beside it on one line (LIME-130-5a).
                let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2)) : AnyLayout(HStackLayout(spacing: 8))
                layout {
                    Text(title).font(Theme.body).foregroundStyle(destructive ? Theme.danger : Theme.text)
                        .fixedSize(horizontal: false, vertical: typeSize.isAccessibilitySize)
                    if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
                    if let value {
                        Text(value).font(Theme.secondary).foregroundStyle(Theme.textSecondary)
                            .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                            .fixedSize(horizontal: false, vertical: typeSize.isAccessibilitySize)
                    }
                }
                if typeSize.isAccessibilitySize { Spacer(minLength: 0) }
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textSecondary.opacity(0.7))
                    .opacity(destructive ? 0 : 1).accessibilityHidden(true)
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
    /// False on a page whose own content names it (a group's details, under its three header circles): the bar shows no title to squeeze to "…" (LIME-250).
    var showsTitle = true
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            VStack(spacing: 16) { content }
                .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 32)
        }
        .limeBackground()
        .navigationTitle(showsTitle ? title : "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .limeBack()
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
