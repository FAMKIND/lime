import Foundation

/// What a group's picture (no group photo, no emoji) draws (LIME-150, item 11): the other members **and you**, others first, you last.
/// - **two people in all (you and one other):** two overlapping circles inside the one avatar circle, the other person in front with an outline
///   ring, you behind;
/// - **three or four in all:** the quadrant cluster of everyone;
/// - **more:** the first three others and a "+N" for the rest (N counts you).
/// Pure, so the SwiftUI avatar and the UIKit twin (`PiPGroupAvatarView`) follow one rule.
enum GroupAvatarPlan: Equatable {
    case pair(front: Person, back: Person)
    case cluster(shown: [Person], extra: Int)
    case single(Person)

    static func make(others: [Person], me: Person) -> GroupAvatarPlan {
        switch others.count {
        case 0: return .single(me)
        case 1: return .pair(front: others[0], back: me)
        case 2, 3: return .cluster(shown: others + [me], extra: 0)
        default: return .cluster(shown: Array(others.prefix(3)), extra: others.count + 1 - 3)
        }
    }

    /// The centre of quadrant `index` (0 top-left, 1 top-right, 2 bottom-left, 3 bottom-right) as offsets from the middle, in units of the
    /// avatar's side.
    static func quadrant(_ index: Int) -> (x: Double, y: Double) { (index % 2 == 0 ? -0.24 : 0.24, index < 2 ? -0.24 : 0.24) }

    /// The pair's circles: diameter and centre offsets in units of the avatar's side (the front circle is the upper right, you behind lower left).
    static let pairDiameter = 0.62
    static let pairFront = (x: 0.17, y: -0.1)
    static let pairBack = (x: -0.17, y: 0.1)
}
