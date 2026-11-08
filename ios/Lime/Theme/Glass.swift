import SwiftUI

/// Liquid Glass on iOS 26+, a thin material with a hairline below that.
/// Reduce Transparency makes it a solid (the surface, or an ink scrim for white controls over photos and video); Increase Contrast adds a 1 pt border
/// in the text colour at 30 % (LIME-130-2).
private struct LimeGlass<S: InsettableShape>: ViewModifier {
    let shape: S
    /// White controls over a photo or video: with Reduce Transparency they sit on an ink scrim, not on the cream surface.
    let overMedia: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(overMedia ? Color(uiColor: LimeGlassScrim.ink) : Theme.surface, in: shape)
                .overlay(shape.strokeBorder(contrast == .increased ? borderColour : Theme.hairline, lineWidth: contrast == .increased ? 1 : 0.5))
        } else if #available(iOS 26, *) {
            content.glassEffect(.regular, in: shape)
                .overlay { if contrast == .increased { shape.strokeBorder(borderColour, lineWidth: 1) } }
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.strokeBorder(contrast == .increased ? borderColour : Theme.hairline, lineWidth: contrast == .increased ? 1 : 0.5))
                .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
        }
    }

    private var borderColour: Color { overMedia ? Color.white.opacity(0.5) : Theme.text.opacity(0.3) }
}

enum LimeGlassScrim {
    /// lime's ink at 85 %: white glyphs on it keep 4.5:1 over any picture.
    static let ink = UIColor(hex: 0x131B17).withAlphaComponent(0.85)
}

extension View {
    func limeGlass<S: InsettableShape>(in shape: S = Capsule(), overMedia: Bool = false) -> some View {
        modifier(LimeGlass(shape: shape, overMedia: overMedia))
    }
}
