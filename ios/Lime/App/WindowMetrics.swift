import SwiftUI

/// The size of lime's own window (LIME-267). On an iPad in Stage Manager, Split View or Slide Over the window is narrower than the screen, so widths
/// taken from `UIScreen.main` lay a phone-sized window out as if it were the whole iPad. Views read this instead; it is updated from the root view.
@MainActor
@Observable
final class WindowMetrics {
    static let shared = WindowMetrics()
    var size: CGSize = UIScreen.main.bounds.size
}
