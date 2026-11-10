import SwiftUI
import UIKit

/// LIME-277b: the eight backgrounds, drawn (no image files): shapes and patterns from the theme's own colours, crisp at any scale, light and dark. Behind root
/// screens and pushed pages; cards, rows and bars keep the theme's surface on top. Reduce Transparency draws the plain paper only.
struct ThemeBackgroundView: View {
    /// A chat's own choice of one of the eight (LIME-277d); nil is the global one.
    var override: ThemeBackground? = nil
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let store = ThemeStore.shared
        let kind = override ?? store.background
        let theme = override == nil ? store.resolved(dark: colorScheme == .dark, increaseContrast: UIAccessibility.isDarkerSystemColorsEnabled)
            : ThemeResolver.resolve(accent: store.accent, background: kind, dark: colorScheme == .dark, increaseContrast: UIAccessibility.isDarkerSystemColorsEnabled)
        let canvas = Color(theme.canvas)
        ZStack {
            canvas
            if !reduceTransparency {
                switch kind {
                case .plain: EmptyView()
                case .living: LivingBackground(theme: theme)
                default: PatternCanvas(kind: kind, theme: theme)
                }
            }
        }
        .drawingGroup(opaque: true)
        .accessibilityHidden(true)
        #if DEBUG
        .overlay(alignment: .topLeading) { Color.clear.frame(width: 1, height: 1).accessibilityElement().accessibilityIdentifier(override == nil ? "theme-bg-\(kind.rawValue)" : "chat-bg-\(kind.rawValue)") }
        #endif
    }
}

/// A pattern alone, for the small samples in the picker (Living shows its tone gradient).
struct ThemeBackgroundSample: View {
    let kind: ThemeBackground
    let theme: ResolvedTheme
    var body: some View {
        switch kind {
        case .plain: Color.clear
        case .living: LinearGradient(colors: HeroPalette.tonePalette(ThemeStore.shared.accent).prefix(3).map { Color($0).opacity(0.35) }, startPoint: .topLeading, endPoint: .bottomTrailing)
        default: PatternCanvas(kind: kind, theme: theme)
        }
    }
}

/// The drawn patterns, one `Canvas` each.
private struct PatternCanvas: View {
    let kind: ThemeBackground
    let theme: ResolvedTheme

    var body: some View {
        Canvas(rendersAsynchronously: false) { context, size in
            switch kind {
            case .paper: paper(&context, size)
            case .dots: dots(&context, size)
            case .lined: lined(&context, size)
            case .graph: graph(&context, size)
            case .chalkboard: chalkboard(&context, size)
            case .bulletin: cork(&context, size)
            case .plain, .living: break
            }
        }
    }

    private var ink: Color { Color(theme.text) }

