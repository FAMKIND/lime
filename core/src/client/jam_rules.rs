//! The jam feed's rules that lived only in Swift (LIME-311): what the segments (All, Posts, Articles, Podcasts) and the filters let through, which card a post
//! gets, which posts the feed holds and in what order, the co-author byline and a card's excerpt. Mirrors `ios/Lime/Features/Jam/JamFilter.swift`
//! (`JamSegment`, `JamFilter`), `JamCardChoice.swift`, and the read parts of `ios/Lime/App/ConversationStore+Jam.swift` (`jamFeed`, the byline). The words of a
//! date follow the phone's locale and stay with the platform. Pure functions; iOS keeps its Swift until LIME-133b.

use crate::client::jam::{JamInfo, JamPostInfo};

/// The feed's segments: **All**, **Posts** (quick posts), **Articles** and **Podcasts** (recordings); Drafts and Discover list other things.
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum JamFeedSegment {
    All,
    Posts,
    Articles,
    Podcasts,
    Drafts,
    Discover,
}

#[uniffi::export]
pub fn jam_segments() -> Vec<JamFeedSegment> {
    use JamFeedSegment::*;
    vec![All, Posts, Articles, Podcasts, Drafts, Discover]
}

#[uniffi::export]
pub fn jam_segment_title(segment: JamFeedSegment) -> String {
    use JamFeedSegment::*;
    match segment {
        All => "All",
        Posts => "Posts",
        Articles => "Articles",
        Podcasts => "Podcasts",
        Drafts => "Drafts",
        Discover => "Discover",
    }
    .to_owned()
}

/// Whether the segment lists a post of this kind (`quick`, `article` or `record`).
#[uniffi::export]
pub fn jam_segment_includes(segment: JamFeedSegment, kind: String) -> bool {
    match segment {
        JamFeedSegment::All => true,
        JamFeedSegment::Posts => kind == "quick",
        JamFeedSegment::Articles => kind == "article",
        JamFeedSegment::Podcasts => kind == "record",
        JamFeedSegment::Drafts | JamFeedSegment::Discover => false,
    }
}

/// A media kind a filter narrows to.
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum JamFeedMedia {
    Photos,
    Video,
    Audio,
}

#[uniffi::export]
pub fn jam_media_title(media: JamFeedMedia) -> String {
    match media {
        JamFeedMedia::Photos => "Photos",
        JamFeedMedia::Video => "Video",
        JamFeedMedia::Audio => "Audio",
    }
    .to_owned()
}

/// The filters on top of the segment: a media kind, **Co-authored**, **Subscribed** (jams you follow, not your own), **Bands** (posts shown as a jam) and **Saved**
/// (bookmarked on this phone).
#[derive(Debug, Clone, PartialEq, Eq, Default, uniffi::Record)]
pub struct JamFeedFilter {
    pub media: Option<JamFeedMedia>,
    pub coauthored: bool,
    pub subscribed: bool,
    pub orgs: bool,
    pub saved: bool,
}

#[uniffi::export]
pub fn jam_filter_active_count(filter: JamFeedFilter) -> u32 {
    u32::from(filter.media.is_some()) + u32::from(filter.coauthored) + u32::from(filter.subscribed) + u32::from(filter.orgs) + u32::from(filter.saved)
}

/// Does a post pass the segment and the filters? `files` are the kinds of the post's attachments (`image`, `video`, `audio`, `file`).
#[uniffi::export]
#[allow(clippy::too_many_arguments)]
pub fn jam_filter_matches(kind: String, files: Vec<String>, coauthored: bool, as_jam: bool, subscribed: bool, saved: bool, segment: JamFeedSegment, filter: JamFeedFilter) -> bool {
    if !jam_segment_includes(segment, kind.clone()) {
        return false;
    }
    if filter.coauthored && !coauthored || filter.orgs && !as_jam || filter.subscribed && !subscribed || filter.saved && !saved {
        return false;
    }
    if kind != "article" {
        if let Some(media) = filter.media {
            let wanted = match media {
                JamFeedMedia::Audio => "audio",
                JamFeedMedia::Video => "video",
                JamFeedMedia::Photos => "image",
            };
            if !files.iter().any(|f| f == wanted) {
                return false;
            }
        }
    }
    true
}

/// The card a post gets: the compact podcast card (audio), a video drawn as a video, or a regular card.
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum JamCardKind {
    Regular,
    SmallPodcast,
    VideoPodcast,
}

/// A recording with audio keeps the small card everywhere; a video recording is a video card; anything else (or a recording not ready) is a regular card.
#[uniffi::export]
pub fn jam_card_kind(is_recording: bool, ready: bool, has_audio: bool, has_video: bool) -> JamCardKind {
    if !is_recording || !ready || !(has_audio || has_video) {
        return JamCardKind::Regular;
    }
    if has_video && !has_audio { JamCardKind::VideoPodcast } else { JamCardKind::SmallPodcast }
}

