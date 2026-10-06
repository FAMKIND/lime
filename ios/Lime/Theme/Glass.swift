import SwiftUI

/// Liquid Glass on iOS 26+, a thin material with a hairline below that.
private struct LimeGlass<S: InsettableShape>: ViewModifier {
    let shape: S

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.strokeBorder(Theme.hairline, lineWidth: 0.5))
                .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
        }
    }
}

extension View {
    func limeGlass<S: InsettableShape>(in shape: S = Capsule()) -> some View {
        modifier(LimeGlass(shape: shape))
    }
}
