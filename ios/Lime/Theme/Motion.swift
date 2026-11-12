import SwiftUI
import UIKit

/// Motion that respects Reduce Motion (LIME-321): the setting is read at the moment something would animate, so a change takes effect at once.
@MainActor
enum Motion {
    static var reduced: Bool { UIAccessibility.isReduceMotionEnabled }
    /// The animation, or none under Reduce Motion.
    static func animation(_ animation: Animation) -> Animation? { reduced ? nil : animation }
}

/// `withAnimation`, skipped under Reduce Motion.
@MainActor @discardableResult
func withMotion<R>(_ animation: Animation = .default, _ body: () throws -> R) rethrows -> R {
    Motion.reduced ? try body() : try withAnimation(animation, body)
}
