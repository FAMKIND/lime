import Foundation

/// What a group's picture (no group photo, no emoji) draws (LIME-150 item 11, LIME-152b): the other members **and you**, others first, you last,
/// as overlapping circles inside the one avatar circle, each with a thin outline ring so every face reads where circles overlap.
/// - **two people in all (you and one other):** two circles, the other person in front, you behind;
/// - **three in all:** a triangle (one on top, two below);
/// - **four in all:** a circle of circles (one at each of top, right, bottom and left, overlapping a little);
/// - **more:** the first three others and a "+N" for the rest (N counts you), laid out as the four.
/// Pure, so the SwiftUI avatar and the UIKit twin (`PiPGroupAvatarView`) follow one rule; the numbers are in `docs/screens/group-avatar.md`.
enum GroupAvatarPlan: Equatable {
    case pair(front: Person, back: Person)
    case triangle([Person])
    case ring(shown: [Person], extra: Int)
    case single(Person)

    static func make(others: [Person], me: Person) -> GroupAvatarPlan {
        switch others.count {
        case 0: return .single(me)
        case 1: return .pair(front: others[0], back: me)
        case 2: return .triangle(others + [me])
        case 3: return .ring(shown: others + [me], extra: 0)
        default: return .ring(shown: Array(others.prefix(3)), extra: others.count + 1 - 3)
        }
    }

    /// Where the circles go, as fractions of the avatar's side: the centres as offsets from the middle (y down), and one diameter for all. For
    /// `circles` of 1, 2, 3 or 4 (a "+N" counts as a circle); in drawing order (later ones sit on top).
    static func spots(circles: Int) -> (diameter: Double, centres: [(x: Double, y: Double)]) {
        switch circles {
        case ...1: return (1.0, [(0, 0)])
        case 2: return (0.62, [(-0.17, 0.1), (0.17, -0.1)])                           // you behind (lower left), the other in front (upper right)
        case 3: return (0.5, [(0, -0.25), (-0.215, 0.145), (0.215, 0.145)])           // top, bottom left, bottom right
        default: return (0.44, [(0, -0.26), (0.26, 0), (0, 0.26), (-0.26, 0)])        // top, right, bottom, left
        }
    }

    /// The outline ring's width for an avatar of this side.
    static func ringWidth(side: Double) -> Double { max(1.2, side * 0.035) }
}
