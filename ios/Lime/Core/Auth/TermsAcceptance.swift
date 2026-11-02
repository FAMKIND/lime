import Foundation

/// What a teacher agreed to at sign-up (LIME-283): the terms version and the date, kept on this phone only.
/// Nothing about it is sent anywhere.
enum TermsAcceptance {
    /// Change this when the terms change in a way people must agree to again.
    static let currentVersion = "terms-2026-11"
    static let termsURL = "https://limemessenger.com/terms"
    static let privacyURL = "https://limemessenger.com/privacy"
    static let guidelinesURL = "https://limemessenger.com/guidelines"
    static let safetyURL = "https://limemessenger.com/safety"

    private static let versionKey = "lime.terms.version"
    private static let dateKey = "lime.terms.date"

    static func record(defaults: UserDefaults = .standard, now: Date = Date()) {
        defaults.set(currentVersion, forKey: versionKey)
        defaults.set(now, forKey: dateKey)
    }

    /// The version this phone agreed to, if any.
    static func accepted(defaults: UserDefaults = .standard) -> String? { defaults.string(forKey: versionKey) }

    /// True only when someone agreed to an older version: phones with no record (accounts from before this) are not asked.
    static func needsReagreement(defaults: UserDefaults = .standard) -> Bool {
        guard let version = accepted(defaults: defaults) else { return false }
        return version != currentVersion
    }
}
