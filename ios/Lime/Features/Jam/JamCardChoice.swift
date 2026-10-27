import Foundation

/// Where a card is drawn (LIME-203): the main feed (All), a filter, a profile's tab, an org's page. The one place that decides which kind of card a post
/// gets, so later discovery layouts reuse it instead of each view deciding for itself.
enum JamCardPlace: Equatable {
    case feed(JamSegment), profileTab(JamSegment), orgPage(JamSegment)

    var segment: JamSegment {
        switch self { case .feed(let s), .profileTab(let s), .orgPage(let s): s }
    }
}

enum JamCardStyle: Equatable {
    /// An article cover, a quick post, anything that is not a recording.
    case regular
    /// The compact podcast card (LIME-200): cover, org, title, a play pill.
    case smallPodcast
    /// A video recording drawn as a video: the framed player, with the org and title under it (LIME-203).
    case videoPodcast
}

enum JamCardChoice {
    /// A recording with audio keeps the small card everywhere; a video recording is a **video card in the main feed** and a small card in the Podcasts
    /// filter and a profile's Podcasts tab, where a compact list is easier to scan. Anything else is a regular card.
    static func style(isRecording: Bool, ready: Bool, hasAudio: Bool, hasVideo: Bool, place: JamCardPlace) -> JamCardStyle {
        guard isRecording, ready, hasAudio || hasVideo else { return .regular }
        // The big video card everywhere, under Podcasts too (the user's answer A, 2026-10-27).
        if hasVideo && !hasAudio { return .videoPodcast }
        return .smallPodcast
    }
}
