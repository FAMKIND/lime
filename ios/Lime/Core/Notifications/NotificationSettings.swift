import Foundation
import Observation

/// What a notification shows (N2 = A: the name and the message by default; the words are decrypted
/// on this phone, never by a server).
enum NotificationPreview: String, CaseIterable, Identifiable, Sendable {
    case nameAndMessage, nameOnly, hidden

    var id: String { rawValue }
    var title: String {
        switch self {
        case .nameAndMessage: "Name and message"
        case .nameOnly: "Name only"
        case .hidden: "No preview"
        }
    }
}

/// The sound for a new message. Lime's own chime is not bundled yet: to add it, drop `lime-chime.caf`
/// into `Resources/Sounds/`, add a `limeChime` case here (default it, play it in `SystemArrivalFeedback`
/// and use `UNNotificationSound(named:)` in `SystemNotifications`). See `Resources/Sounds/README.md`.
enum NotificationSound: String, CaseIterable, Identifiable, Sendable {
    case systemDefault, none

    var id: String { rawValue }
    var title: String {
        switch self {
        case .systemDefault: "Default"
        case .none: "None"
        }
    }
}

/// How long a chat stays muted.
enum MuteDuration: String, CaseIterable, Identifiable, Sendable {
    case hour, eightHours, week, always

    var id: String { rawValue }
    var title: String {
        switch self {
        case .hour: "For 1 hour"
        case .eightHours: "For 8 hours"
        case .week: "For 1 week"
        case .always: "Always"
        }
    }

    func end(from now: Date) -> Date {
        switch self {
        case .hour: now.addingTimeInterval(3_600)
        case .eightHours: now.addingTimeInterval(8 * 3_600)
        case .week: now.addingTimeInterval(7 * 24 * 3_600)
        case .always: .distantFuture
        }
    }
}

/// This phone's notification choices, kept in the phone's own settings (they are not secret and are
/// never sent anywhere).
@MainActor
@Observable
final class NotificationSettings {
    var enabled: Bool { didSet { defaults.set(enabled, forKey: Keys.enabled) } }
    var preview: NotificationPreview { didSet { defaults.set(preview.rawValue, forKey: Keys.preview) } }
    var sound: NotificationSound { didSet { defaults.set(sound.rawValue, forKey: Keys.sound) } }
    /// "Not now" was chosen on the explainer: do not ask again by itself (Settings still offers it).
    var explainerDismissed: Bool { didSet { defaults.set(explainerDismissed, forKey: Keys.dismissed) } }
    /// Chat id to when its mute ends (`distantFuture` for always).
    private(set) var muted: [String: Date] { didSet { defaults.set(muted.mapValues(\.timeIntervalSince1970), forKey: Keys.muted) } }

    private let defaults: UserDefaults

    private enum Keys {
        static let enabled = "lime.notify.enabled"
        static let preview = "lime.notify.preview"
        static let sound = "lime.notify.sound"
        static let dismissed = "lime.notify.explainerDismissed"
        static let muted = "lime.notify.muted"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        enabled = defaults.object(forKey: Keys.enabled) as? Bool ?? true
        preview = defaults.string(forKey: Keys.preview).flatMap(NotificationPreview.init) ?? .nameAndMessage
        sound = defaults.string(forKey: Keys.sound).flatMap(NotificationSound.init) ?? .systemDefault
        explainerDismissed = defaults.bool(forKey: Keys.dismissed)
        let stored = defaults.dictionary(forKey: Keys.muted) as? [String: Double] ?? [:]
        muted = stored.mapValues { Date(timeIntervalSince1970: $0) }
    }

    func mute(_ conversationID: String, for duration: MuteDuration, now: Date = Date()) {
        muted[conversationID] = duration.end(from: now)
    }

    func unmute(_ conversationID: String) { muted[conversationID] = nil }

    func isMuted(_ conversationID: String, now: Date = Date()) -> Bool {
        guard let end = muted[conversationID] else { return false }
        return end > now
    }

    /// Chats still muted at `now`, soonest end first ("Always" last). Ended mutes are forgotten.
    func activeMutes(now: Date = Date()) -> [(conversationID: String, until: Date)] {
        muted.filter { $0.value > now }.map { ($0.key, $0.value) }.sorted { $0.until < $1.until }
    }

    /// Drops mutes that have ended.
    func pruneEndedMutes(now: Date = Date()) {
        let ended = muted.filter { $0.value <= now }.map(\.key)
        for id in ended { muted[id] = nil }
    }

    /// Forget everything (signing out).
    func reset() {
        for key in [Keys.enabled, Keys.preview, Keys.sound, Keys.dismissed, Keys.muted] { defaults.removeObject(forKey: key) }
        enabled = true; preview = .nameAndMessage; sound = .systemDefault; explainerDismissed = false; muted = [:]
    }
}
