import Foundation
import Observation

/// The profile fields that have an editor, one per sheet (Signal's pattern).
enum ProfileField: String, Identifiable, CaseIterable {
    case name, about, username, school
    var id: String { rawValue }
}

/// A tap-to-fill About line.
struct AboutPreset: Equatable, Identifiable {
    let emoji: String
    let text: String
    var id: String { emoji + text }

    static let all: [AboutPreset] = [
        AboutPreset(emoji: "👋", text: "Happy to help"),
        AboutPreset(emoji: "📚", text: "Planning lessons"),
        AboutPreset(emoji: "🍎", text: "In class"),
        AboutPreset(emoji: "☕", text: "Coffee lover"),
        AboutPreset(emoji: "📝", text: "Grading"),
        AboutPreset(emoji: "🔕", text: "Taking a break"),
        AboutPreset(emoji: "🔒", text: "Encrypted"),
    ]
}

/// One editor's state: the field, what it started as, what it is now, and whether ✓ may be pressed.
/// The rules: a name is required (1 to 40 characters); a username follows the web app's rules; About is
/// an optional single emoji and a few words, 140 characters in all; a school is at most 120.
@MainActor
@Observable
final class FieldEditorModel {
    let field: ProfileField
    var text: String
    var emoji: String
    var isSaving = false
    var errorMessage: String?

    private let originalText: String
    private let originalEmoji: String
    private let profile: Profile

    init(field: ProfileField, profile: Profile) {
        self.field = field
        self.profile = profile
        switch field {
        case .name: originalText = profile.displayName
        case .about: originalText = profile.aboutText ?? ""
        case .username: originalText = profile.username ?? ""
        case .school: originalText = profile.school ?? ""
        }
        originalEmoji = field == .about ? (profile.aboutEmoji ?? "") : ""
        text = originalText
        emoji = originalEmoji
    }

    // MARK: What is shown

    var title: String {
        switch field {
        case .name: "Edit Name"
        case .about: "About (\(remaining))"
        case .username: "Username"
        case .school: "School"
        }
    }

    var placeholder: String {
        switch field {
        case .name: "Your name"
        case .about: "Write a few words about yourself…"
        case .username: "username"
        case .school: "Your school"
        }
    }

    var footer: String? {
        switch field {
        case .username: "Teachers can find you with your optional username, so you don't have to give out your email."
        case .name: "Your name is visible to teachers you message."
        default: nil
        }
    }

    // MARK: Counting

    /// The characters About has used: the emoji counts as one.
    var used: Int { (trimmedEmoji.isEmpty ? 0 : 1) + trimmedText.count }
    var remaining: Int { Profile.maxAboutLength - used }

    var trimmedText: String {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return field == .username ? value.trimmingCharacters(in: CharacterSet(charactersIn: "@")) : value
    }

    var trimmedEmoji: String { emoji.trimmingCharacters(in: .whitespaces) }

    // MARK: Rules

    /// Why the field cannot be saved as it is, or nil.
    var validationMessage: String? {
        switch field {
        case .name:
            if trimmedText.isEmpty { return "Your name can't be empty." }
            if trimmedText.count > Profile.maxNameLength { return "Use at most \(Profile.maxNameLength) characters." }
        case .about:
            if trimmedEmoji.count > 1 { return "Use a single emoji." }
            if used > Profile.maxAboutLength { return "About is at most \(Profile.maxAboutLength) characters." }
        case .username:
            if !trimmedText.isEmpty { return OnboardingModel.usernameError(trimmedText) }
        case .school:
            if trimmedText.count > 120 { return "Use at most 120 characters." }
        }
        return nil
    }

    var hasChange: Bool { trimmedText != originalText.trimmingCharacters(in: .whitespacesAndNewlines) || trimmedEmoji != originalEmoji }

    /// ✓ is live only for a valid change that is not already being saved.
    var canSave: Bool { hasChange && validationMessage == nil && !isSaving }

    // MARK: Editing

    func applyPreset(_ preset: AboutPreset) {
        emoji = preset.emoji
        text = preset.text
    }

    /// An emoji picked from the keyboard replaces the leading emoji (only the last one typed counts).
    func pickEmoji(_ picked: String) {
        guard let last = picked.last else { return }
        emoji = String(last)
    }

    func clear() {
        text = ""
        if field == .about { emoji = "" }
    }

    /// The whole profile with this one field changed (the server replaces the profile).
    func draft() -> ProfileDraft {
        var draft = ProfileDraft(profile)
        switch field {
        case .name: draft.displayName = trimmedText
        case .about:
            draft.aboutEmoji = trimmedEmoji.isEmpty ? nil : trimmedEmoji
            draft.aboutText = trimmedText.isEmpty ? nil : trimmedText
        case .username: draft.username = trimmedText.isEmpty ? nil : trimmedText
        case .school: draft.school = trimmedText.isEmpty ? nil : trimmedText
        }
        return draft
    }
}
