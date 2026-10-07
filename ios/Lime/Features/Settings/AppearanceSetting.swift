import SwiftUI

/// Settings, Customize, Appearance: follow the phone, or always light, or always dark. Stored on this
/// phone only and applied to the whole app.
enum AppearanceSetting: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    /// The UserDefaults key (a Debug build can start in a mode with `-lime.appearance dark`).
    static let storageKey = "lime.appearance"

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var symbol: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }

    /// What is stored (anything unknown means "follow the phone").
    static func stored(in defaults: UserDefaults = .standard) -> AppearanceSetting {
        defaults.string(forKey: storageKey).flatMap(AppearanceSetting.init(rawValue:)) ?? .system
    }

    func save(in defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.storageKey)
    }
}

/// The donate link, when one is configured (`LIME_DONATE_URL` when the project is generated). With none,
/// Settings hides the row.
enum DonateLink {
    /// Only a secure web address counts.
    static func url(from string: String?) -> URL? {
        guard let string = string?.trimmingCharacters(in: .whitespaces), !string.isEmpty,
              let url = URL(string: string), url.scheme?.lowercased() == "https", url.host?.isEmpty == false else { return nil }
        return url
    }

    static var current: URL? {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-lime-donate-url"), index + 1 < arguments.count {
            return url(from: arguments[index + 1])
        }
        #endif
        return url(from: GeneratedBackend.donateURL)
    }
}
