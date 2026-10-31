import SwiftUI

/// LIME-277c: one Appearance screen (Settings → Customize → Appearance, and the palette button on your own profile). A live preview, then rows with the current
/// value and a swatch on the right (Mode, Accent, Background, Font, Text size); a row opens its own picker page, with the preview on top. Everything applies at
/// once and stays on this iPhone.
struct AppearanceScreen: View {
    enum Page: String, Identifiable {
        case mode, accent, background, font, size
        var id: String { rawValue }
    }

    @AppStorage(AppearanceSetting.storageKey) private var mode = AppearanceSetting.system.rawValue
    @State private var pushed: Page?
    private var store: ThemeStore { ThemeStore.shared }
    private let text = TextPreferences.shared

    var body: some View {
        SettingsPage(title: "Appearance") {
            AppearancePreview()
            SettingsCard {
                row(.mode, symbol: "circle.lefthalf.filled", title: "Mode", value: AppearanceSetting(rawValue: mode)?.title ?? "System", trailing: AnyView(EmptyView()))
                Divider().overlay(Theme.hairline).padding(.leading, 60)
                row(.accent, symbol: "paintpalette", title: "Accent", value: LimeColours.name(store.accent), trailing: AnyView(AccentDot(tone: store.accent, size: 22)))
                Divider().overlay(Theme.hairline).padding(.leading, 60)
                row(.background, symbol: "square.grid.3x3", title: "Background", value: store.background.title, trailing: AnyView(MiniBackground(kind: store.background)))
                Divider().overlay(Theme.hairline).padding(.leading, 60)
                row(.font, symbol: "textformat", title: "Font", value: text.typeface.title, trailing: AnyView(EmptyView()))
                Divider().overlay(Theme.hairline).padding(.leading, 60)
                row(.size, symbol: "textformat.size", title: "Text size", value: text.followsSystem ? "iPhone's" : text.currentStep.name, trailing: AnyView(EmptyView()), showsDivider: false)
            }
            Button("Reset to lime") { reset() }
                .font(Theme.body).foregroundStyle(Theme.text).frame(maxWidth: .infinity, minHeight: 48)
                .background(Theme.surface, in: Capsule())
                .accessibilityIdentifier("appearance-reset")
            SettingsFootnote(text: "The accent colours buttons and selections; the background is the paper under every page. Text adjusts to stay easy to read. All of it is kept on this iPhone.")
        }
        .navigationDestination(item: $pushed) { page in
            switch page {
            case .mode: ModePage()
            case .accent: AccentPage()
            case .background: BackgroundPage()
            case .font: TextSizeScreen(tab: .font)
            case .size: TextSizeScreen(tab: .size)
            }
        }
        #if DEBUG
        .task {
            // Screenshots: `-lime-demo-appearance-page accent` opens a picker page.
            let arguments = ProcessInfo.processInfo.arguments
            if let at = arguments.firstIndex(of: "-lime-demo-appearance-page"), at + 1 < arguments.count { pushed = Page(rawValue: arguments[at + 1]) }
        }
        #endif
    }

    private func row(_ page: Page, symbol: String, title: String, value: String, trailing: AnyView, showsDivider: Bool = true) -> some View {
        Button { pushed = page } label: {
            HStack(spacing: 14) {
                Image(systemName: symbol).font(.system(size: 20)).frame(width: 28).foregroundStyle(Theme.text)
                Text(title).font(Theme.body).foregroundStyle(Theme.text)
                Spacer(minLength: 8)
                Text(value).font(Theme.secondary).foregroundStyle(Theme.textSecondary).lineLimit(1)
                trailing
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textSecondary).accessibilityHidden(true)
            }
            .padding(.horizontal, 18).frame(minHeight: 58)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(value)")
        .accessibilityIdentifier("appearance-row-\(page.rawValue)")
    }

    /// Lime's own look again: lime, Plain, follow the phone's light or dark, the system font and the iPhone's text size.
    private func reset() {
        store.reset()
        mode = AppearanceSetting.system.rawValue
        text.typeface = .system
        text.followsSystem = true
    }
}

// MARK: Small pieces

private struct AccentDot: View {
    let tone: Int
    let size: CGFloat
    var body: some View {
        Circle().fill(Color(uiColor: UIColor(hex: LimeColours.accentHex[((tone % 8) + 8) % 8]))).frame(width: size, height: size)
            .overlay(Circle().strokeBorder(Theme.hairline, lineWidth: 1)).accessibilityHidden(true)
    }
}

/// A tiny thumbnail of a background, for a row's right-hand side.
private struct MiniBackground: View {
    let kind: ThemeBackground
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let theme = ThemeResolver.resolve(accent: ThemeStore.shared.accent, background: kind, dark: scheme == .dark)
        ZStack { Color(theme.canvas); ThemeBackgroundSample(kind: kind, theme: theme) }
            .frame(width: 22, height: 30).clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
            .accessibilityHidden(true)
    }
}

