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

/// The sound for a new message: Lime's own chime (the default), the system's, none, or one of the person's own (a file they added,
/// kept on this phone in `Library/Sounds`).
enum NotificationSound: Hashable, Identifiable, Sendable {
    case limeChime, systemDefault, none
    case custom(String)

    var id: String { rawValue }

    /// How it is stored: "limeChime", "systemDefault", "none" or "custom:<id>".
    var rawValue: String {
        switch self {
        case .limeChime: "limeChime"
        case .systemDefault: "systemDefault"
        case .none: "none"
        case .custom(let id): "custom:\(id)"
        }
    }

    init?(rawValue: String) {
        switch rawValue {
        case "limeChime": self = .limeChime
        case "systemDefault": self = .systemDefault
        case "none": self = .none
        default:
            guard rawValue.hasPrefix("custom:"), rawValue.count > 7 else { return nil }
            self = .custom(String(rawValue.dropFirst(7)))
        }
    }

    /// The built-in choices, in the order Settings lists them.
    static let builtIns: [NotificationSound] = [.limeChime, .systemDefault, .none]

    var title: String {
        switch self {
        case .limeChime: "Lime chime"
        case .systemDefault: "Default"
        case .none: "None"
        case .custom: "Your sound"
        }
    }

    /// The file notifications play: in the app bundle (the chime) or `Library/Sounds` (a custom sound). `nil` means the system's.
    var fileName: String? {
        switch self {
        case .limeChime: SoundFiles.chime
        case .custom(let id): "\(id).caf"
        case .systemDefault, .none: nil
        }
    }
}

/// The ringtone for a call: Lime's steelpan, the system's, or a custom one (used by the in-app ringing; see `CallRingtone`).
enum CallSound: Hashable, Identifiable, Sendable {
    case limeSteelpan, systemDefault
    case custom(String)

    var id: String { rawValue }
    var rawValue: String {
        switch self {
        case .limeSteelpan: "limeSteelpan"
        case .systemDefault: "systemDefault"
        case .custom(let id): "custom:\(id)"
        }
    }

    init?(rawValue: String) {
        switch rawValue {
        case "limeSteelpan": self = .limeSteelpan
        case "systemDefault": self = .systemDefault
        default:
            guard rawValue.hasPrefix("custom:"), rawValue.count > 7 else { return nil }
            self = .custom(String(rawValue.dropFirst(7)))
        }
    }

    static let builtIns: [CallSound] = [.limeSteelpan, .systemDefault]
    var title: String {
        switch self {
        case .limeSteelpan: "Lime steelpan"
        case .systemDefault: "Default"
        case .custom: "Your sound"
        }
    }
}

/// The names of the sound files in the app bundle.
enum SoundFiles {
    static let chime = "lime-chime.caf"
    static let ring = "lime-ring.caf"
}

/// What CallKit plays for an incoming call (LIME-111 passes this to `CXProviderConfiguration.ringtoneSound`). CallKit documents that
/// setting as the name of a sound in the app bundle, so a custom call sound cannot be handed to it: the custom sound plays in Lime's own
/// ringing screen, and the system call screen uses the Lime steelpan.
enum CallRingtone {
    static let callKitSoundName = SoundFiles.ring
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
    var callSound: CallSound { didSet { defaults.set(callSound.rawValue, forKey: Keys.callSound) } }
    /// "Not now" was chosen on the explainer: do not ask again by itself (Settings still offers it).
    var explainerDismissed: Bool { didSet { defaults.set(explainerDismissed, forKey: Keys.dismissed) } }
    /// Chat id to when its mute ends (`distantFuture` for always).
    private(set) var muted: [String: Date] { didSet { defaults.set(muted.mapValues(\.timeIntervalSince1970), forKey: Keys.muted) } }

    private let defaults: UserDefaults

    private enum Keys {
        static let enabled = "lime.notify.enabled"
        static let preview = "lime.notify.preview"
        static let sound = "lime.notify.sound"
        static let callSound = "lime.notify.callSound"
        static let soundMigrated = "lime.notify.soundMigrated102b"
        static let dismissed = "lime.notify.explainerDismissed"
        static let muted = "lime.notify.muted"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // One source of truth for the sound: Lime's chime unless the person chose another, whatever was or was not written before.
        defaults.register(defaults: [Keys.sound: NotificationSound.limeChime.rawValue, Keys.callSound: CallSound.limeSteelpan.rawValue])
        // Before Lime had its own chime, "Default" was the preset, so a stored "Default" was never a choice: once, it becomes the chime.
        if !defaults.bool(forKey: Keys.soundMigrated) {
            if defaults.string(forKey: Keys.sound) == NotificationSound.systemDefault.rawValue { defaults.removeObject(forKey: Keys.sound) }
            defaults.set(true, forKey: Keys.soundMigrated)
        }
        enabled = defaults.object(forKey: Keys.enabled) as? Bool ?? true
        preview = defaults.string(forKey: Keys.preview).flatMap(NotificationPreview.init) ?? .nameAndMessage
        sound = defaults.string(forKey: Keys.sound).flatMap(NotificationSound.init) ?? .limeChime
        callSound = defaults.string(forKey: Keys.callSound).flatMap(CallSound.init) ?? .limeSteelpan
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
        for key in [Keys.enabled, Keys.preview, Keys.sound, Keys.callSound, Keys.dismissed, Keys.muted, Keys.soundMigrated] { defaults.removeObject(forKey: key) }
        enabled = true; preview = .nameAndMessage; sound = .limeChime; callSound = .limeSteelpan; explainerDismissed = false; muted = [:]
    }
}
