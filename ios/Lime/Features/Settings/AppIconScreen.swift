import SwiftUI
import UIKit

/// The icons a person can choose for lime on the Home Screen (LIME-292b): lime's own and seven playful ones, all the lime logo. The choice is local to this
/// phone (iOS keeps it), never sent. Each is an `AppIcon-<Title>` set in the asset catalog; lime's own is `AppIcon` (iOS calls it `nil`).
enum AppIconChoice: String, CaseIterable, Identifiable {
    case lime, dark, minimal, pixel, rainbow, notebook, chalkboard, apple

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lime: "lime"
        case .dark: "Dark"
        case .minimal: "Minimal"
        case .pixel: "Pixel"
        case .rainbow: "Rainbow"
        case .notebook: "Notebook"
        case .chalkboard: "Chalkboard"
        case .apple: "Apple"
        }
    }

    /// What `setAlternateIconName` takes: nil is the primary icon.
    var iconName: String? { self == .lime ? nil : "AppIcon-\(title)" }
    var preview: String { "IconPreview-\(rawValue.prefix(1).uppercased())\(rawValue.dropFirst())" }
    var spokenName: String { "\(title) app icon" }

    static func choice(forIconName name: String?) -> AppIconChoice { allCases.first { $0.iconName == name } ?? .lime }

    /// Four columns; three then two at accessibility text sizes, so the icons grow and never shrink under 60 pt.
    static func columns(for size: DynamicTypeSize) -> Int {
        guard size.isAccessibilitySize else { return 4 }
        return size >= .accessibility3 ? 2 : 3
    }

    static let footer = "The name \u{201C}lime\u{201D} stays the same on your Home Screen and in notifications."
}

/// Settings → Customize → App icon: a grid in one card, icons only (the names are for VoiceOver), a ring in lime's green round the one in use.
struct AppIconScreen: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var current = AppIconChoice.choice(forIconName: UIApplication.shared.alternateIconName)
    @State private var problem: String?

    var body: some View {
        let columns = AppIconChoice.columns(for: typeSize)
        let size: CGFloat = columns == 4 ? 64 : (columns == 3 ? 72 : 88)
        SettingsPage(title: "App icon") {
            SettingsCard {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: columns), spacing: 18) {
                    ForEach(AppIconChoice.allCases) { choice in
                        Button { pick(choice) } label: { cell(choice, size: size) }
                            .buttonStyle(.plain)
                            .accessibilityLabel(choice.spokenName)
                            .accessibilityAddTraits(choice == current ? [.isSelected] : [])
                            .accessibilityIdentifier("app-icon-\(choice.rawValue)")
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 18)
            }
            SettingsFootnote(text: AppIconChoice.footer)
            if let problem {
                Text(problem).font(Theme.secondary).foregroundStyle(Theme.danger).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12)
                    .announcesWhenShown(problem).accessibilityIdentifier("app-icon-problem")
            }
        }
    }

    /// The ring: lime's green (nudged just enough to keep 3:1 against the card, which a theme can change), a small gap, then the icon.
    private func cell(_ choice: AppIconChoice, size: CGFloat) -> some View {
        let radius = size * 0.2237
        return Image(choice.preview).resizable().interpolation(.high).scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 0.5))
            .padding(6)
            .overlay {
                if choice == current { RoundedRectangle(cornerRadius: radius + 6, style: .continuous).strokeBorder(Self.ring, lineWidth: 3) }
            }
            .padding(2)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
    }

    static var ring: Color {
        Color(UIColor { traits in
            let theme = ThemeStore.shared.resolved(dark: traits.userInterfaceStyle == .dark, increaseContrast: traits.accessibilityContrast == .high)
            return ContrastGuard.nudge(UIColor(hex: 0x09A950), against: [theme.surface], minimum: ContrastGuard.large)
        })
    }

    private func pick(_ choice: AppIconChoice) {
        guard choice != current else { return }
        problem = nil
        guard UIApplication.shared.supportsAlternateIcons else { problem = "This iPhone can\u{2019}t change the icon."; return }
        UIApplication.shared.setAlternateIconName(choice.iconName) { error in
            Task { @MainActor in
                if error == nil {
                    current = choice
                    Announce.say("App icon changed to \(choice.title)")
                } else { problem = "Couldn\u{2019}t change the icon. Try again." }
            }
        }
    }
}
