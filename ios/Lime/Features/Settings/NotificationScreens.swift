import SwiftUI
import UIKit

/// Settings → Notifications: on or off, what a notification shows, its sound, and muted chats.
struct NotificationsScreen: View {
    @Environment(ConversationStore.self) private var store
    @Environment(NotificationCoordinator.self) private var notifications
    @State private var explaining = false
    @State private var sounds = CustomSounds.shared
    @State private var adding: CustomSounds.Kind?
    @State private var renaming: CustomSounds.Item?
    @State private var renameText = ""

    var body: some View {
        @Bindable var settings = notifications.settings
        SettingsPage(title: "Notifications") {
            permissionCard
            SettingsCard {
                Toggle(isOn: $settings.enabled) {
                    Text("Message notifications").font(Theme.body).foregroundStyle(Theme.text)
                }
                .tint(Theme.accent)
                .padding(.horizontal, 18).frame(minHeight: 58)
                .accessibilityIdentifier("notif-toggle")
            }
            SettingsFootnote(text: "Calls ring only while Lime is open or was just open, until push calls arrive. Outside work hours or in Do Not Disturb, a call is a missed call.")
            if settings.enabled {
                SettingsFootnote(text: "Preview")
                SettingsCard {
                    ForEach(NotificationPreview.allCases) { option in
                        choice(option.title, selected: settings.preview == option, id: "preview-\(option.rawValue)", last: option == NotificationPreview.allCases.last) {
                            settings.preview = option
                        }
                    }
                }
                SettingsFootnote(text: "Messages are decrypted on this iPhone, so a preview never passes through a server. A message request never shows its words.")
                SettingsFootnote(text: "Message sound")
                SettingsCard {
                    ForEach(NotificationSound.builtIns) { option in
                        choice(option.title, selected: settings.sound == option, id: "sound-\(option.rawValue)", last: false) {
                            settings.sound = option
                            SoundPreview.shared.play(messageSound: option)
                        }
                    }
                    ForEach(sounds.items(of: .message)) { item in
                        choice(item.name, selected: settings.sound == .custom(item.id), id: "sound-custom-\(item.id)", last: false) {
                            settings.sound = .custom(item.id)
                            SoundPreview.shared.play(messageSound: .custom(item.id))
                        }
                        .contextMenu { customMenu(item) }
                    }
                    choice("Add your own…", selected: false, id: "sound-add-message", last: true) { adding = .message }
                }
                SettingsFootnote(text: "Call sound")
                SettingsCard {
                    ForEach(CallSound.builtIns) { option in
                        choice(option.title, selected: settings.callSound == option, id: "callsound-\(option.rawValue)", last: false) { settings.callSound = option }
                    }
                    ForEach(sounds.items(of: .call)) { item in
                        choice(item.name, selected: settings.callSound == .custom(item.id), id: "callsound-custom-\(item.id)", last: false) { settings.callSound = .custom(item.id) }
                            .contextMenu { customMenu(item) }
                    }
                    choice("Add your own…", selected: false, id: "sound-add-call", last: true) { adding = .call }
                }
                SettingsFootnote(text: "Your own sounds stay on this iPhone: they are not uploaded or synced. Press and hold one to rename or delete it. Up to \(CustomSounds.limit).")
                SettingsFootnote(text: "Muted chats")
                mutedChats
            }
            SettingsFootnote(text: "Lime has no push service yet, so alerts arrive while Lime is open, or for a short while after you leave it.")
        }
        .task { await notifications.refreshAuthorization() }
        .sheet(isPresented: $explaining) { NotificationExplainerSheet() }
        .sheet(item: $adding) { kind in AddSoundSheet(kind: kind) }
        .alert("Rename sound", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $renameText)
            Button("Save") { if let item = renaming { sounds.rename(item.id, to: renameText) }; renaming = nil }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
    }

    @ViewBuilder
    private func customMenu(_ item: CustomSounds.Item) -> some View {
        Button { renameText = item.name; renaming = item } label: { Label("Rename", systemImage: "pencil") }
        Button(role: .destructive) {
            if notifications.settings.sound == .custom(item.id) { notifications.settings.sound = .limeChime }
            if notifications.settings.callSound == .custom(item.id) { notifications.settings.callSound = .limeSteelpan }
            sounds.delete(item.id)
        } label: { Label("Delete", systemImage: "trash") }
    }

