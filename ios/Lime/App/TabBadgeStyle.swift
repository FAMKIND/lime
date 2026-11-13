import SwiftUI
import UIKit

/// Tab bar badges in lime's green with dark digits, like the row badges (not the system red).
enum TabBadgeStyle {
    static var background: UIColor { UIColor(Theme.accent) }
    static var text: UIColor { UIColor(Theme.accentInk) }

    /// The standard tab bar appearance with only the badge colours changed.
    @MainActor static func appearance() -> UITabBarAppearance {
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        let attributes: [NSAttributedString.Key: Any] = [.foregroundColor: text, .font: UIFontMetrics(forTextStyle: .caption1).scaledFont(for: .systemFont(ofSize: 12, weight: .semibold))]   // follows the text size (LIME-326)
        for layout in [appearance.stackedLayoutAppearance, appearance.inlineLayoutAppearance, appearance.compactInlineLayoutAppearance] {
            for state in [layout.normal, layout.selected] {
                state.badgeBackgroundColor = background
                state.badgeTextAttributes = attributes
            }
        }
        return appearance
    }

    /// Applied once at launch to every tab bar the SwiftUI `TabView` makes.
    @MainActor static func install() {
        apply()
        // A text-size change while the app runs rebuilds the badge font and puts it on the bars already on screen (LIME-327).
        NotificationCenter.default.addObserver(forName: UIContentSizeCategory.didChangeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { apply(toVisibleBars: true) }
        }
    }

    @MainActor private static func apply(toVisibleBars live: Bool = false) {
        let appearance = appearance()
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
        guard live else { return }
        func bars(in view: UIView) -> [UITabBar] { ((view as? UITabBar).map { [$0] } ?? []) + view.subviews.flatMap(bars(in:)) }
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows {
                for bar in bars(in: window) { bar.standardAppearance = appearance; bar.scrollEdgeAppearance = appearance }
            }
        }
    }
}
