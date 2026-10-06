import SwiftUI

/// iOS 17-25 only (iOS 26+ uses the system's soft scroll edge effect). A subtle veil behind the
/// floating header pills: a progressive blur plus a low-opacity canvas gradient. It starts at the
/// very top of the screen (behind the status bar), as in Apple Messages, and is gone about 10pt
/// below the header buttons.
struct TopFade: View {
    private let headerHeight: CGFloat = 56
    private let tail: CGFloat = 10
    /// How strongly the canvas colour veils the very top. Low on purpose: rows read as softly veiled.
    private let veil = 0.55

    var body: some View {
        GeometryReader { geo in
            let total = geo.safeAreaInsets.top + headerHeight + tail
            let fade = LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black.opacity(0.55), location: 0.55),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .top, endPoint: .bottom)
            ZStack {
                Rectangle().fill(.ultraThinMaterial).mask(fade)
                Theme.canvas.opacity(veil).mask(fade)
            }
            .frame(height: total)
            .ignoresSafeArea(edges: .top)
        }
        .frame(height: 0, alignment: .top)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
