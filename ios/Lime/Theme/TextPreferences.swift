import CoreText
import Observation
import SwiftUI

/// lime's own text size and typeface (LIME-168), kept on this phone. By default lime follows the iPhone's text size and uses the system font.
///
/// The size is applied at the root of the app as a Dynamic Type override, so every text style (and every custom font, which is made with
/// `relativeTo:`) scales with it; the typeface is read by `Theme.font`, so the whole UI follows it.

/// The seven steps of lime's own text size, from Extra Small to the largest accessibility size. "Default" is what the iPhone calls Large.
struct TextStep: Equatable, Identifiable {
    let id: Int
    let name: String
    let size: DynamicTypeSize
    let category: UIContentSizeCategory

    static let all: [TextStep] = [
        TextStep(id: 0, name: "Extra Small", size: .xSmall, category: .extraSmall),
        TextStep(id: 1, name: "Small", size: .small, category: .small),
        TextStep(id: 2, name: "Default", size: .large, category: .large),
        TextStep(id: 3, name: "Large", size: .xLarge, category: .extraLarge),
        TextStep(id: 4, name: "Extra Large", size: .xxxLarge, category: .extraExtraExtraLarge),
        TextStep(id: 5, name: "Accessibility", size: .accessibility2, category: .accessibilityMedium),
        TextStep(id: 6, name: "Largest", size: .accessibility5, category: .accessibilityExtraExtraExtraLarge),
    ]
    static let defaultStep = 2
}

/// The typefaces on offer: the system font (SF Pro) and five open ones (SIL Open Font License; credits in Acknowledgements).
enum LimeTypeface: String, CaseIterable, Identifiable {
    case system, figtree, spaceGrotesk, atkinson, newsreader, plexMono

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .figtree: "Figtree"
        case .spaceGrotesk: "Space Grotesk"
        case .atkinson: "Atkinson Hyperlegible Next"
        case .newsreader: "Newsreader"
        case .plexMono: "IBM Plex Mono"
        }
    }

    var detail: String {
        switch self {
        case .system: "The iPhone's own font"
        case .figtree: "Clean and friendly"
        case .spaceGrotesk: "A pop of energy"
        case .atkinson: "Made for low vision"
        case .newsreader: "A serif for reading"
        case .plexMono: "Monospaced"
        }
    }

    /// The prefix of the font files (`Figtree-SemiBold`), nil for the system font.
    var fileStem: String? {
        switch self {
        case .system: nil
        case .figtree: "Figtree"
        case .spaceGrotesk: "SpaceGrotesk"
        case .atkinson: "AtkinsonHyperlegibleNext"
        case .newsreader: "Newsreader"
        case .plexMono: "IBMPlexMono"
        }
    }

    /// A text style in this typeface (the system font for `.system`).
    func font(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        guard let name = postScriptName(for: weight) else { return Font.system(style, design: .default, weight: weight) }
        return Font.custom(name, size: style.basePointSize, relativeTo: style)
    }

    /// The font file for a weight: Regular, Medium, SemiBold or Bold (the nearest one).
    func postScriptName(for weight: Font.Weight) -> String? {
        guard let stem = fileStem else { return nil }
        let style: String
        switch weight {
        case .ultraLight, .thin, .light, .regular: style = "Regular"
        case .medium: style = "Medium"
        case .semibold: style = "SemiBold"
        default: style = "Bold"
        }
        return "\(stem)-\(style)"
    }
}

@Observable
final class TextPreferences: @unchecked Sendable {
    static let shared = TextPreferences(defaults: launchDefaults())