/// The posts the feed holds: only posts that are ready to read, of jams I follow (an accepted subscription) or my own, each once, newest first.
#[uniffi::export]
pub fn jam_feed_posts(posts: Vec<JamPostInfo>, jams: Vec<JamInfo>) -> Vec<JamPostInfo> {
    let live: Vec<&str> = jams.iter().filter(|j| j.mine || j.status == "active").map(|j| j.jam_id.as_str()).collect();
    let mut seen: Vec<String> = Vec::new();
    let mut out: Vec<JamPostInfo> = Vec::new();
    for p in posts {
        if live.contains(&p.jam_id.as_str()) && p.state == "ready" && !seen.contains(&p.post_id) {
            seen.push(p.post_id.clone());
            out.push(p);
        }
    }
    out.sort_by_key(|p| std::cmp::Reverse(p.created));
    out
}

/// "with Jean Chung and Lee Wong" for the co-authors who accepted, or none.
#[uniffi::export]
pub fn jam_byline(coauthor_names: Vec<String>) -> Option<String> {
    match coauthor_names.len() {
        0 => None,
        1 => Some(format!("with {}", coauthor_names[0])),
        n => Some(format!("with {} and {}", coauthor_names[..n - 1].join(", "), coauthor_names[n - 1])),
    }
}

