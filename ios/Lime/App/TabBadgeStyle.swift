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
        let attributes: [NSAttributedString.Key: Any] = [.foregroundColor: text, .font: UIFont.systemFont(ofSize: 12, weight: .semibold)]
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
        let appearance = appearance()
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
}