    /// What iOS allows: ask (explainer first), or send the person to iOS Settings when it was refused.
    @ViewBuilder
    private var permissionCard: some View {
        switch notifications.authorization {
        case .authorized: EmptyView()
        case .notDetermined:
            SettingsCard {
                Button { explaining = true } label: {
                    SettingsRowLabel(symbol: "bell.badge", title: "Allow notifications", showsDivider: false)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("notif-allow")
            }
        case .denied:
            SettingsCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Notifications are off for Lime in iOS Settings.").font(Theme.body).foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("notif-denied")
                    Button("Open iOS Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                    .font(Theme.secondary.weight(.semibold)).foregroundStyle(Theme.text)
                    .accessibilityIdentifier("notif-open-settings")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
            }
        }
    }

    private func choice(_ title: String, selected: Bool, id: String, last: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 0) {
                HStack {
                    Text(title).font(Theme.body).foregroundStyle(Theme.text)
                    Spacer()
                    if selected { Image(systemName: "checkmark").font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.text) }
                }
                .padding(.horizontal, 18).frame(minHeight: 54)
                if !last { Divider().overlay(Theme.hairline).padding(.leading, 18) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    @ViewBuilder
    private var mutedChats: some View {
        let muted = notifications.settings.activeMutes()
        SettingsCard {
            if muted.isEmpty {
                Text("No muted chats. Mute a chat from its ⋯ menu.").font(Theme.secondary).foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(18)
                    .accessibilityIdentifier("notif-no-muted")
            } else {
                ForEach(Array(muted.enumerated()), id: \.element.conversationID) { index, entry in
                    VStack(spacing: 0) {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(store.conversation(entry.conversationID)?.title ?? "Chat").font(Theme.body).foregroundStyle(Theme.text)
                                Text(MuteText.until(entry.until)).font(Theme.caption).foregroundStyle(Theme.textSecondary)
                            }
                            Spacer()
                            Button("Unmute") { notifications.settings.unmute(entry.conversationID) }
                                .font(Theme.secondary.weight(.semibold)).foregroundStyle(Theme.text)
                                .accessibilityIdentifier("unmute-\(entry.conversationID)")
                        }
                        .padding(.horizontal, 18).frame(minHeight: 58)
                        if index < muted.count - 1 { Divider().overlay(Theme.hairline).padding(.leading, 18) }
                    }
                }
            }
        }
    }
}

enum MuteText {
    /// "Muted until 3:40 PM", "Muted until Oct 14" or "Muted always".
    static func until(_ date: Date, now: Date = Date()) -> String {
        if date == .distantFuture { return "Muted always" }
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) { return "Muted until \(date.formatted(date: .omitted, time: .shortened))" }
        return "Muted until \(date.formatted(.dateTime.month(.abbreviated).day()))"
    }
}

/// Why Lime asks, before the system's own prompt. "Not now" is respected: it is not asked again by itself.
struct NotificationExplainerSheet: View {
    @Environment(NotificationCoordinator.self) private var notifications
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "bell.badge").font(.system(size: 34)).foregroundStyle(Theme.text)
            Text("Know when a teacher writes").font(.system(.title2, design: .default, weight: .bold)).foregroundStyle(Theme.text)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 10) {
                Text("Lime can alert you to new messages. Messages are decrypted on this iPhone, so what an alert says never passes through a server.")
                Text("You choose what an alert shows, its sound, and which chats to mute, in Settings.")
            }
            .font(Theme.body).foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button {
                Task { await notifications.requestAuthorization(); dismiss() }
            } label: {
                Text("Turn on notifications").font(Theme.title).foregroundStyle(Theme.accentInk)
                    .frame(maxWidth: .infinity, minHeight: 52).background(Theme.accent, in: Capsule())
            }
            .accessibilityIdentifier("explainer-allow")
            Button {
                notifications.settings.explainerDismissed = true
                dismiss()
            } label: {
                Text("Not now").font(Theme.title).foregroundStyle(Theme.text).frame(maxWidth: .infinity, minHeight: 48)
            }
            .accessibilityIdentifier("explainer-not-now")
        }
        .padding(24)
        .background(Theme.canvas.ignoresSafeArea())
        .presentationDetents([.medium])
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("notification-explainer")
    }
}
