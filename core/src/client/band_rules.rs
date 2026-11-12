//! Which of my jams is my own space and which are bands (LIME-315a). The core's rule (`store/jam.rs::own_space`): **my own space is the oldest jam I write** (made on my first post);
//! it is my profile's posting space and never a band: it never gets a members group (LIME-281). Every other jam of mine is a band. The app asks here instead of copying the rule.

use super::jam::JamInfo;

/// The id of my own space among `jams` (the ones I write, `mine`; ended ones count, as in the store: the oldest by `created`, then by id), or None when I write none.
#[uniffi::export]
pub fn jam_own_space_id(jams: Vec<JamInfo>) -> Option<String> {
    jams.into_iter().filter(|j| j.mine).min_by(|a, b| a.created.cmp(&b.created).then_with(|| a.jam_id.cmp(&b.jam_id))).map(|j| j.jam_id)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn jam(id: &str, mine: bool, created: i64) -> JamInfo {
        JamInfo {
            jam_id: id.into(), conversation_id: format!("jam:{id}"), writer: "me".into(), title: id.into(), about: String::new(), topics: vec![], tiers: vec![], mine,
            status: "active".into(), ended: false, community: false, community_state: None, community_group: None, subscriber_count: 0, post_count: 0, created,
        }
    }

    #[test]
    fn my_own_space_is_the_oldest_jam_i_write_and_the_rest_are_bands() {
        let jams = vec![jam("band-b", true, 300), jam("space", true, 100), jam("followed", false, 50), jam("band-a", true, 200)];
        assert_eq!(jam_own_space_id(jams), Some("space".into()), "the oldest of mine, not a jam I only follow");
    }

    #[test]
    fn a_tie_goes_to_the_smaller_id_and_no_jam_of_mine_gives_none() {
        assert_eq!(jam_own_space_id(vec![jam("b", true, 5), jam("a", true, 5)]), Some("a".into()));
        assert_eq!(jam_own_space_id(vec![jam("x", false, 1)]), None);
        assert_eq!(jam_own_space_id(vec![]), None);
    }

    #[test]
    fn an_ended_jam_still_counts_as_the_own_space_as_in_the_store() {
        let mut old = jam("space", true, 10);
        old.ended = true;
        assert_eq!(jam_own_space_id(vec![jam("band", true, 20), old]), Some("space".into()));
    }
}
