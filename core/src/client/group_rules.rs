//! Group rules that lived only in Swift (LIME-303; `ios/Lime/Features/Messages/GroupAvatarPlan.swift`): what a group's picture draws when it has no photo
//! and no emoji. Pure functions, so every app draws the same picture. The numbers are in `docs/screens/group-avatar.md`.
//! iOS keeps its Swift copy until LIME-133b moves it onto this.

/// How a group's picture is arranged.
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum GroupAvatarKind {
    /// One circle (nobody else in the group).
    Single,
    /// Two circles: the other person in front, you behind.
    Pair,
    /// Three in all: one on top, two below.
    Triangle,
    /// Four circles: one at each of top, right, bottom and left. The fourth may be a "+N".
    Ring,
}

/// What the group picture draws: `shown` are the people's ids in drawing order (later circles sit on top), `extra` is the "+N" count
/// (it counts you) that replaces the fourth circle when there are more than three others.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct GroupAvatarPlan {
    pub kind: GroupAvatarKind,
    pub shown: Vec<String>,
    pub extra: u32,
}

/// The circles of a group with no picture: the other members and you, others first, you last. `pair` lists `[front, back]`, the order
/// the Swift enum names them in.
#[uniffi::export]
pub fn group_avatar_plan(others: Vec<String>, me: String) -> GroupAvatarPlan {
    match others.len() {
        0 => GroupAvatarPlan { kind: GroupAvatarKind::Single, shown: vec![me], extra: 0 },
        1 => GroupAvatarPlan { kind: GroupAvatarKind::Pair, shown: vec![others[0].clone(), me], extra: 0 },
        2 => GroupAvatarPlan { kind: GroupAvatarKind::Triangle, shown: others.into_iter().chain([me]).collect(), extra: 0 },
        3 => GroupAvatarPlan { kind: GroupAvatarKind::Ring, shown: others.into_iter().chain([me]).collect(), extra: 0 },
        n => GroupAvatarPlan { kind: GroupAvatarKind::Ring, shown: others.into_iter().take(3).collect(), extra: (n + 1 - 3) as u32 },
    }
}

/// A circle's centre as a fraction of the avatar's side, from the middle (y down).
#[derive(Debug, Clone, Copy, PartialEq, uniffi::Record)]
pub struct GroupAvatarSpot {
    pub x: f64,
    pub y: f64,
}

/// One diameter for all circles (a fraction of the avatar's side) and the centres, in drawing order.
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct GroupAvatarSpots {
    pub diameter: f64,
    pub centres: Vec<GroupAvatarSpot>,
}

/// Where the circles go, for 1, 2, 3 or 4 circles (a "+N" counts as one).
#[uniffi::export]
pub fn group_avatar_spots(circles: u32) -> GroupAvatarSpots {
    let spot = |x: f64, y: f64| GroupAvatarSpot { x, y };
    match circles {
        0 | 1 => GroupAvatarSpots { diameter: 1.0, centres: vec![spot(0.0, 0.0)] },
        2 => GroupAvatarSpots { diameter: 0.62, centres: vec![spot(-0.17, 0.1), spot(0.17, -0.1)] },
        3 => GroupAvatarSpots { diameter: 0.5, centres: vec![spot(0.0, -0.25), spot(-0.215, 0.145), spot(0.215, 0.145)] },
        _ => GroupAvatarSpots { diameter: 0.44, centres: vec![spot(0.0, -0.26), spot(0.26, 0.0), spot(0.0, 0.26), spot(-0.26, 0.0)] },
    }
}

/// The outline ring's width for an avatar of this side.
#[uniffi::export]
pub fn group_avatar_ring_width(side: f64) -> f64 {
    (side * 0.035).max(1.2)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn people(n: usize) -> Vec<String> {
        (0..n).map(|i| format!("p{i}")).collect()
    }

    // The same cases as ios/LimeTests/CallPolishTests.swift.
    #[test]
    fn a_pair_is_two_overlapping_circles_the_other_person_in_front_and_me_behind() {
        let plan = group_avatar_plan(people(1), "me".into());
        assert_eq!(plan, GroupAvatarPlan { kind: GroupAvatarKind::Pair, shown: vec!["p0".into(), "me".into()], extra: 0 });
    }

    #[test]
    fn three_or_four_in_all_is_the_cluster_of_everyone_with_me_last() {
        let mut three = people(2);
        three.push("me".into());
        assert_eq!(group_avatar_plan(people(2), "me".into()), GroupAvatarPlan { kind: GroupAvatarKind::Triangle, shown: three, extra: 0 });
        let mut four = people(3);
        four.push("me".into());
        assert_eq!(group_avatar_plan(people(3), "me".into()), GroupAvatarPlan { kind: GroupAvatarKind::Ring, shown: four, extra: 0 });
    }

    #[test]
    fn more_than_four_shows_three_and_a_plus_n_that_counts_me() {
        assert_eq!(group_avatar_plan(people(4), "me".into()), GroupAvatarPlan { kind: GroupAvatarKind::Ring, shown: people(3), extra: 2 });
        assert_eq!(group_avatar_plan(people(7), "me".into()), GroupAvatarPlan { kind: GroupAvatarKind::Ring, shown: people(3), extra: 5 });
    }

    #[test]
    fn nobody_else_is_just_me() {
        assert_eq!(group_avatar_plan(vec![], "me".into()), GroupAvatarPlan { kind: GroupAvatarKind::Single, shown: vec!["me".into()], extra: 0 });
    }

    #[test]
    fn the_spots_match_the_swift_numbers() {
        assert_eq!(group_avatar_spots(1).diameter, 1.0);
        let two = group_avatar_spots(2);
        assert_eq!((two.diameter, two.centres.len()), (0.62, 2));
        assert_eq!(two.centres[0], GroupAvatarSpot { x: -0.17, y: 0.1 });
        let three = group_avatar_spots(3);
        assert_eq!((three.diameter, three.centres.len()), (0.5, 3));
        assert_eq!(three.centres[0], GroupAvatarSpot { x: 0.0, y: -0.25 });
        let four = group_avatar_spots(4);
        assert_eq!((four.diameter, four.centres.len()), (0.44, 4));
        assert_eq!(group_avatar_spots(9), four);
    }

    #[test]
    fn the_ring_is_at_least_1_2_wide() {
        assert_eq!(group_avatar_ring_width(20.0), 1.2);
        assert!((group_avatar_ring_width(100.0) - 3.5).abs() < 1e-9);
    }
}
