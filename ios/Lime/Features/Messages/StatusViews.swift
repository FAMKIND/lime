import SwiftUI

/// The status icon in a cut-out notch at an avatar's bottom-right: a green dot (available), a yellow moon (away), or a red badge
/// with a "z" (do not disturb). Nothing for a contact who has not shared one.
struct StatusBadge: View {
    let state: UserStatus
    var size: CGFloat = 16

    var body: some View {
        ZStack {
            // The notch: the page colour around the icon, so it reads as cut out of the avatar.
            Circle().fill(Theme.canvas).frame(width: size + 4, height: size + 4)
            switch state {
            case .available:
                Circle().fill(Color(red: 0.20, green: 0.72, blue: 0.36)).frame(width: size - 2, height: size - 2)
            case .away:
                // A solid disc with the moon on it, like the other two, so it reads the same on any background.
                Circle().fill(Color(red: 0.96, green: 0.70, blue: 0.10)).frame(width: size - 1, height: size - 1)
                    .overlay(Image(systemName: "moon.fill").font(.system(size: size * 0.5, weight: .bold)).foregroundStyle(.white))
            case .dnd:
                Circle().fill(Color(red: 0.88, green: 0.28, blue: 0.30)).frame(width: size - 1, height: size - 1)
                    .overlay(Text("z").font(.system(size: size * 0.72, weight: .black, design: .rounded)).foregroundStyle(.white).offset(y: -0.5))
            }
        }
        .frame(width: size + 4, height: size + 4)
        .accessibilityHidden(true)
    }
}

extension View {
    /// Puts a person's status badge on their avatar (nothing when they have none).
    func statusBadge(_ userID: String?, size: CGFloat) -> some View { modifier(StatusBadgeModifier(userID: userID, avatarSize: size)) }
}

private struct StatusBadgeModifier: ViewModifier {
    let userID: String?
    let avatarSize: CGFloat
    @Environment(ConversationStore.self) private var store

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottomTrailing) {
            if let userID, let status = store.status(of: userID) {
                StatusBadge(state: status.state, size: max(12, min(avatarSize * 0.32, 18)))
                    .offset(x: 3, y: 3)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(status.state.title)
                    .accessibilityIdentifier("status-badge-\(userID)")
            }
        }
    }
}

/// Tap your own avatar: set your status, quiet for a while, or open Work hours and Settings.
struct StatusSheet: View {
    var openSettings: () -> Void
    @Environment(ConversationStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var settings = StatusSettings.shared
    @State private var customUntil = Calendar.current.date(byAdding: .hour, value: 2, to: Date()) ?? Date()
    @State private var choosingTime = false
    @State private var showHours = false

    private var current: UserStatus { settings.plan().state }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Text("Your status").font(.system(.title3, design: .default, weight: .bold)).foregroundStyle(Theme.text).padding(.top, 16)
                    Text("Only people you chat with can see it. There is no last seen.").font(Theme.secondary).foregroundStyle(Theme.textSecondary)
                    SettingsCard {
                        ForEach(UserStatus.allCases) { status in
                            row(status.title, selected: current == status, id: "status-\(status.rawValue)", badge: status) { set(status, until: nil) }
                        }
                    }
                    SettingsFootnote(text: "Quiet until…")
                    SettingsCard {
                        row("1 hour", selected: false, id: "status-quiet-1h") { set(.dnd, until: Date().addingTimeInterval(3600)) }
                        row("Until tomorrow 7:00", selected: false, id: "status-quiet-tomorrow") { set(.dnd, until: Self.tomorrowSeven()) }
                        row("Choose a time…", selected: false, id: "status-quiet-custom") { choosingTime.toggle() }
                        if choosingTime {
                            DatePicker("Until", selection: $customUntil, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                                .datePickerStyle(.compact).padding(.horizontal, 18).frame(minHeight: 54)
                            row("Set", selected: false, id: "status-quiet-set") { set(.dnd, until: customUntil) }
                        }
                    }
                    if settings.manual != nil {
                        Button { settings.manual = nil; changed() } label: {
                            Text("Back to automatic").font(Theme.body).foregroundStyle(Theme.text).frame(maxWidth: .infinity, minHeight: 50)
                        }
                        .accessibilityIdentifier("status-automatic")
                    }
                    SettingsCard {
                        Button { showHours = true } label: {
                            SettingsRowLabel(symbol: "clock", title: "Work hours", value: settings.hours.enabled ? "On" : "Off")
                        }
                        .buttonStyle(.plain).accessibilityIdentifier("status-work-hours")
                        Button { dismiss(); openSettings() } label: {
                            SettingsRowLabel(symbol: "gearshape", title: "Settings", showsDivider: false)
                        }
                        .buttonStyle(.plain).accessibilityIdentifier("status-open-settings")
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 32)
            }
            .background(Theme.canvas.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showHours) { WorkHoursScreen() }
        }
        .tint(Theme.text)
        .presentationDetents([.large])
        .presentationBackground(Theme.canvas)
        .accessibilityIdentifier("status-sheet")
    }

    private func row(_ title: String, selected: Bool, id: String, badge: UserStatus? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if let badge { StatusBadge(state: badge, size: 18) }
                Text(title).font(Theme.body).foregroundStyle(Theme.text)
                Spacer()
                if selected { Image(systemName: "checkmark").font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.text) }
            }
            .padding(.horizontal, 18).frame(minHeight: 54).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func set(_ status: UserStatus, until: Date?) {
        settings.manual = ManualStatus(state: status, until: until)
        changed()
        dismiss()
    }

    private func changed() { Task { await store.statusSettingsChanged() } }

    static func tomorrowSeven(now: Date = Date(), calendar: Calendar = .current) -> Date {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        return calendar.date(byAdding: .hour, value: 7, to: tomorrow) ?? tomorrow
    }
}