    /// A small deterministic random sequence, so a pattern is the same every time it is drawn.
    private struct Seeded {
        var state: UInt64
        mutating func next() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 33) / Double(UInt64(1) << 31)
        }
    }

    private func paper(_ context: inout GraphicsContext, _ size: CGSize) {
        var random = Seeded(state: 11)
        let count = Int(size.width * size.height / 260)
        for _ in 0..<count {
            let x = random.next() * size.width, y = random.next() * size.height
            let r = 0.4 + random.next() * 0.6
            context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)), with: .color(ink.opacity(0.05 + random.next() * 0.05)))
        }
    }

    private func dots(_ context: inout GraphicsContext, _ size: CGSize) {
        let step: CGFloat = 22
        var y: CGFloat = step / 2
        while y < size.height {
            var x: CGFloat = step / 2
            while x < size.width {
                context.fill(Path(ellipseIn: CGRect(x: x - 1.1, y: y - 1.1, width: 2.2, height: 2.2)), with: .color(ink.opacity(0.16)))
                x += step
            }
            y += step
        }
    }

    private func lined(_ context: inout GraphicsContext, _ size: CGSize) {
        let step: CGFloat = 30
        var y: CGFloat = 70
        while y < size.height {
            context.stroke(Path { $0.move(to: CGPoint(x: 0, y: y)); $0.addLine(to: CGPoint(x: size.width, y: y)) }, with: .color(Color(red: 0.42, green: 0.62, blue: 0.82).opacity(0.28)), lineWidth: 1)
            y += step
        }
        context.stroke(Path { $0.move(to: CGPoint(x: 46, y: 0)); $0.addLine(to: CGPoint(x: 46, y: size.height)) }, with: .color(Color(red: 0.86, green: 0.38, blue: 0.40).opacity(0.30)), lineWidth: 1)
    }

    private func graph(_ context: inout GraphicsContext, _ size: CGSize) {
        let step: CGFloat = 20
        var index = 0
        var x: CGFloat = 0
        while x <= size.width {
            context.stroke(Path { $0.move(to: CGPoint(x: x, y: 0)); $0.addLine(to: CGPoint(x: x, y: size.height)) }, with: .color(ink.opacity(index % 5 == 0 ? 0.13 : 0.06)), lineWidth: index % 5 == 0 ? 0.9 : 0.5)
            x += step; index += 1
        }
        index = 0
        var y: CGFloat = 0
        while y <= size.height {
            context.stroke(Path { $0.move(to: CGPoint(x: 0, y: y)); $0.addLine(to: CGPoint(x: size.width, y: y)) }, with: .color(ink.opacity(index % 5 == 0 ? 0.13 : 0.06)), lineWidth: index % 5 == 0 ? 0.9 : 0.5)
            y += step; index += 1
        }
    }

    private func chalkboard(_ context: inout GraphicsContext, _ size: CGSize) {
        var random = Seeded(state: 29)
        for _ in 0..<7 {
            let w = size.width * (0.5 + random.next() * 0.6), h = size.height * (0.05 + random.next() * 0.1)
            let rect = CGRect(x: random.next() * size.width - w / 2, y: random.next() * size.height - h / 2, width: w, height: h)
            var smudge = context
            smudge.addFilter(.blur(radius: 24))
            smudge.fill(Path(ellipseIn: rect), with: .color(Color.white.opacity(0.045)))
        }
        for _ in 0..<Int(size.width * size.height / 900) {
            let x = random.next() * size.width, y = random.next() * size.height
            context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1, height: 1)), with: .color(Color.white.opacity(0.06)))
        }
    }

    private func cork(_ context: inout GraphicsContext, _ size: CGSize) {
        var random = Seeded(state: 47)
        let dark = theme.canvas.cgColor.components.map { $0.first ?? 0 } ?? 0 < 0.4
        for _ in 0..<Int(size.width * size.height / 70) {
            let x = random.next() * size.width, y = random.next() * size.height
            let r = 0.8 + random.next() * 2.2
            let tone = random.next()
            let colour = dark
                ? Color(red: 0.55 + tone * 0.2, green: 0.38 + tone * 0.15, blue: 0.24 + tone * 0.1).opacity(0.22)
                : (tone < 0.5 ? Color(red: 0.55, green: 0.38, blue: 0.2).opacity(0.18) : Color(red: 0.96, green: 0.84, blue: 0.64).opacity(0.35))
            context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r * (0.7 + random.next() * 0.5))), with: .color(colour))
        }
    }
}

/// Living (261/261b): the ambient colours from your own photo, or from your colour when you have none, drifting slowly (still with Reduce Motion) under a veil
/// of the canvas so text stays readable.
private struct LivingBackground: View {
    let theme: ResolvedTheme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let store = ThemeStore.shared
        let photo = store.livingPhoto
        let palette = (photo.map { HeroPalette.vibrant(from: $0, key: "living-\(ObjectIdentifier($0).hashValue)") } ?? []).count >= 3
            ? HeroPalette.vibrant(from: photo!, key: "living-\(ObjectIdentifier(photo!).hashValue)")
            : HeroPalette.tonePalette(store.accent)
        ZStack {
            AmbientBackground(palette: palette)
            Color(theme.canvas).opacity(LivingVeil.opacity(dark: colorScheme == .dark))
        }
    }
}

extension View {
    /// The paper under a root screen or a pushed page: the theme's background (LIME-277b), plain canvas by default.
    func limeBackground() -> some View {
        background { ThemeBackgroundView().ignoresSafeArea() }
    }
}