/// The live preview (Substack's "Background preview"): the chosen background with a mini chat and a jam card drawn the way the app draws them. Decorative.
struct AppearancePreview: View {
    var body: some View {
        ZStack {
            ThemeBackgroundView()
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Are you coming to the staff meeting?")
                        .font(Theme.font(.subheadline)).foregroundStyle(Theme.text)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Theme.bubbleOther, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    HStack {
                        Spacer(minLength: 40)
                        Text("Yes! I'll bring the reading lists.")
                            .font(Theme.font(.subheadline)).foregroundStyle(Theme.ownBubbleInk)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Theme.ownBubble, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                }
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Seed swap, week 4").font(Theme.font(.subheadline, weight: .semibold)).foregroundStyle(Theme.text)
                        Text("A jam post").font(Theme.font(.caption)).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer(minLength: 8)
                    Text("Subscribe").font(Theme.font(.caption, weight: .semibold)).foregroundStyle(Theme.accentInk)
                        .padding(.horizontal, 12).frame(minHeight: 30).background(Theme.accent, in: Capsule())
                }
                .padding(12)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .padding(16)
        }
        .frame(height: 230)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
        .accessibilityHidden(true)
        .accessibilityIdentifier("appearance-preview")
        #if DEBUG
        .overlay(alignment: .topLeading) { Color.clear.frame(width: 1, height: 1).accessibilityElement().accessibilityIdentifier("appearance-preview-shown") }
        #endif
    }
}

// MARK: Picker pages

private struct ModePage: View {
    @AppStorage(AppearanceSetting.storageKey) private var stored = AppearanceSetting.system.rawValue

    var body: some View {
        SettingsPage(title: "Mode") {
            AppearancePreview()
            SettingsCard {
                ForEach(AppearanceSetting.allCases) { option in
                    Button { stored = option.rawValue } label: {
                        VStack(spacing: 0) {
                            HStack(spacing: 14) {
                                Image(systemName: option.symbol).font(.system(size: 20)).frame(width: 28).foregroundStyle(Theme.text)
                                Text(option.title).font(Theme.body).foregroundStyle(Theme.text)
                                Spacer()
                                if stored == option.rawValue { Image(systemName: "checkmark").font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.text) }
                            }
                            .padding(.horizontal, 18).frame(minHeight: 58)
                            if option != AppearanceSetting.allCases.last { Divider().overlay(Theme.hairline).padding(.leading, 60) }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("appearance-\(option.rawValue)")
                    .accessibilityAddTraits(stored == option.rawValue ? [.isSelected] : [])
                }
            }
            SettingsFootnote(text: ThemeStore.shared.background.forcesDark ? "Chalkboard is always dark." : "System follows your iPhone's Light or Dark.")
        }
    }
}

/// Eight large circles (lime first), the chosen one with a dark ring and a check (WhatsApp's colour grid).
private struct AccentPage: View {
    private var store: ThemeStore { ThemeStore.shared }
    private let order = [LimeColours.lime] + (0..<8).filter { $0 != LimeColours.lime }

    var body: some View {
        SettingsPage(title: "Accent") {
            AppearancePreview()
            SettingsCard {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 44), spacing: 8), count: 4), spacing: 12) {
                    ForEach(order, id: \.self) { tone in
                        let on = store.accent == tone
                        Button { store.accent = tone } label: {
                            ZStack {
                                Circle().fill(Color(uiColor: UIColor(hex: LimeColours.accentHex[tone])))
                                if on {
                                    Image(systemName: "checkmark").font(.system(size: 20, weight: .bold))
                                        .foregroundStyle(Color(ContrastGuard.ink(on: UIColor(hex: LimeColours.accentHex[tone]))))
                                }
                            }
                            .frame(width: 52, height: 52)
                            .overlay(Circle().strokeBorder(on ? Theme.text : Color.clear, lineWidth: 3).padding(-5))
                            .frame(maxWidth: .infinity, minHeight: 64)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(LimeColours.name(tone) + (tone == LimeColours.lime ? ", lime's own" : ""))
                        .accessibilityAddTraits(on ? [.isSelected] : [])
                        .accessibilityIdentifier("theme-accent-\(tone)")
                    }
                }
                .padding(16)
            }
            SettingsFootnote(text: "The accent colours the one main button on a screen, the “+”, badges and selections. The same eight colours are used for avatars and covers.")
        }
    }
}

/// A 3-across grid of tall, phone-shaped thumbnails, the chosen one outlined with a check (WhatsApp's wallpaper grid).
private struct BackgroundPage: View {
    private var store: ThemeStore { ThemeStore.shared }
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        SettingsPage(title: "Background") {
            AppearancePreview()
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 80), spacing: 12), count: 3), spacing: 14) {
                ForEach(ThemeBackground.allCases) { kind in
                    let on = store.background == kind
                    Button { store.background = kind } label: {
                        VStack(spacing: 6) {
                            ThemeTile(kind: kind, dark: scheme == .dark)
                                .aspectRatio(0.62, contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(on ? Theme.text : Theme.hairline, lineWidth: on ? 3 : 1))
                                .overlay(alignment: .bottomTrailing) {
                                    if on {
                                        Image(systemName: "checkmark.circle.fill").font(.system(size: 22)).symbolRenderingMode(.palette)
                                            .foregroundStyle(Theme.canvas, Theme.text).padding(8)
                                    }
                                }
                            Text(kind.title).font(Theme.font(.caption, weight: on ? .semibold : .regular)).foregroundStyle(Theme.text).lineLimit(1)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(kind.title).accessibilityAddTraits(on ? [.isSelected] : [])
                    .accessibilityIdentifier("theme-background-\(kind.rawValue)")
                }
            }
            SettingsFootnote(text: store.background.forcesDark ? "Chalkboard draws all of lime dark." : "The paper under every page. Cards and bars stay readable on each.")
        }
    }
}
