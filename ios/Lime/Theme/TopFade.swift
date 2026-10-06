import SwiftUI

/// A soft fade (canvas to clear) behind the floating header pills, so scrolled content
/// never shows hard-cut under them. Covers the status bar, the pills and 24pt below.
struct TopFade: View {
    private let headerHeight: CGFloat = 56
    private let fadeLength: CGFloat = 24

    var body: some View {
        GeometryReader { geo in
            let solid = geo.safeAreaInsets.top + headerHeight
            let total = solid + fadeLength
            LinearGradient(
                stops: [
                    .init(color: Theme.canvas, location: 0),
                    .init(color: Theme.canvas, location: solid / total),
                    .init(color: Theme.canvas.opacity(0), location: 1),
                ],
                startPoint: .top, endPoint: .bottom)
                .frame(height: total)
                .ignoresSafeArea(edges: .top)
        }
        .frame(height: 0, alignment: .top)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