/// The first words of a post for a card: a quick post's text, an article's subtitle or opening, cut at a word.
#[uniffi::export]
pub fn jam_excerpt(post: JamPostInfo, limit: u32) -> String {
    let limit = limit as usize;
    let body = post.plain.replace('\n', " ");
    let body = body.trim();
    let source = if post.kind == "article" && !post.subtitle.trim().is_empty() { post.subtitle.trim() } else { body };
    if source.chars().count() <= limit {
        return source.to_owned();
    }
    let cut: String = source.chars().take(limit).collect();
    let at = cut.rfind(' ').filter(|i| cut[..*i].chars().count() > limit / 2).unwrap_or(cut.len());
    format!("{}…", cut[..at].trim_end())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ok(kind: &str, files: &[&str], segment: JamFeedSegment, filter: JamFeedFilter) -> bool {
        jam_filter_matches(kind.into(), files.iter().map(|s| (*s).to_owned()).collect(), false, false, true, false, segment, filter)
    }

    fn flags(kind: &str, coauthored: bool, as_jam: bool, subscribed: bool, saved: bool, filter: JamFeedFilter) -> bool {
        jam_filter_matches(kind.into(), vec![], coauthored, as_jam, subscribed, saved, JamFeedSegment::All, filter)
    }

    // ios/LimeTests/JamFilterTests.swift
    #[test]
    fn the_segments_split_by_kind() {
        use JamFeedSegment::*;
        let none = JamFeedFilter::default;
        for kind in ["quick", "article", "record"] {
            assert!(ok(kind, &[], All, none()), "All has {kind}");
        }
        assert!(ok("quick", &[], Posts, none()) && !ok("article", &[], Posts, none()) && !ok("record", &[], Posts, none()));
        assert!(ok("article", &[], Articles, none()) && !ok("quick", &[], Articles, none()));
        assert!(ok("record", &["audio"], Podcasts, none()) && !ok("quick", &[], Podcasts, none()));
        assert_eq!(jam_segments().into_iter().map(jam_segment_title).collect::<Vec<_>>(), ["All", "Posts", "Articles", "Podcasts", "Drafts", "Discover"]);
        assert!(!ok("quick", &[], Drafts, none()) && !ok("quick", &[], Discover, none()), "Drafts and Discover list other things, not the feed");
    }

    #[test]
    fn media_narrows_and_an_article_ignores_it() {
        use JamFeedSegment::*;
        let media = |m| JamFeedFilter { media: Some(m), ..Default::default() };
        assert!(ok("record", &["audio"], All, media(JamFeedMedia::Audio)));
        assert!(!ok("record", &["video"], All, media(JamFeedMedia::Audio)));
        assert!(ok("quick", &["image", "image"], All, media(JamFeedMedia::Photos)));
        assert!(ok("record", &["video"], Podcasts, media(JamFeedMedia::Video)));
        assert!(ok("article", &[], All, media(JamFeedMedia::Audio)));
    }

    #[test]
    fn coauthored_subscribed_orgs_and_saved() {
        let f = |co, sub, orgs, saved| JamFeedFilter { media: None, coauthored: co, subscribed: sub, orgs, saved };
        assert!(!flags("quick", false, false, true, false, f(true, false, false, false)));
        assert!(flags("article", true, false, true, false, f(true, false, false, false)));
        assert!(!flags("quick", false, false, false, false, f(false, true, false, false)), "my own jam is not a subscription");
        assert!(flags("quick", false, false, true, false, f(false, true, false, false)));
        assert!(flags("quick", false, true, true, false, f(false, false, true, false)));
        assert!(!flags("quick", false, false, true, false, f(false, false, true, false)));
        assert!(flags("article", false, false, true, true, f(false, false, false, true)));
        assert!(!flags("article", false, false, true, false, f(false, false, false, true)));
        assert_eq!(jam_filter_active_count(JamFeedFilter { media: Some(JamFeedMedia::Audio), coauthored: true, subscribed: true, orgs: true, saved: true }), 5);
        assert_eq!(jam_filter_active_count(JamFeedFilter::default()), 0);
    }

    // ios/LimeTests/JamCardChoiceTests.swift
    #[test]
    fn a_video_recording_is_a_big_card_and_an_audio_one_the_small_card() {
        assert_eq!(jam_card_kind(true, true, false, true), JamCardKind::VideoPodcast);
        assert_eq!(jam_card_kind(true, true, true, false), JamCardKind::SmallPodcast);
        assert_eq!(jam_card_kind(true, true, true, true), JamCardKind::SmallPodcast, "a recording with sound and picture files is the audio one");
        assert_eq!(jam_card_kind(false, true, false, true), JamCardKind::Regular);
        assert_eq!(jam_card_kind(true, false, false, true), JamCardKind::Regular);
        assert_eq!(jam_card_kind(true, true, false, false), JamCardKind::Regular, "nothing to play");
    }

    fn jam(id: &str, mine: bool, status: &str) -> JamInfo {
        JamInfo {
            jam_id: id.into(),
            conversation_id: format!("jam:{id}"),
            writer: "w".into(),
            title: id.into(),
            about: String::new(),
            topics: vec![],
            tiers: vec![],
            mine,
            status: status.into(),
            ended: false,
            community: false,
            community_state: None,
            community_group: None,
            subscriber_count: 0,
            post_count: 0,
            created: 0,
        }
    }

    fn post(id: &str, jam: &str, at: i64, state: &str) -> JamPostInfo {
        JamPostInfo {
            post_id: id.into(),
            jam_id: jam.into(),
            author: "w".into(),
            tier: "free".into(),
            kind: "quick".into(),
            title: String::new(),
            subtitle: String::new(),
            markdown: "A short post".into(),
            plain: "A short post".into(),
            attachments_json: "[]".into(),
            created: at,
            coauthors: vec![],
            display_as: "person".into(),
            edited_at: 0,
            audience: "subscribers".into(),
            series: None,
            topics: vec![],
            state: state.into(),
        }
    }

    // JamAndProfileTest.theFeedHoldsTheReadyPostsOfActiveAndOwnJamsNewestFirst
    #[test]
    fn the_feed_holds_the_ready_posts_of_active_and_own_jams_newest_first() {
        let jams = vec![jam("a", false, "active"), jam("b", false, "requested"), jam("c", true, "active"), jam("d", false, "removed")];
        let posts = vec![post("p1", "a", 100, "ready"), post("p2", "b", 900, "ready"), post("p3", "c", 300, "ready"), post("p4", "d", 400, "ready"), post("p5", "a", 200, "pending"), post("p1", "a", 100, "ready")];
        assert_eq!(jam_feed_posts(posts, jams).into_iter().map(|p| p.post_id).collect::<Vec<_>>(), ["p3", "p1"], "requested/removed jams, a post still arriving, and a repeat are out");
    }

    // JamAndProfileTest.bylineNamesTheCoauthors / anExcerptIsCutAtAWord
    #[test]
    fn the_byline_names_the_coauthors() {
        assert_eq!(jam_byline(vec![]), None);
        assert_eq!(jam_byline(vec!["Jean Chung".into()]).as_deref(), Some("with Jean Chung"));
        assert_eq!(jam_byline(vec!["Jean Chung".into(), "Lee Wong".into()]).as_deref(), Some("with Jean Chung and Lee Wong"));
        assert_eq!(jam_byline(vec!["A".into(), "B".into(), "C".into()]).as_deref(), Some("with A, B and C"));
    }

    #[test]
    fn an_excerpt_is_cut_at_a_word() {
        let mut long = post("p", "j", 0, "ready");
        long.plain = "word ".repeat(100);
        let cut = jam_excerpt(long, 50);
        assert!(cut.ends_with('…') && cut.chars().count() <= 51 && !cut.trim_end_matches('…').ends_with(' '));
        assert_eq!(jam_excerpt(post("q", "j", 0, "ready"), 280), "A short post");
        let mut article = post("r", "j", 0, "ready");
        article.kind = "article".into();
        article.subtitle = "The subtitle".into();
        article.plain = "Body text here".into();
        assert_eq!(jam_excerpt(article, 280), "The subtitle");
    }
}