/// Settings → Work hours: a weekly schedule. Outside it you are in Do not disturb and notifications are held.
struct WorkHoursScreen: View {
    @Environment(ConversationStore.self) private var store
    @State private var settings = StatusSettings.shared
    private let letters = ["S", "M", "T", "W", "T", "F", "S"]

    var body: some View {
        SettingsPage(title: "Work hours") {
            SettingsCard {
                Toggle(isOn: Binding(get: { settings.hours.enabled }, set: { settings.hours.enabled = $0; changed() })) {
                    Text("Use work hours").font(Theme.body).foregroundStyle(Theme.text)
                }
                .tint(Theme.accent).padding(.horizontal, 18).frame(minHeight: 58)
                .accessibilityIdentifier("hours-toggle")
            }
            SettingsFootnote(text: "Outside these hours you are in Do not disturb: new messages arrive silently, and you get a summary when work hours start. Your contacts see “Quiet hours until …”.")
            if settings.hours.enabled {
                SettingsCard {
                    HStack(spacing: 8) {
                        ForEach(1...7, id: \.self) { weekday in
                            let on = settings.hours.days.contains(weekday)
                            Button {
                                if on { settings.hours.days.remove(weekday) } else { settings.hours.days.insert(weekday) }
                                changed()
                            } label: {
                                Text(letters[weekday - 1]).font(Theme.body.weight(.semibold))
                                    .foregroundStyle(on ? Theme.accentInk : Theme.text)
                                    .frame(width: 38, height: 38).background(on ? Theme.accent : Theme.pressed, in: Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Calendar.current.weekdaySymbols[weekday - 1]).accessibilityAddTraits(on ? [.isSelected] : [])
                            .accessibilityIdentifier("hours-day-\(weekday)")
                        }
                    }
                    .padding(.horizontal, 14).frame(minHeight: 64)
                    DatePicker("Start", selection: time(\.start), displayedComponents: .hourAndMinute)
                        .padding(.horizontal, 18).frame(minHeight: 54).accessibilityIdentifier("hours-start")
                    DatePicker("End", selection: time(\.end), displayedComponents: .hourAndMinute)
                        .padding(.horizontal, 18).frame(minHeight: 54).accessibilityIdentifier("hours-end")
                }
            }
        }
        .accessibilityIdentifier("work-hours-screen")
    }

    private func time(_ key: WritableKeyPath<WorkHours, Int>) -> Binding<Date> {
        Binding(
            get: { Calendar.current.date(byAdding: .minute, value: settings.hours[keyPath: key], to: Calendar.current.startOfDay(for: Date())) ?? Date() },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                settings.hours[keyPath: key] = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
                changed()
            }
        )
    }

    private func changed() { Task { await store.statusSettingsChanged() } }
}
