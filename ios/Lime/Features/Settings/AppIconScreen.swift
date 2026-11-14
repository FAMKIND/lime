import SwiftUI
import UIKit

/// The icons a person can choose for lime on the Home Screen (LIME-292b, 292c): lime's own and seven others, all the lime slice. The choice is local to this
/// phone (iOS keeps it), never sent. Each is an Icon Composer bundle `AppIcon-<Title>.icon` (iOS makes its Dark, Clear and Tinted looks from the layers); lime's
/// own is the `AppIcon` set (iOS calls it `nil`).
enum AppIconChoice: String, CaseIterable, Identifiable {
    case lime, dark, sticker, notebook, chalkboard, pixel, rainbow, apple

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lime: "lime"
        case .dark: "Dark"
        case .sticker: "Sticker"
        case .notebook: "Notebook"
        case .chalkboard: "Chalkboard"
        case .pixel: "Pixel"
        case .rainbow: "Rainbow"
        case .apple: "Apple"
        }
    }

    /// What `setAlternateIconName` takes: nil is the primary icon.
    var iconName: String? { self == .lime ? nil : "AppIcon-\(title)" }
    var preview: String { "IconPreview-\(rawValue.prefix(1).uppercased())\(rawValue.dropFirst())" }
    var spokenName: String { "\(title) app icon" }

    static func choice(forIconName name: String?) -> AppIconChoice {
        if name == Self.oldMinimal { return .sticker }
        return allCases.first { $0.iconName == name } ?? .lime
    }

    /// The icon this build replaced: Minimal became Sticker (LIME-292c).
    static let oldMinimal = "AppIcon-Minimal"

    /// What to do about the icon iOS says is set: nothing when it is one of ours; Minimal moves to Sticker; anything else this build does not have goes back to lime's
    /// own (never a blank icon). `to` is what `setAlternateIconName` takes.
    static func migration(forIconName name: String?) -> (change: Bool, to: String?) {
        guard let name else { return (false, nil) }
        if allCases.contains(where: { $0.iconName == name }) { return (false, name) }
        if name == oldMinimal { return (true, AppIconChoice.sticker.iconName) }
        return (true, nil)
    }

    /// Four columns; three then two at accessibility text sizes, so the icons grow and never shrink under 60 pt.
    static func columns(for size: DynamicTypeSize) -> Int {
        guard size.isAccessibilitySize else { return 4 }
        return size >= .accessibility3 ? 2 : 3
    }

    /// Once a phone has an icon this build no longer has (Minimal became Sticker), move it, so the Home Screen never shows a blank one (LIME-292c).
    @MainActor static func migrateIfNeeded() {
        let step = migration(forIconName: UIApplication.shared.alternateIconName)
        guard step.change, UIApplication.shared.supportsAlternateIcons else { return }
        UIApplication.shared.setAlternateIconName(step.to) { _ in }
    }

    static let footer = "The name \u{201C}lime\u{201D} stays the same on your Home Screen and in notifications."
}

/// Settings → Customize → App icon: a grid in one card, each icon with its name under it (as Signal's), a ring in lime's green round the one in use.
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

    /// The ring: lime's green (nudged just enough to keep 3:1 against the card, which a theme can change), a small gap, then the icon, and its name under it.
    private func cell(_ choice: AppIconChoice, size: CGFloat) -> some View {
        let radius = size * 0.2237
        return VStack(spacing: 4) {
            icon(choice, size: size, radius: radius)
            Text(choice.title).font(Theme.font(.footnote)).foregroundStyle(Theme.textSecondary).lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                .multilineTextAlignment(.center).minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .contentShape(Rectangle())
    }

    private func icon(_ choice: AppIconChoice, size: CGFloat, radius: CGFloat) -> some View {
        Image(choice.preview).resizable().interpolation(.high).scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 0.5))
            .padding(6)
            .overlay {
                if choice == current { RoundedRectangle(cornerRadius: radius + 6, style: .continuous).strokeBorder(Self.ring, lineWidth: 3) }
            }
            .padding(2)
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