    /// The phone's defaults, except in a UI-test launch (`-lime-skip-sign-in`, Debug): every such launch starts from a fresh, throwaway set
    /// (plus whatever `-lime.text.*` arguments say), so one test changing the size cannot leak into the next.
    private static func launchDefaults() -> UserDefaults {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-lime-skip-sign-in"), let fresh = UserDefaults(suiteName: "lime.uitest.text") {
            fresh.removePersistentDomain(forName: "lime.uitest.text")
            for key in [followKey, stepKey, fontKey] {
                if let at = arguments.firstIndex(of: "-" + key), at + 1 < arguments.count { fresh.set(arguments[at + 1], forKey: key) }
            }
            return fresh
        }
        #endif
        return .standard
    }

    static let followKey = "lime.text.follow"
    static let stepKey = "lime.text.step"
    static let fontKey = "lime.text.font"

    private let defaults: UserDefaults

    /// Called after the size or the follow switch changes (the windows take the new size).
    @ObservationIgnored var onSizeChange: (() -> Void)?

    /// Use the iPhone's text size (the default): lime changes it with the phone's setting.
    var followsSystem: Bool { didSet { defaults.set(followsSystem, forKey: Self.followKey); onSizeChange?() } }
    /// The step when lime has its own size (0...6; a value outside is kept inside). Written by hand, not by the observation macro, because a
    /// `didSet` that assigns to the property itself would loop under it.
    @ObservationIgnored private var storedStep: Int
    var step: Int {
        get { access(keyPath: \.step); return storedStep }
        set {
            withMutation(keyPath: \.step) {
                storedStep = min(max(newValue, 0), TextStep.all.count - 1)
                defaults.set(storedStep, forKey: Self.stepKey)
            }
            onSizeChange?()
        }
    }
    var typeface: LimeTypeface { didSet { defaults.set(typeface.rawValue, forKey: Self.fontKey) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // A Debug build can start with `-lime.text.follow NO -lime.text.step 6 -lime.text.font figtree`: launch arguments arrive as text.
        followsSystem = Self.bool(defaults.object(forKey: Self.followKey)) ?? true
        let stored = Self.int(defaults.object(forKey: Self.stepKey)) ?? TextStep.defaultStep
        storedStep = min(max(stored, 0), TextStep.all.count - 1)
        typeface = defaults.string(forKey: Self.fontKey).flatMap(LimeTypeface.init(rawValue:)) ?? .system
    }

    private static func bool(_ value: Any?) -> Bool? {
        if let bool = value as? Bool { return bool }
        switch (value as? String)?.lowercased() {
        case "yes", "true", "1": return true
        case "no", "false", "0": return false
        default: return nil
        }
    }

    private static func int(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        return (value as? String).flatMap { Int($0) }
    }

    var currentStep: TextStep { TextStep.all[step] }

    /// The Dynamic Type size lime forces, or nil to follow the phone.
    var override: DynamicTypeSize? { followsSystem ? nil : currentStep.size }

    /// For UIKit text (the composer): the content size category lime forces, or nil to follow the phone.
    var overrideCategory: UIContentSizeCategory? { followsSystem ? nil : currentStep.category }
}

/// Puts lime's own text size on every window of the app. A SwiftUI sheet does not inherit a Dynamic Type override from the view that presents it,
/// and UIKit (the composer, alerts, the tab bar) never sees one; the window's trait override reaches all of them, sheets included.
@MainActor
enum WindowTextSize {
    static func apply() {
        let category = TextPreferences.shared.overrideCategory
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                if let category {
                    window.traitOverrides.preferredContentSizeCategory = category
                } else {
                    window.traitOverrides.remove(UITraitPreferredContentSizeCategory.self)
                }
            }
        }
    }

    /// Follows the preferences from now on (called once at launch, and again when a window appears).
    static func start() {
        TextPreferences.shared.onSizeChange = { Task { @MainActor in apply() } }
        apply()
    }
}

/// Registers the bundled typefaces with the system (once, at launch), so `Font.custom` finds them by name.
enum FontRegistrar {
    nonisolated(unsafe) private static var registered = false   // called once on the main thread at launch (and from tests)

    static func registerAll() {
        guard !registered else { return }
        registered = true
        let urls = (Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? [])
        guard !urls.isEmpty else { return }
        CTFontManagerRegisterFontURLs(urls as CFArray, .process, true, nil)
    }
}

extension Font.TextStyle {
    /// The point size of the style at the default text size (what `relativeTo:` scales from).
    var basePointSize: CGFloat {
        switch self {
        case .extraLargeTitle: 36
        case .extraLargeTitle2: 28
        case .largeTitle: 34
        case .title: 28
        case .title2: 22
        case .title3: 20
        case .headline, .body: 17
        case .callout: 16
        case .subheadline: 15
        case .footnote: 13
        case .caption: 12
        case .caption2: 11
        @unknown default: 17
        }
    }
}

/// Applies lime's own text size at the root and keeps the system's when it follows the phone (the environment is rewritten, not the view's
/// identity, so switching never rebuilds the screens).
struct LimeTextSize: ViewModifier {
    func body(content: Content) -> some View {
        let override = TextPreferences.shared.override
        content.transformEnvironment(\.dynamicTypeSize) { size in
            if let override { size = override }
        }
    }
}

extension View {
    func limeTextSize() -> some View { modifier(LimeTextSize()) }
}
