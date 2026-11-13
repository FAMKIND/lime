//! The rules of calls (LIME-423): everything about a call that is not media or the system's own screen, as pure functions both apps can
//! use. Ported from iOS (`CallManager.swift`, `CallLog.swift`, `CallGrouping.swift`, `CallsTab.swift`, `Model/CallBubble.swift`,
//! `PiPGridPlan.swift`, `CallAccessibility.swift`) and tested with the iOS test cases (`CallTests`, `CallHistoryTests`,
//! `CallBackActionTests`, `CallBubbleTests`, `PiPGridPlanTests`).
//!
//! What stays in the platform: the media (WebRTC, LiveKit), the audio session and routing, the system call screen, the clock and the
//! calendar's *formatting* (the rules here say which kind of label a time gets; the app writes "4:12 PM" in the person's locale), the
//! mailbox polling and the tile geometry of the group call screen.
//!
//! The 1:1 machine takes the state, an event and the time, and returns the new state and a list of actions for the platform to carry
//! out; it holds no timers or tasks of its own, so every phase and timeout is testable without waiting.

// ---------------------------------------------------------------------------------------------------- the constants

/// How long "Calling…" waits for `call.ringing` before the hint "may be off or lime closed" shows.
pub const CALL_HINT_SECONDS: f64 = 10.0;
/// How long a call rings (outgoing: no answer; incoming: missed).
pub const CALL_RING_SECONDS: f64 = 45.0;
/// How long the media path may take to come up after an answer.
pub const CALL_CONNECT_SECONDS: f64 = 30.0;
/// How long the caller sees "<Name> has Do Not Disturb on" before the call closes.
pub const CALL_UNAVAILABLE_SECONDS: f64 = 2.0;
/// A second call from a person this phone silenced rings if it comes within this many seconds.
pub const CALL_BREAKTHROUGH_SECONDS: f64 = 180.0;
/// How long one op may take to handle before the queue moves on.
pub const CALL_HANDLER_SECONDS: f64 = 3.0;
/// How many people a group call shows as a grid before it starts in speaker view with the camera off.
pub const GROUP_CALL_GRID_LIMIT: u32 = 12;
/// How long the grid stays lightened after the phone cools down (seconds).
pub const PIP_HEAT_CALM_SECONDS: f64 = 120.0;

/// The same numbers as one record, for a platform that wants them all.
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct CallTimeouts {
    pub hint_seconds: f64,
    pub ring_seconds: f64,
    pub connect_seconds: f64,
    pub unavailable_seconds: f64,
    pub breakthrough_seconds: f64,
    pub handler_seconds: f64,
}

#[uniffi::export]
pub fn call_timeouts() -> CallTimeouts {
    CallTimeouts {
        hint_seconds: CALL_HINT_SECONDS,
        ring_seconds: CALL_RING_SECONDS,
        connect_seconds: CALL_CONNECT_SECONDS,
        unavailable_seconds: CALL_UNAVAILABLE_SECONDS,
        breakthrough_seconds: CALL_BREAKTHROUGH_SECONDS,
        handler_seconds: CALL_HANDLER_SECONDS,
    }
}

// ---------------------------------------------------------------------------------------------------- outcomes and words

/// How a call ended, for the chat's call line and the Calls list.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, uniffi::Enum)]
pub enum CallResult {
    Completed,
    Missed,
    Declined,
    NoAnswer,
    Busy,
    Failed,
    /// An incoming call this phone did not ring for: Do Not Disturb.
    MissedDnd,
    /// An incoming call this phone did not ring for: outside work hours.
    MissedHours,
    /// A call I placed to someone in Do Not Disturb or outside work hours.
    Unavailable,
}

/// Why a phone is not ringing.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, uniffi::Enum)]
pub enum CallQuietKind {
    Dnd,
    WorkHours,
}

/// The stored word for an outcome (`call_history.outcome`, the chat call body's `outcome`): `completed`, `missed`, `declined`,
/// `noAnswer`, `busy`, `failed`, `missed_dnd`, `missed_hours`, `unavailable` (these are iOS's raw values, kept exactly).
#[uniffi::export]
pub fn call_result_raw(result: CallResult) -> String {
    match result {
        CallResult::Completed => "completed",
        CallResult::Missed => "missed",
        CallResult::Declined => "declined",
        CallResult::NoAnswer => "noAnswer",
        CallResult::Busy => "busy",
        CallResult::Failed => "failed",
        CallResult::MissedDnd => "missed_dnd",
        CallResult::MissedHours => "missed_hours",
        CallResult::Unavailable => "unavailable",
    }
    .to_string()
}

/// The outcome of a stored word; `None` for a word this version does not know.
#[uniffi::export]
pub fn call_result_parse(raw: String) -> Option<CallResult> {
    Some(match raw.as_str() {
        "completed" => CallResult::Completed,
        "missed" => CallResult::Missed,
        "declined" => CallResult::Declined,
        "noAnswer" => CallResult::NoAnswer,
        "busy" => CallResult::Busy,
        "failed" => CallResult::Failed,
        "missed_dnd" => CallResult::MissedDnd,
        "missed_hours" => CallResult::MissedHours,
        "unavailable" => CallResult::Unavailable,
        _ => return None,
    })
}

/// The stored word for a quiet reason (`dnd`, `work_hours`), as it travels in `call.unavailable`.
#[uniffi::export]
pub fn call_quiet_raw(kind: CallQuietKind) -> String {
    match kind {
        CallQuietKind::Dnd => "dnd",
        CallQuietKind::WorkHours => "work_hours",
    }
    .to_string()
}

#[uniffi::export]
pub fn call_quiet_parse(raw: String) -> Option<CallQuietKind> {
    match raw.as_str() {
        "dnd" => Some(CallQuietKind::Dnd),
        "work_hours" => Some(CallQuietKind::WorkHours),
        _ => None,
    }
}

/// The outcome of an incoming call this phone did not ring for.
#[uniffi::export]
pub fn call_quiet_result(kind: CallQuietKind) -> CallResult {
    match kind {
        CallQuietKind::Dnd => CallResult::MissedDnd,
        CallQuietKind::WorkHours => CallResult::MissedHours,
    }
}

/// Counts as a missed incoming call (the Missed filter and the tab's badge): missed, and the two silenced ones; not "unavailable".
#[uniffi::export]
pub fn call_result_is_missed(result: CallResult) -> bool {
    matches!(result, CallResult::Missed | CallResult::MissedDnd | CallResult::MissedHours)
}

/// "Silenced · Do Not Disturb" / "Silenced · Work hours" for a call this phone did not ring for.
#[uniffi::export]
pub fn call_result_silenced_note(result: CallResult) -> Option<String> {
    match result {
        CallResult::MissedDnd => Some("Silenced \u{00B7} Do Not Disturb".to_string()),
        CallResult::MissedHours => Some("Silenced \u{00B7} Work hours".to_string()),
        _ => None,
    }
}

/// "4:12" or "1:04:12": a length of time as a call clock.
#[uniffi::export]
pub fn call_clock(seconds: f64) -> String {
    let total = seconds.round().max(0.0) as i64;
    if total >= 3600 {
        format!("{}:{:02}:{:02}", total / 3600, (total % 3600) / 60, total % 60)
    } else {
        format!("{}:{:02}", total / 60, total % 60)
    }
}

/// One call, kept on this phone (the Calls tab and the chat's timeline).
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct CallLogEntry {
    pub id: String,
    pub peer_id: String,
    pub peer_name: String,
    pub video: bool,
    pub outgoing: bool,
    pub at_ms: i64,
    pub duration_ms: i64,
    pub result: CallResult,
}

impl CallLogEntry {
    fn missed_incoming(&self) -> bool {
        !self.outgoing && call_result_is_missed(self.result)
    }
}

/// The call as a line (the Messages row, a chat's quote): "Voice call · 4:12", "Missed call", "Declined call", "No answer", "<Name> was busy".
#[uniffi::export]
pub fn call_log_line(entry: CallLogEntry) -> String {
    let kind = if entry.video { "Video call" } else { "Voice call" };
    let video_word = if entry.video { "video " } else { "" };
    match entry.result {
        CallResult::Completed => format!("{kind} \u{00B7} {}", call_clock(entry.duration_ms as f64 / 1000.0)),
        CallResult::Missed | CallResult::MissedDnd | CallResult::MissedHours => {
            if entry.outgoing { "No answer".to_string() } else { format!("Missed {video_word}call") }
        }
        CallResult::Declined => {
            if entry.outgoing { format!("{kind} declined") } else { format!("Declined {video_word}call") }
        }
        CallResult::NoAnswer => "No answer".to_string(),
        CallResult::Busy => format!("{} was busy", entry.peer_name),
        CallResult::Failed => format!("{kind} failed"),
        CallResult::Unavailable => "Unavailable".to_string(),
    }
}

/// The words for a call in the details list: the length, or what became of it.
#[uniffi::export]
pub fn call_log_outcome_text(entry: CallLogEntry) -> String {
    match entry.result {
        CallResult::Completed => call_clock(entry.duration_ms as f64 / 1000.0),
        CallResult::Missed => if entry.outgoing { "No answer" } else { "Missed" }.to_string(),
        CallResult::MissedDnd | CallResult::MissedHours => {
            if entry.outgoing { "No answer".to_string() } else { call_result_silenced_note(entry.result).unwrap_or_else(|| "Missed".to_string()) }
        }
        CallResult::Unavailable => "Unavailable".to_string(),
        CallResult::Declined => "Declined".to_string(),
        CallResult::NoAnswer => "No answer".to_string(),
        CallResult::Busy => "Busy".to_string(),
        CallResult::Failed => "Failed".to_string(),
    }
}

/// The note under a history row's name: the silenced words, or "Unavailable".
#[uniffi::export]
pub fn call_log_row_note(result: CallResult) -> Option<String> {
    call_result_silenced_note(result).or_else(|| (result == CallResult::Unavailable).then(|| "Unavailable".to_string()))
}

// ---------------------------------------------------------------------------------------------------- the chat's call bubble

/// A call as the chat shows it (`Model/CallBubble.swift`).
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct CallBubbleWords {
    pub title: String,
    pub detail: String,
    pub summary: String,
    pub is_missed_incoming: bool,
    pub is_group: bool,
    pub live: bool,
    pub video: bool,
    pub started_by: Option<String>,
}

fn bubble(video: bool, duration_ms: i64, result: CallResult, mine: bool, is_group: bool, live: bool, started_by: Option<String>) -> CallBubbleWords {
    let missed_incoming = !is_group && !mine && call_result_is_missed(result);
    let kind = if video { "video" } else { "voice" };
    let title = if is_group {
        if live { "Group call".to_string() } else { "Call ended".to_string() }
    } else if missed_incoming {
        format!("Missed {kind} call")
    } else if video {
        "Video call".to_string()
    } else {
        "Voice call".to_string()
    };
    let detail = match result {
        CallResult::Completed => call_clock(duration_ms as f64 / 1000.0),
        CallResult::Missed => if mine { "Cancelled" } else { "Missed" }.to_string(),
        CallResult::MissedDnd | CallResult::MissedHours => {
            if mine { "Cancelled".to_string() } else { call_result_silenced_note(result).unwrap_or_else(|| "Missed".to_string()) }
        }
        CallResult::Unavailable => "Unavailable".to_string(),
        CallResult::NoAnswer => "No answer".to_string(),
        CallResult::Declined => "Declined".to_string(),
        CallResult::Busy => "Busy".to_string(),
        CallResult::Failed => "Failed".to_string(),
    };
    let summary = if missed_incoming {
        title.clone()
    } else if is_group && live {
        "Group call \u{00B7} Join".to_string()
    } else {
        format!("{title} \u{00B7} {detail}")
    };
    CallBubbleWords { title, detail, summary, is_missed_incoming: missed_incoming, is_group, live, video, started_by }
}

/// The words of a 1:1 call in a chat.
#[uniffi::export]
pub fn call_bubble_words(video: bool, duration_ms: i64, result: CallResult, mine: bool) -> CallBubbleWords {
    bubble(video, duration_ms, result, mine, false, false, None)
}

/// The words of a call from the core's body JSON (`{"video":true,"duration_ms":23000,"outcome":"completed","outgoing":true}`, or for a
/// group `{"group":true,"outcome":"live","started_by":"<id>"}`); `None` for a body that is not a call or has an unknown outcome.
#[uniffi::export]
pub fn call_bubble_from_body(body: String, mine: bool) -> Option<CallBubbleWords> {
    let json: serde_json::Value = serde_json::from_str(&body).ok()?;
    let raw = json.get("outcome")?.as_str()?;
    let is_group = json.get("group").and_then(serde_json::Value::as_bool).unwrap_or(false);
    let live = is_group && raw == "live";
    let result = call_result_parse(if live { "completed".to_string() } else { raw.to_string() })?;
    let video = json.get("video").and_then(serde_json::Value::as_bool).unwrap_or(false);
    let duration_ms = json.get("duration_ms").and_then(serde_json::Value::as_i64).unwrap_or(0);
    let started_by = json.get("started_by").and_then(serde_json::Value::as_str).map(str::to_owned);
    Some(bubble(video, duration_ms, result, mine, is_group, live, started_by))
}

/// The title of a group call in a chat, given the starter's name: my own card reads "Call started", someone else's "<Name> started a call".
#[uniffi::export]
pub fn call_bubble_title(words: CallBubbleWords, mine: bool, started_by_name: Option<String>) -> String {
    if !words.is_group {
        return words.title;
    }
    if words.live {
        if mine { "Call started".to_string() } else { format!("{} started a call", started_by_name.unwrap_or_else(|| "Someone".to_string())) }
    } else {
        "Call ended".to_string()
    }
}

/// The second line of a chat's call bubble: "Join" while a group call is on.
#[uniffi::export]
pub fn call_bubble_chat_detail(words: CallBubbleWords) -> String {
    if words.is_group && words.live { "Join".to_string() } else { words.detail }
}

/// "Jean is there", "Jean and Lee are there", "Jean, Lee and 2 others are there"; just a count when the names are not known.
#[uniffi::export]
pub fn call_live_card_who(names: Vec<String>, count: u32, i_am_in: bool) -> String {
    if i_am_in && names.is_empty() && count <= 1 {
        return "Waiting for others".to_string();
    }
    let firsts: Vec<String> = names.iter().map(|n| n.split(' ').find(|s| !s.is_empty()).unwrap_or(n).to_string()).collect();
    match (firsts.len(), count) {
        (0, 0) => "Nobody is there yet".to_string(),
        (0, 1) => "1 person is there".to_string(),
        (0, c) => format!("{c} people are there"),
        (1, c) => {
            let mut s = format!("{} is there", firsts[0]);
            if c > 1 {
                s.push_str(&format!(" and {} other{}", c - 1, if c - 1 == 1 { "" } else { "s" }));
            }
            s
        }
        (2, c) if c <= 2 => format!("{} and {} are there", firsts[0], firsts[1]),
        (n, c) => {
            let others = (c as i64 - 2).max(n as i64 - 2);
            format!("{}, {} and {} other{} are there", firsts[0], firsts[1], others, if others == 1 { "" } else { "s" })
        }
    }
}

// ---------------------------------------------------------------------------------------------------- history grouping

/// Consecutive calls with the same person, of the same kind, on the same day, that were all missed or all not missed: one row with a
/// count (Apple's rule, `CallGrouping.swift`).
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct CallLogGroup {
    /// The newest call's id.
    pub id: String,
    /// Newest first.
    pub entries: Vec<CallLogEntry>,
    pub is_missed_incoming: bool,
}

fn day_of(at_ms: i64, tz_offset_seconds: i32) -> i64 {
    (at_ms.div_euclid(1000) + tz_offset_seconds as i64).div_euclid(86_400)
}

/// The history as rows: newest first, neighbours merged by the rule above. `tz_offset_seconds` is the phone's offset from UTC (the
/// "same day" is the person's day).
#[uniffi::export]
pub fn call_log_groups(entries: Vec<CallLogEntry>, tz_offset_seconds: i32) -> Vec<CallLogGroup> {
    let mut sorted = entries;
    sorted.sort_by(|a, b| b.at_ms.cmp(&a.at_ms));
    let mut result: Vec<Vec<CallLogEntry>> = Vec::new();
    for entry in sorted {
        let merges = result.last().and_then(|g| g.first()).is_some_and(|last| {
            last.peer_id == entry.peer_id
                && last.video == entry.video
                && day_of(last.at_ms, tz_offset_seconds) == day_of(entry.at_ms, tz_offset_seconds)
                && last.missed_incoming() == entry.missed_incoming()
        });
        if merges {
            result.last_mut().expect("checked").push(entry);
        } else {
            result.push(vec![entry]);
        }
    }
    result.into_iter().map(|g| CallLogGroup { id: g[0].id.clone(), is_missed_incoming: g[0].missed_incoming(), entries: g }).collect()
}

/// Which kind of label the time at the right of a row gets (the app writes it in the person's locale).
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum CallTimeLabel {
    /// Today: the time, "4:12 PM".
    Time,
    Yesterday,
    /// Within seven days: the weekday's name.
    Weekday,
    /// Older: a short numeric date.
    Date,
}

#[uniffi::export]
pub fn call_time_label_kind(at_ms: i64, now_ms: i64, tz_offset_seconds: i32) -> CallTimeLabel {
    let back = day_of(now_ms, tz_offset_seconds) - day_of(at_ms, tz_offset_seconds);
    match back {
        0 => CallTimeLabel::Time,
        1 => CallTimeLabel::Yesterday,
        // The iOS rule: a date on or after the start of the day seven days ago; a call from the future counts as today's.
        2..=7 => CallTimeLabel::Weekday,
        b if b < 0 => CallTimeLabel::Time,
        _ => CallTimeLabel::Date,
    }
}

/// A call's date on one short line (the profile's call rows), as a kind: today "11:01 AM"; "Yesterday 11:01 AM"; else "Oct 11, 11:01 AM"
/// with the year only when it is not this year.
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum CallShortDate {
    Time,
    YesterdayTime,
    DateTime { with_year: bool },
}

#[uniffi::export]
pub fn call_short_date_kind(at_ms: i64, now_ms: i64, tz_offset_seconds: i32, same_year: bool) -> CallShortDate {
    match day_of(now_ms, tz_offset_seconds) - day_of(at_ms, tz_offset_seconds) {
        0 => CallShortDate::Time,
        1 => CallShortDate::YesterdayTime,
        _ => CallShortDate::DateTime { with_year: !same_year },
    }
}

// ---------------------------------------------------------------------------------------------------- what tapping a call does

/// What tapping a call in the history does (LIME-170): a person is called again the same way; a group is joined if its call is on now,
/// else a new one is started.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Enum)]
pub enum CallBackChoice {
    CallPerson,
    JoinGroup { call_id: String },
    StartGroup,
}

#[uniffi::export]
pub fn call_back_choice(is_group: bool, live_call_id: Option<String>) -> CallBackChoice {
    if !is_group {
        return CallBackChoice::CallPerson;
    }
    match live_call_id {
        Some(call_id) => CallBackChoice::JoinGroup { call_id },
        None => CallBackChoice::StartGroup,
    }
}

/// A history row of a group's call carries the group's conversation id.
#[uniffi::export]
pub fn call_peer_is_group(peer_id: String) -> bool {
    peer_id.starts_with("grp:")
}

// ---------------------------------------------------------------------------------------------------- small call rules

/// The `a=fingerprint:` value of an SDP (upper-case), the DTLS key that protects the media; `None` when there is none.
#[uniffi::export]
pub fn call_fingerprint(sdp: String) -> Option<String> {
    for line in sdp.lines() {
        let text = line.trim();
        if let Some(rest) = text.strip_prefix("a=fingerprint:") {
            let (_algorithm, value) = rest.split_once(' ')?;
            return Some(value.to_uppercase());
        }
    }
    None
}

/// Always relay calls: with it on and no relay credentials the call fails clearly and never goes direct. `true` when the call may go on.
#[uniffi::export]
pub fn call_relay_allowed(always_relay: bool, has_relay_credentials: bool) -> bool {
    !always_relay || has_relay_credentials
}

/// What the person is told when "Always relay calls" is on and the relay cannot be reached.
#[uniffi::export]
pub fn call_relay_unavailable_words() -> String {
    "Can\u{2019}t reach lime\u{2019}s relay. Turn off Always relay calls to call directly.".to_string()
}

/// Whether a group call rings this phone: the core says whether the group is small enough (`group_call_rings`), and a silenced phone
/// does not ring (the chat line still shows the call).
#[uniffi::export]
pub fn group_call_should_ring(member_count: u32, quiet: Option<CallQuietKind>) -> bool {
    crate::client::group_calls::group_call_rings(member_count) && quiet.is_none()
}

/// A group call with more people than this starts in speaker view with the camera off.
#[uniffi::export]
pub fn group_call_starts_in_speaker_view(people: u32) -> bool {
    people > GROUP_CALL_GRID_LIMIT
}

/// What names the group call on screen: the group's own name when a person chose it, else the first names of the people in the call.
#[uniffi::export]
pub fn group_call_title(group_name: String, name_is_custom: bool, names: Vec<String>) -> String {
    if name_is_custom || names.is_empty() {
        return group_name;
    }
    names.iter().map(|n| n.split(' ').find(|s| !s.is_empty()).unwrap_or(n).to_string()).collect::<Vec<_>>().join(", ")
}

// ---------------------------------------------------------------------------------------------------- the 1:1 machine

/// Where a call is.
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum CallPhaseKind {
    Idle,
    /// I called; waiting for them to answer.
    Outgoing,
    /// They are calling; waiting for me.
    Incoming,
    /// Answered; the media path is coming up.
    Connecting,
    Active,
}

/// Timers the platform runs for the machine; the machine asks for one with `ArmTimer` and is told with the event `Timer`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum CallTimerKind {
    /// "Calling…" without a sign of ringing.
    Hint,
    /// Ringing for too long.
    Ring,
    /// The media path took too long.
    Connect,
    /// The caller has seen "has Do Not Disturb on" long enough.
    Unavailable,
}

/// A person who called while this phone was silenced, and when.
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct CallSilenced {
    pub peer_id: String,
    pub at_ms: i64,
}

/// Everything the machine remembers.
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct CallMachineState {
    pub phase: CallPhaseKind,
    pub call_id: String,
    pub peer_id: String,
    pub peer_name: String,
    pub video: bool,
    pub outgoing: bool,
    /// The other phone is ringing (it sent `call.ringing`).
    pub remote_ringing: bool,
    /// Ten seconds of "Calling…" with no sign of ringing.
    pub unreachable_hint: bool,
    /// Set on the caller's side once the other phone said it will not ring.
    pub unavailable: Option<CallQuietKind>,
    pub started_at_ms: Option<i64>,
    pub silenced: Vec<CallSilenced>,
}

#[uniffi::export]
pub fn call_machine_new() -> CallMachineState {
    CallMachineState {
        phase: CallPhaseKind::Idle,
        call_id: String::new(),
        peer_id: String::new(),
        peer_name: String::new(),
        video: false,
        outgoing: false,
        remote_ringing: false,
        unreachable_hint: false,
        unavailable: None,
        started_at_ms: None,
        silenced: Vec::new(),
    }
}

/// What happened.
#[derive(Debug, Clone, PartialEq, uniffi::Enum)]
pub enum CallMachineEvent {
    /// The person taps Call.
    TapCall { call_id: String, peer_id: String, peer_name: String, video: bool },
    /// The platform's start went out: ice servers, media, offer, `call.offer` sent.
    OfferSent,
    /// Any of those failed.
    OfferFailed,
    /// `call.offer` arrived. `my_id` is this account's user id (glare); `quiet` is why this phone must not ring, if it must not.
    OfferReceived { call_id: String, peer_id: String, peer_name: String, video: bool, my_id: String, quiet: Option<CallQuietKind> },
    /// The platform showed the incoming call (screen or notification): tell the caller this phone is ringing.
    RingShown,
    /// The system refused to ring (a Focus or a missing permission): a missed call.
    RingRefused,
    /// The person taps Answer.
    TapAnswer,
    /// The platform's answer went out (`call.answer` sent).
    AnswerSent,
    /// Building or sending the answer failed.
    AnswerFailed,
    /// The person taps Decline.
    TapDecline,
    /// The person taps End (or cancels before an answer).
    TapHangUp,
    SignalRinging { call_id: String, peer_id: String },
    SignalAnswer { call_id: String, peer_id: String },
    /// The platform could not apply the answer.
    AnswerApplyFailed,
    SignalEnd { call_id: String, peer_id: String },
    SignalDecline { call_id: String, peer_id: String },
    SignalBusy { call_id: String, peer_id: String },
    SignalUnavailable { call_id: String, peer_id: String, reason: CallQuietKind },
    /// The media path is up.
    MediaUp,
    /// The media path failed.
    MediaFailed,
    /// "Always relay calls" is on and the relay has no credentials.
    RelayUnavailable,
    Timer { kind: CallTimerKind },
}

/// What the platform is asked to do, in order.
#[derive(Debug, Clone, PartialEq, uniffi::Enum)]
pub enum CallMachineAction {
    /// Get the ice servers, start the media, make the offer, send `call.offer`; then tell the machine `OfferSent` or `OfferFailed`.
    StartOutgoing,
    /// Show the incoming call; then tell the machine `RingShown` or `RingRefused`.
    ShowIncoming,
    /// Get the ice servers, start the media, make the answer, send `call.answer`; then `AnswerSent` or `AnswerFailed`.
    AcceptIncoming,
    /// Apply the answer to the media (and its candidates); `AnswerApplyFailed` if that fails.
    ApplyAnswer,
    /// Send one control op to the other phone (`call.ringing`, `call.busy`, `call.decline`, `call.end`, `call.unavailable`).
    Send { op: String, call_id: String, peer_id: String, reason: Option<String> },
    StartRingback,
    StopRingback,
    StartPolling,
    StopPolling,
    ArmTimer { kind: CallTimerKind, seconds: f64 },
    CancelTimer { kind: CallTimerKind },
    /// Say it (a TalkBack live region).
    Announce { words: String },
    /// Write the call into the history (the core's `call_history_add`).
    Log { entry: CallLogEntry },
    /// Close the media, the route and the foreground service; the call is over.
    TearDown,
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct CallMachineStep {
    pub state: CallMachineState,
    pub actions: Vec<CallMachineAction>,
}

fn in_call(state: &CallMachineState) -> bool {
    state.phase != CallPhaseKind::Idle
}

/// What to say when the phase changes; `None` for no speech.
#[uniffi::export]
pub fn call_phase_announcement(old: CallPhaseKind, new: CallPhaseKind) -> Option<String> {
    if old == new {
        return None;
    }
    match new {
        CallPhaseKind::Idle => (old != CallPhaseKind::Idle).then(|| "Call ended".to_string()),
        CallPhaseKind::Outgoing => Some("Calling\u{2026}".to_string()),
        CallPhaseKind::Incoming => None,
        CallPhaseKind::Connecting => Some("Connecting\u{2026}".to_string()),
        CallPhaseKind::Active => Some("Connected".to_string()),
    }
}

/// What the visible line says when the phone may be off.
#[uniffi::export]
pub fn call_unreachable_words(name: String) -> String {
    format!("{name}\u{2019}s phone may be off or lime closed")
}

/// What the caller sees once the other phone said it will not ring.
#[uniffi::export]
pub fn call_unavailable_words(name: String, reason: CallQuietKind) -> String {
    match reason {
        CallQuietKind::WorkHours => format!("{name} is outside work hours"),
        CallQuietKind::Dnd => format!("{name} has Do Not Disturb on"),
    }
}

/// The line under the name: Calling… → Ringing… → Connecting… → the timer; an incoming call says what it is.
#[uniffi::export]
pub fn call_status_text(state: CallMachineState, now_ms: i64) -> String {
    match state.phase {
        CallPhaseKind::Idle => String::new(),
        CallPhaseKind::Outgoing => match state.unavailable {
            Some(reason) => call_unavailable_words(state.peer_name.clone(), reason),
            None => if state.remote_ringing { "Ringing\u{2026}" } else { "Calling\u{2026}" }.to_string(),
        },
        CallPhaseKind::Incoming => if state.video { "lime video call" } else { "lime voice call" }.to_string(),
        CallPhaseKind::Connecting => "Connecting\u{2026}".to_string(),
        CallPhaseKind::Active => call_clock(((now_ms - state.started_at_ms.unwrap_or(now_ms)) as f64) / 1000.0),
    }
}

fn begin(state: &mut CallMachineState, outgoing: bool, call_id: String, peer_id: String, peer_name: String, video: bool) {
    state.phase = if outgoing { CallPhaseKind::Outgoing } else { CallPhaseKind::Incoming };
    state.call_id = call_id;
    state.peer_id = peer_id;
    state.peer_name = peer_name;
    state.video = video;
    state.outgoing = outgoing;
    state.remote_ringing = false;
    state.unreachable_hint = false;
    state.unavailable = None;
    state.started_at_ms = None;
}

fn send(op: &str, call_id: &str, peer_id: &str, reason: Option<String>) -> CallMachineAction {
    CallMachineAction::Send { op: op.to_string(), call_id: call_id.to_string(), peer_id: peer_id.to_string(), reason }
}

/// Ends the call on this phone: stops what runs, writes the history and tears down. Returns the actions; the caller adds the `call.end`
/// when the other phone has to be told.
fn finish(state: &mut CallMachineState, result: CallResult, now_ms: i64, actions: &mut Vec<CallMachineAction>) {
    if !in_call(state) {
        return;
    }
    for kind in [CallTimerKind::Ring, CallTimerKind::Connect, CallTimerKind::Hint, CallTimerKind::Unavailable] {
        actions.push(CallMachineAction::CancelTimer { kind });
    }
    actions.push(CallMachineAction::StopRingback);
    actions.push(CallMachineAction::StopPolling);
    let duration_ms = state.started_at_ms.map(|s| (now_ms - s).max(0)).unwrap_or(0);
    actions.push(CallMachineAction::Log {
        entry: CallLogEntry {
            id: state.call_id.clone(),
            peer_id: state.peer_id.clone(),
            peer_name: state.peer_name.clone(),
            video: state.video,
            outgoing: state.outgoing,
            at_ms: state.started_at_ms.unwrap_or(now_ms),
            duration_ms,
            result,
        },
    });
    actions.push(CallMachineAction::TearDown);
    let silenced = std::mem::take(&mut state.silenced);
    *state = call_machine_new();
    state.silenced = silenced;
}

/// The outcome of a reason to end, as iOS's `Reason.outcome(wasActive:)`.
fn hung_up_result(active: bool) -> CallResult {
    if active { CallResult::Completed } else { CallResult::Missed }
}

/// `end(reason:)`: hang up, cancel before an answer, or a failure; tells the other phone unless the reason is "missed".
fn end(state: &mut CallMachineState, result: CallResult, tell: bool, now_ms: i64, actions: &mut Vec<CallMachineAction>) {
    if !in_call(state) {
        return;
    }
    let (id, peer) = (state.call_id.clone(), state.peer_id.clone());
    let result = if state.unavailable.is_some() { CallResult::Unavailable } else { result };
    finish(state, result, now_ms, actions);
    if tell {
        actions.push(send("call.end", &id, &peer, None));
    }
}

fn mine(state: &CallMachineState, call_id: &str, peer_id: &str) -> bool {
    in_call(state) && state.call_id == call_id && state.peer_id == peer_id
}

/// One step of the 1:1 call machine. `now_ms` is the phone's clock in milliseconds. A step that does nothing returns the state
/// unchanged and no actions. The phase announcement (`call_phase_announcement`) is added by this function whenever the phase changes.
#[uniffi::export]
pub fn call_machine_step(state: CallMachineState, event: CallMachineEvent, now_ms: i64) -> CallMachineStep {
    let before = state.phase;
    let mut state = state;
    let mut actions: Vec<CallMachineAction> = Vec::new();
    use CallMachineEvent as E;
    match event {
        E::TapCall { call_id, peer_id, peer_name, video } => {
            if state.phase == CallPhaseKind::Idle {
                begin(&mut state, true, call_id, peer_id, peer_name, video);
                actions.push(CallMachineAction::StartOutgoing);
            }
        }
        E::OfferSent => {
            if state.phase == CallPhaseKind::Outgoing {
                actions.push(CallMachineAction::ArmTimer { kind: CallTimerKind::Ring, seconds: CALL_RING_SECONDS });
                actions.push(CallMachineAction::StartPolling);
                actions.push(CallMachineAction::StartRingback);
                actions.push(CallMachineAction::ArmTimer { kind: CallTimerKind::Hint, seconds: CALL_HINT_SECONDS });
            }
        }
        E::OfferFailed | E::RelayUnavailable => {
            if state.phase == CallPhaseKind::Outgoing {
                finish(&mut state, CallResult::Failed, now_ms, &mut actions);
            } else if state.phase == CallPhaseKind::Connecting {
                end(&mut state, CallResult::Failed, true, now_ms, &mut actions);
            }
        }
        E::OfferReceived { call_id, peer_id, peer_name, video, my_id, quiet } => {
            if state.phase != CallPhaseKind::Idle {
                if state.phase == CallPhaseKind::Outgoing && state.peer_id == peer_id && state.call_id != call_id {
                    // Crossed calls: both phones offered at once. The lower user id's offer wins; the other side drops its own, silently.
                    if my_id < peer_id {
                        return CallMachineStep { state, actions };
                    }
                    finish(&mut state, CallResult::Missed, now_ms, &mut actions);
                } else {
                    // Already on a call: the second caller hears "busy".
                    if state.call_id != call_id {
                        actions.push(send("call.busy", &call_id, &peer_id, None));
                    }
                    return CallMachineStep { state, actions };
                }
            }
            if let Some(reason) = quiet {
                let within = state.silenced.iter().find(|s| s.peer_id == peer_id).is_some_and(|s| ((now_ms - s.at_ms) as f64) / 1000.0 < CALL_BREAKTHROUGH_SECONDS);
                if within {
                    // A second call within three minutes rings anyway (an emergency gets through).
                    state.silenced.retain(|s| s.peer_id != peer_id);
                } else {
                    state.silenced.retain(|s| s.peer_id != peer_id);
                    state.silenced.push(CallSilenced { peer_id: peer_id.clone(), at_ms: now_ms });
                    actions.push(CallMachineAction::Log {
                        entry: CallLogEntry {
                            id: call_id.clone(),
                            peer_id: peer_id.clone(),
                            peer_name,
                            video,
                            outgoing: false,
                            at_ms: now_ms,
                            duration_ms: 0,
                            result: call_quiet_result(reason),
                        },
                    });
                    actions.push(send("call.unavailable", &call_id, &peer_id, Some(call_quiet_raw(reason))));
                    return CallMachineStep { state, actions };
                }
            }
            begin(&mut state, false, call_id, peer_id, peer_name, video);
            actions.push(CallMachineAction::StartPolling);
            actions.push(CallMachineAction::ArmTimer { kind: CallTimerKind::Ring, seconds: CALL_RING_SECONDS });
            actions.push(CallMachineAction::ShowIncoming);
        }
        E::RingShown => {
            if state.phase == CallPhaseKind::Incoming {
                actions.push(send("call.ringing", &state.call_id.clone(), &state.peer_id.clone(), None));
            }
        }
        E::RingRefused => {
            if state.phase == CallPhaseKind::Incoming {
                finish(&mut state, CallResult::Missed, now_ms, &mut actions);
            }
        }
        E::TapAnswer => {
            if state.phase == CallPhaseKind::Incoming {
                state.phase = CallPhaseKind::Connecting;
                actions.push(CallMachineAction::CancelTimer { kind: CallTimerKind::Ring });
                actions.push(CallMachineAction::ArmTimer { kind: CallTimerKind::Connect, seconds: CALL_CONNECT_SECONDS });
                actions.push(CallMachineAction::AcceptIncoming);
            }
        }
        E::AnswerSent => {}
        E::AnswerFailed | E::AnswerApplyFailed => {
            end(&mut state, CallResult::Failed, true, now_ms, &mut actions);
        }
        E::TapDecline => {
            if state.phase == CallPhaseKind::Incoming {
                let (id, peer) = (state.call_id.clone(), state.peer_id.clone());
                finish(&mut state, CallResult::Declined, now_ms, &mut actions);
                actions.push(send("call.decline", &id, &peer, None));
            }
        }
        E::TapHangUp => {
            if state.phase == CallPhaseKind::Incoming {
                // Hanging up a ringing call is declining it.
                let (id, peer) = (state.call_id.clone(), state.peer_id.clone());
                finish(&mut state, CallResult::Declined, now_ms, &mut actions);
                actions.push(send("call.decline", &id, &peer, None));
            } else if in_call(&state) {
                let result = hung_up_result(state.phase == CallPhaseKind::Active);
                end(&mut state, result, true, now_ms, &mut actions);
            }
        }
        E::SignalRinging { call_id, peer_id } => {
            if state.phase == CallPhaseKind::Outgoing && state.call_id == call_id && state.peer_id == peer_id {
                if !state.remote_ringing {
                    actions.push(CallMachineAction::Announce { words: "Ringing\u{2026}".to_string() });
                }
                state.remote_ringing = true;
                state.unreachable_hint = false;
            }
        }
        E::SignalAnswer { call_id, peer_id } => {
            if state.phase == CallPhaseKind::Outgoing && state.call_id == call_id && state.peer_id == peer_id {
                state.phase = CallPhaseKind::Connecting;
                actions.push(CallMachineAction::CancelTimer { kind: CallTimerKind::Ring });
                actions.push(CallMachineAction::StopRingback);
                actions.push(CallMachineAction::CancelTimer { kind: CallTimerKind::Hint });
                actions.push(CallMachineAction::ArmTimer { kind: CallTimerKind::Connect, seconds: CALL_CONNECT_SECONDS });
                actions.push(CallMachineAction::ApplyAnswer);
            }
        }
        E::SignalEnd { call_id, peer_id } => remote_end(&mut state, RemoteEnd::End, &call_id, &peer_id, now_ms, &mut actions),
        E::SignalDecline { call_id, peer_id } => remote_end(&mut state, RemoteEnd::Decline, &call_id, &peer_id, now_ms, &mut actions),
        E::SignalBusy { call_id, peer_id } => remote_end(&mut state, RemoteEnd::Busy, &call_id, &peer_id, now_ms, &mut actions),
        E::SignalUnavailable { call_id, peer_id, reason } => {
            if state.phase == CallPhaseKind::Outgoing && state.call_id == call_id && state.peer_id == peer_id && state.unavailable.is_none() {
                state.unavailable = Some(reason);
                state.unreachable_hint = false;
                actions.push(CallMachineAction::Announce { words: call_unavailable_words(state.peer_name.clone(), reason) });
                actions.push(CallMachineAction::StopRingback);
                actions.push(CallMachineAction::CancelTimer { kind: CallTimerKind::Ring });
                actions.push(CallMachineAction::CancelTimer { kind: CallTimerKind::Hint });
                actions.push(CallMachineAction::ArmTimer { kind: CallTimerKind::Unavailable, seconds: CALL_UNAVAILABLE_SECONDS });
            }
        }
        E::MediaUp => {
            if in_call(&state) && state.phase != CallPhaseKind::Active {
                state.phase = CallPhaseKind::Active;
                state.started_at_ms = Some(now_ms);
                actions.push(CallMachineAction::CancelTimer { kind: CallTimerKind::Ring });
                actions.push(CallMachineAction::CancelTimer { kind: CallTimerKind::Connect });
                actions.push(CallMachineAction::StopPolling);
                actions.push(CallMachineAction::StopRingback);
            }
        }
        E::MediaFailed => {
            if in_call(&state) {
                end(&mut state, CallResult::Failed, true, now_ms, &mut actions);
            }
        }
        E::Timer { kind } => match kind {
            CallTimerKind::Hint => {
                if state.phase == CallPhaseKind::Outgoing && !state.remote_ringing && !state.unreachable_hint {
                    state.unreachable_hint = true;
                    actions.push(CallMachineAction::Announce { words: call_unreachable_words(state.peer_name.clone()) });
                }
            }
            CallTimerKind::Ring => {
                if matches!(state.phase, CallPhaseKind::Outgoing | CallPhaseKind::Incoming) {
                    if state.outgoing {
                        end(&mut state, CallResult::NoAnswer, true, now_ms, &mut actions);
                    } else {
                        end(&mut state, CallResult::Missed, false, now_ms, &mut actions);
                    }
                }
            }
            CallTimerKind::Connect => {
                if state.phase == CallPhaseKind::Connecting {
                    end(&mut state, CallResult::Failed, true, now_ms, &mut actions);
                }
            }
            CallTimerKind::Unavailable => {
                if state.phase == CallPhaseKind::Outgoing && state.unavailable.is_some() {
                    finish(&mut state, CallResult::Unavailable, now_ms, &mut actions);
                }
            }
        },
    }
    if let Some(words) = call_phase_announcement(before, state.phase) {
        actions.insert(0, CallMachineAction::Announce { words });
    }
    CallMachineStep { state, actions }
}

#[derive(Clone, Copy)]
enum RemoteEnd {
    End,
    Decline,
    Busy,
}

/// The other phone ended the call (`call.end`, `call.decline`, `call.busy`): guards on the call id and the peer, and writes the outcome as
/// iOS does: busy → Busy; decline → Declined; end → Missed while it was ringing here, else Completed if it was active, else Missed.
fn remote_end(state: &mut CallMachineState, kind: RemoteEnd, call_id: &str, peer_id: &str, now_ms: i64, actions: &mut Vec<CallMachineAction>) {
    if !mine(state, call_id, peer_id) {
        return;
    }
    let result = match kind {
        RemoteEnd::Busy => CallResult::Busy,
        RemoteEnd::Decline => CallResult::Declined,
        RemoteEnd::End => {
            if state.phase == CallPhaseKind::Incoming { CallResult::Missed } else { hung_up_result(state.phase == CallPhaseKind::Active) }
        }
    };
    finish(state, result, now_ms, actions);
}

// ---------------------------------------------------------------------------------------------------- the minimised group call's grid

/// One person of a group call, as the grid plan needs them.
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct GridPerson {
    pub id: String,
    pub name: String,
    pub is_me: bool,
    pub speaking: bool,
    /// Their camera is on, their key has arrived and this is a video call: there is a picture to draw.
    pub has_picture: bool,
}

/// One cell of the grid: a person, or the "+N" cell.
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct GridCell {
    pub id: String,
    /// `Some(n)` for the "+N" cell.
    pub more: Option<u32>,
    pub name: String,
    pub is_me: bool,
    /// Draw their live picture (false: their photo, never black).
    pub live: bool,
    pub speaking: bool,
}

/// Which view of a minimised call: everyone in a grid, or the speaker alone.
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum GridView {
    Grid,
    Speaker,
}

/// The person's choice, else the grid up to 4 other people and the speaker above.
#[uniffi::export]
pub fn pip_grid_view(choice: Option<GridView>, others: u32) -> GridView {
    choice.unwrap_or(if others <= 4 { GridView::Grid } else { GridView::Speaker })
}

/// Who owns the window while minimised: decided from the kind of call, the person's choice and the number of people, and not from
/// whether someone happens to be in the room this second. The second value is what a log says.
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct GridMode {
    pub view: GridView,
    pub why: String,
}

#[uniffi::export]
pub fn pip_grid_mode(video: bool, choice: Option<GridView>, others: u32) -> GridMode {
    if !video {
        return GridMode { view: GridView::Speaker, why: "voice call".to_string() };
    }
    if let Some(choice) = choice {
        let word = match choice {
            GridView::Grid => "grid",
            GridView::Speaker => "speaker",
        };
        return GridMode { view: choice, why: format!("chosen: {word}") };
    }
    let view = if others <= 4 { GridView::Grid } else { GridView::Speaker };
    GridMode { view, why: format!("default for {others} other people") }
}

/// The cells in order. Counting the other people (not me): 1 fills the window; 2 sit side by side; 3 make a 2 × 2 whose fourth cell is my
/// own picture; 4 make a 2 × 2; 5 or more show the 3 people who spoke most recently and a "+N" cell. `recent` lists the other people by
/// how lately they spoke (newest first); `speaker_id` is the one person kept live when the heat guard has lightened the grid.
#[uniffi::export]
pub fn pip_grid_cells(people: Vec<GridPerson>, recent: Vec<String>, speaker_id: Option<String>, all_live: bool) -> Vec<GridCell> {
    let others: Vec<&GridPerson> = people.iter().filter(|p| !p.is_me).collect();
    if others.is_empty() {
        return Vec::new();
    }
    let mut shown: Vec<&GridPerson>;
    let mut extra = 0u32;
    match others.len() {
        1 | 2 | 4 => shown = others.clone(),
        3 => {
            shown = others.clone();
            shown.extend(people.iter().filter(|p| p.is_me));
        }
        n => {
            let mut order: Vec<&GridPerson> = recent.iter().filter_map(|id| others.iter().copied().find(|p| &p.id == id)).collect();
            order.extend(others.iter().copied().filter(|p| !recent.contains(&p.id)));
            shown = order.into_iter().take(3).collect();
            extra = (n - 3) as u32;
        }
    }
    let mut cells: Vec<GridCell> = shown
        .into_iter()
        .map(|p| GridCell {
            id: p.id.clone(),
            more: None,
            name: p.name.clone(),
            is_me: p.is_me,
            live: p.has_picture && (all_live || speaker_id.as_deref() == Some(p.id.as_str())),
            speaking: p.speaking,
        })
        .collect();
    if extra > 0 {
        cells.push(GridCell { id: "more".to_string(), more: Some(extra), name: format!("+{extra}"), is_me: false, live: false, speaking: false });
    }
    cells
}

/// How many cells draw a live picture.
#[uniffi::export]
pub fn pip_grid_live_count(cells: Vec<GridCell>) -> u32 {
    cells.iter().filter(|c| c.live).count() as u32
}

/// The heat guard: when the phone reaches the serious thermal state the grid keeps only the speaker live, and goes back to all live after
/// two minutes at fair or nominal, so it never flaps.
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct PipHeat {
    pub reduced: bool,
    pub calm_since_ms: Option<i64>,
}

/// Feeds the thermal state (`hot` = serious or critical); the second value says whether `reduced` changed.
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct PipHeatStep {
    pub heat: PipHeat,
    pub changed: bool,
}

#[uniffi::export]
pub fn pip_heat_step(heat: PipHeat, hot: bool, now_ms: i64) -> PipHeatStep {
    let before = heat.reduced;
    let mut heat = heat;
    if hot {
        heat.reduced = true;
        heat.calm_since_ms = None;
    } else if heat.reduced {
        let since = *heat.calm_since_ms.get_or_insert(now_ms);
        if ((now_ms - since) as f64) / 1000.0 >= PIP_HEAT_CALM_SECONDS {
            heat.reduced = false;
            heat.calm_since_ms = None;
        }
    } else {
        heat.calm_since_ms = None;
    }
    PipHeatStep { changed: heat.reduced != before, heat }
}

#[uniffi::export]
pub fn pip_heat_new() -> PipHeat {
    PipHeat { reduced: false, calm_since_ms: None }
}

#[cfg(test)]
mod tests {
    use super::*;
    use CallMachineAction as A;
    use CallMachineEvent as E;

    const T0: i64 = 1_800_000_000_000;

    fn step(state: &CallMachineState, event: E, now: i64) -> CallMachineStep {
        call_machine_step(state.clone(), event, now)
    }
    fn tap(video: bool) -> E {
        E::TapCall { call_id: "c1".into(), peer_id: "ben".into(), peer_name: "Ben".into(), video }
    }
    fn offer(call_id: &str, peer: &str, my_id: &str, quiet: Option<CallQuietKind>) -> E {
        E::OfferReceived { call_id: call_id.into(), peer_id: peer.into(), peer_name: peer.to_uppercase(), video: false, my_id: my_id.into(), quiet }
    }
    fn logs(step: &CallMachineStep) -> Vec<CallLogEntry> {
        step.actions.iter().filter_map(|a| if let A::Log { entry } = a { Some(entry.clone()) } else { None }).collect()
    }
    fn sends(step: &CallMachineStep) -> Vec<(String, String, Option<String>)> {
        step.actions.iter().filter_map(|a| if let A::Send { op, call_id, reason, .. } = a { Some((op.clone(), call_id.clone(), reason.clone())) } else { None }).collect()
    }
    fn has(step: &CallMachineStep, action: &A) -> bool {
        step.actions.contains(action)
    }
    fn announced(step: &CallMachineStep) -> Vec<String> {
        step.actions.iter().filter_map(|a| if let A::Announce { words } = a { Some(words.clone()) } else { None }).collect()
    }
    fn idle() -> CallMachineState {
        call_machine_new()
    }
    /// An outgoing call that has gone out and is ringing.
    fn outgoing() -> CallMachineState {
        let s = step(&idle(), tap(false), T0).state;
        step(&s, E::OfferSent, T0).state
    }
    fn incoming(video: bool) -> CallMachineState {
        let mut s = step(&idle(), offer("in1", "ben", "me", None), T0).state;
        s.video = video;
        s
    }
    fn entry(result: CallResult, video: bool, outgoing: bool, ms: i64) -> CallLogEntry {
        CallLogEntry { id: "x".into(), peer_id: "jean".into(), peer_name: "Jean".into(), video, outgoing, at_ms: 0, duration_ms: ms, result }
    }

    // ---- CallTests: the phases

    #[test]
    fn an_outgoing_call_rings_then_connects_and_logs_its_duration() {
        let s = step(&idle(), tap(false), T0);
        assert_eq!(s.state.phase, CallPhaseKind::Outgoing);
        assert!(has(&s, &A::StartOutgoing));
        assert_eq!(announced(&s), vec!["Calling\u{2026}"]);
        let sent = step(&s.state, E::OfferSent, T0 + 100);
        assert!(has(&sent, &A::StartRingback) && has(&sent, &A::StartPolling));
        assert!(has(&sent, &A::ArmTimer { kind: CallTimerKind::Ring, seconds: 45.0 }));
        assert!(has(&sent, &A::ArmTimer { kind: CallTimerKind::Hint, seconds: 10.0 }));
        let ringing = step(&sent.state, E::SignalRinging { call_id: "c1".into(), peer_id: "ben".into() }, T0 + 1000);
        assert!(ringing.state.remote_ringing);
        let answered = step(&ringing.state, E::SignalAnswer { call_id: "c1".into(), peer_id: "ben".into() }, T0 + 3000);
        assert_eq!(answered.state.phase, CallPhaseKind::Connecting);
        assert!(has(&answered, &A::ApplyAnswer) && has(&answered, &A::StopRingback));
        assert!(has(&answered, &A::ArmTimer { kind: CallTimerKind::Connect, seconds: 30.0 }));
        let up = step(&answered.state, E::MediaUp, T0 + 4000);
        assert_eq!(up.state.phase, CallPhaseKind::Active);
        assert_eq!(announced(&up), vec!["Connected"]);
        let hung = step(&up.state, E::TapHangUp, T0 + 4000 + 65_000);
        assert_eq!(hung.state.phase, CallPhaseKind::Idle);
        let log = logs(&hung);
        assert_eq!(log.len(), 1);
        assert_eq!((log[0].result, log[0].duration_ms, log[0].outgoing, log[0].at_ms), (CallResult::Completed, 65_000, true, T0 + 4000));
        assert_eq!(sends(&hung), vec![("call.end".to_string(), "c1".to_string(), None)]);
        assert!(has(&hung, &A::TearDown));
        assert_eq!(announced(&hung), vec!["Call ended"]);
    }

    #[test]
    fn an_unanswered_outgoing_call_is_no_answer_after_forty_five_seconds() {
        let s = outgoing();
        let timed = step(&s, E::Timer { kind: CallTimerKind::Ring }, T0 + 45_000);
        assert_eq!(timed.state.phase, CallPhaseKind::Idle);
        assert_eq!(logs(&timed)[0].result, CallResult::NoAnswer);
        assert_eq!(sends(&timed)[0].0, "call.end", "the other phone is told it stopped");
    }

    #[test]
    fn an_incoming_call_accepted_sends_an_answer_and_a_declined_one_says_so() {
        let ringing = step(&idle(), offer("in1", "ben", "me", None), T0);
        assert_eq!(ringing.state.phase, CallPhaseKind::Incoming);
        assert!(has(&ringing, &A::ShowIncoming) && has(&ringing, &A::ArmTimer { kind: CallTimerKind::Ring, seconds: 45.0 }));
        assert!(announced(&ringing).is_empty(), "an incoming call is announced by the system's own screen");
        let shown = step(&ringing.state, E::RingShown, T0 + 100);
        assert_eq!(sends(&shown), vec![("call.ringing".to_string(), "in1".to_string(), None)], "the callee tells the caller it is ringing");
        let accepted = step(&shown.state, E::TapAnswer, T0 + 2000);
        assert_eq!(accepted.state.phase, CallPhaseKind::Connecting);
        assert!(has(&accepted, &A::AcceptIncoming));
        let declined = step(&shown.state, E::TapDecline, T0 + 2000);
        assert_eq!(logs(&declined)[0].result, CallResult::Declined);
        assert_eq!(sends(&declined), vec![("call.decline".to_string(), "in1".to_string(), None)]);
        // Hanging up a ringing call is declining it.
        let hung = step(&shown.state, E::TapHangUp, T0 + 2000);
        assert_eq!(logs(&hung)[0].result, CallResult::Declined);
    }

    #[test]
    fn an_incoming_call_that_rings_out_is_missed_and_the_caller_is_not_told_twice() {
        let missed = step(&incoming(false), E::Timer { kind: CallTimerKind::Ring }, T0 + 45_000);
        assert_eq!(logs(&missed)[0].result, CallResult::Missed);
        assert!(sends(&missed).is_empty(), "the caller's own timer ends its side");
    }

    #[test]
    fn a_remote_end_while_ringing_is_missed_and_the_other_ends_follow_iosts_table() {
        let missed = step(&incoming(false), E::SignalEnd { call_id: "in1".into(), peer_id: "ben".into() }, T0 + 5000);
        assert_eq!(logs(&missed)[0].result, CallResult::Missed);
        let declined = step(&outgoing(), E::SignalDecline { call_id: "c1".into(), peer_id: "ben".into() }, T0 + 5000);
        assert_eq!(logs(&declined)[0].result, CallResult::Declined);
        let busy = step(&outgoing(), E::SignalBusy { call_id: "c1".into(), peer_id: "ben".into() }, T0 + 5000);
        assert_eq!(logs(&busy)[0].result, CallResult::Busy);
        // an end before the call was up is "missed" for the caller too; after it was up, completed with the length
        let early = step(&outgoing(), E::SignalEnd { call_id: "c1".into(), peer_id: "ben".into() }, T0 + 5000);
        assert_eq!(logs(&early)[0].result, CallResult::Missed);
        let up = step(&step(&outgoing(), E::SignalAnswer { call_id: "c1".into(), peer_id: "ben".into() }, T0).state, E::MediaUp, T0 + 1000).state;
        let done = step(&up, E::SignalEnd { call_id: "c1".into(), peer_id: "ben".into() }, T0 + 31_000);
        assert_eq!((logs(&done)[0].result, logs(&done)[0].duration_ms), (CallResult::Completed, 30_000));
        // a stranger's end, or another call's, does nothing
        let other = step(&outgoing(), E::SignalEnd { call_id: "zzz".into(), peer_id: "ben".into() }, T0);
        assert_eq!(other.state.phase, CallPhaseKind::Outgoing);
        assert!(other.actions.is_empty());
    }

    #[test]
    fn a_second_caller_hears_busy() {
        let busy = step(&outgoing(), offer("in9", "sam", "me", None), T0 + 100);
        assert_eq!(sends(&busy), vec![("call.busy".to_string(), "in9".to_string(), None)]);
        assert_eq!(busy.state.phase, CallPhaseKind::Outgoing, "the call that is on goes on");
        assert!(logs(&busy).is_empty());
    }

    #[test]
    fn crossed_calls_the_lower_user_ids_offer_wins() {
        // I am "ada" and they are "ben": my id is lower, so mine wins and theirs is ignored.
        let mine = step(&outgoing(), offer("theirs", "ben", "ada", None), T0 + 100);
        assert_eq!(mine.state.phase, CallPhaseKind::Outgoing);
        assert_eq!(mine.state.call_id, "c1");
        assert!(mine.actions.is_empty());
        // I am "zed": theirs wins; my own is dropped silently (logged as missed) and theirs rings as an ordinary incoming call.
        let theirs = step(&outgoing(), offer("theirs", "ben", "zed", None), T0 + 100);
        assert_eq!(theirs.state.phase, CallPhaseKind::Incoming);
        assert_eq!(theirs.state.call_id, "theirs");
        assert_eq!(logs(&theirs).len(), 1);
        assert_eq!(logs(&theirs)[0].result, CallResult::Missed);
        assert!(has(&theirs, &A::ShowIncoming));
        assert!(sends(&theirs).is_empty(), "silently: nothing is sent for my dropped call");
    }

    #[test]
    fn quiet_hours_make_a_missed_call_without_ringing_and_tell_the_caller_why() {
        let silenced = step(&idle(), offer("in1", "ben", "me", Some(CallQuietKind::Dnd)), T0);
        assert_eq!(silenced.state.phase, CallPhaseKind::Idle, "no ring");
        let log = logs(&silenced);
        assert_eq!((log[0].result, log[0].outgoing, log[0].duration_ms), (CallResult::MissedDnd, false, 0));
        assert_eq!(sends(&silenced), vec![("call.unavailable".to_string(), "in1".to_string(), Some("dnd".to_string()))]);
        let hours = step(&idle(), offer("in2", "ben", "me", Some(CallQuietKind::WorkHours)), T0);
        assert_eq!(logs(&hours)[0].result, CallResult::MissedHours);
        assert_eq!(sends(&hours)[0].2.as_deref(), Some("work_hours"));
    }

    #[test]
    fn a_second_call_within_three_minutes_rings_despite_do_not_disturb_and_one_after_is_silenced_again() {
        let first = step(&idle(), offer("in1", "ben", "me", Some(CallQuietKind::Dnd)), T0);
        let second = step(&first.state, offer("in2", "ben", "me", Some(CallQuietKind::Dnd)), T0 + 60_000);
        assert_eq!(second.state.phase, CallPhaseKind::Incoming, "an emergency gets through");
        assert!(has(&second, &A::ShowIncoming));
        // a different person is still silenced
        let other = step(&first.state, offer("in3", "sam", "me", Some(CallQuietKind::Dnd)), T0 + 60_000);
        assert_eq!(other.state.phase, CallPhaseKind::Idle);
        // after three minutes the same person is silenced again
        let late = step(&first.state, offer("in4", "ben", "me", Some(CallQuietKind::Dnd)), T0 + 181_000);
        assert_eq!(late.state.phase, CallPhaseKind::Idle);
        assert_eq!(logs(&late)[0].result, CallResult::MissedDnd);
    }

    #[test]
    fn the_caller_sees_why_for_a_moment_then_the_call_ends_as_unavailable() {
        let s = outgoing();
        let told = step(&s, E::SignalUnavailable { call_id: "c1".into(), peer_id: "ben".into(), reason: CallQuietKind::Dnd }, T0 + 500);
        assert_eq!(told.state.phase, CallPhaseKind::Outgoing);
        assert_eq!(call_status_text(told.state.clone(), T0 + 600), "Ben has Do Not Disturb on");
        assert_eq!(announced(&told), vec!["Ben has Do Not Disturb on"]);
        assert!(has(&told, &A::ArmTimer { kind: CallTimerKind::Unavailable, seconds: 2.0 }) && has(&told, &A::StopRingback));
        let closed = step(&told.state, E::Timer { kind: CallTimerKind::Unavailable }, T0 + 2500);
        assert_eq!(closed.state.phase, CallPhaseKind::Idle);
        assert_eq!(logs(&closed)[0].result, CallResult::Unavailable);
        let hours = step(&s, E::SignalUnavailable { call_id: "c1".into(), peer_id: "ben".into(), reason: CallQuietKind::WorkHours }, T0 + 500);
        assert_eq!(call_status_text(hours.state, T0), "Ben is outside work hours");
        // hanging up while the note shows is still "unavailable"
        let hung = step(&told.state, E::TapHangUp, T0 + 1000);
        assert_eq!(logs(&hung)[0].result, CallResult::Unavailable);
    }

    #[test]
    fn an_unavailable_for_another_call_is_ignored() {
        let s = outgoing();
        let ignored = step(&s, E::SignalUnavailable { call_id: "other".into(), peer_id: "ben".into(), reason: CallQuietKind::Dnd }, T0);
        assert!(ignored.actions.is_empty() && ignored.state.unavailable.is_none());
        let wrong_peer = step(&s, E::SignalUnavailable { call_id: "c1".into(), peer_id: "sam".into(), reason: CallQuietKind::Dnd }, T0);
        assert!(wrong_peer.actions.is_empty());
    }

    #[test]
    fn the_status_line_goes_calling_ringing_connecting_then_the_timer() {
        let calling = outgoing();
        assert_eq!(call_status_text(calling.clone(), T0), "Calling\u{2026}");
        let ringing = step(&calling, E::SignalRinging { call_id: "c1".into(), peer_id: "ben".into() }, T0).state;
        assert_eq!(call_status_text(ringing.clone(), T0), "Ringing\u{2026}");
        let connecting = step(&ringing, E::SignalAnswer { call_id: "c1".into(), peer_id: "ben".into() }, T0).state;
        assert_eq!(call_status_text(connecting.clone(), T0), "Connecting\u{2026}");
        let active = step(&connecting, E::MediaUp, T0 + 1000).state;
        assert_eq!(call_status_text(active.clone(), T0 + 1000), "0:00");
        assert_eq!(call_status_text(active, T0 + 1000 + 252_000), "4:12");
        assert_eq!(call_status_text(incoming(false), T0), "lime voice call");
        assert_eq!(call_status_text(incoming(true), T0), "lime video call");
        assert_eq!(call_status_text(idle(), T0), "");
    }

    #[test]
    fn the_unreachable_hint_appears_after_ten_seconds_without_ringing_and_not_with_it() {
        let s = outgoing();
        let hint = step(&s, E::Timer { kind: CallTimerKind::Hint }, T0 + 10_000);
        assert!(hint.state.unreachable_hint);
        assert_eq!(announced(&hint), vec!["Ben\u{2019}s phone may be off or lime closed"]);
        let ringing = step(&s, E::SignalRinging { call_id: "c1".into(), peer_id: "ben".into() }, T0 + 5000);
        let none = step(&ringing.state, E::Timer { kind: CallTimerKind::Hint }, T0 + 10_000);
        assert!(!none.state.unreachable_hint, "ringing: no hint");
        // ringing clears a hint that already showed
        let late = step(&hint.state, E::SignalRinging { call_id: "c1".into(), peer_id: "ben".into() }, T0 + 12_000);
        assert!(!late.state.unreachable_hint);
        // ringing is announced once
        assert_eq!(announced(&ringing), vec!["Ringing\u{2026}"]);
        assert!(announced(&step(&ringing.state, E::SignalRinging { call_id: "c1".into(), peer_id: "ben".into() }, T0 + 6000)).is_empty());
    }

    #[test]
    fn ringback_starts_with_the_offer_and_stops_on_every_outcome() {
        let sent = step(&step(&idle(), tap(false), T0).state, E::OfferSent, T0);
        assert!(has(&sent, &A::StartRingback));
        for event in [
            E::TapHangUp,
            E::Timer { kind: CallTimerKind::Ring },
            E::SignalDecline { call_id: "c1".into(), peer_id: "ben".into() },
            E::SignalBusy { call_id: "c1".into(), peer_id: "ben".into() },
            E::SignalAnswer { call_id: "c1".into(), peer_id: "ben".into() },
        ] {
            let s = step(&sent.state, event.clone(), T0 + 1000);
            assert!(has(&s, &A::StopRingback), "{event:?} stops the ringback");
        }
    }

    #[test]
    fn failures_end_the_call_as_failed_and_tell_the_other_phone_once_it_knows_of_the_call() {
        // the offer could not go out: nobody was told, so nothing is sent
        let failed = step(&step(&idle(), tap(false), T0).state, E::OfferFailed, T0);
        assert_eq!(logs(&failed)[0].result, CallResult::Failed);
        assert!(sends(&failed).is_empty());
        // the media never came up
        let connecting = step(&outgoing(), E::SignalAnswer { call_id: "c1".into(), peer_id: "ben".into() }, T0).state;
        let timed = step(&connecting, E::Timer { kind: CallTimerKind::Connect }, T0 + 30_000);
        assert_eq!(logs(&timed)[0].result, CallResult::Failed);
        assert_eq!(sends(&timed)[0].0, "call.end");
        let media = step(&connecting, E::MediaFailed, T0 + 1000);
        assert_eq!(logs(&media)[0].result, CallResult::Failed);
        let apply = step(&connecting, E::AnswerApplyFailed, T0 + 1000);
        assert_eq!(logs(&apply)[0].result, CallResult::Failed);
        // accepting failed
        let accepted = step(&incoming(false), E::TapAnswer, T0).state;
        let no_answer = step(&accepted, E::AnswerFailed, T0 + 1000);
        assert_eq!(logs(&no_answer)[0].result, CallResult::Failed);
        assert_eq!(sends(&no_answer)[0].0, "call.end");
        // the system refused to ring: a missed call, nothing sent
        let refused = step(&incoming(false), E::RingRefused, T0);
        assert_eq!(logs(&refused)[0].result, CallResult::Missed);
        assert!(sends(&refused).is_empty());
        // a timer that fires in the wrong phase does nothing
        let stale = step(&idle(), E::Timer { kind: CallTimerKind::Connect }, T0);
        assert!(stale.actions.is_empty());
        let stale_ring = step(&connecting, E::Timer { kind: CallTimerKind::Ring }, T0);
        assert!(stale_ring.actions.is_empty() && stale_ring.state.phase == CallPhaseKind::Connecting);
    }

    #[test]
    fn only_one_call_at_a_time_and_a_second_tap_does_nothing() {
        let again = step(&outgoing(), E::TapCall { call_id: "c2".into(), peer_id: "sam".into(), peer_name: "Sam".into(), video: false }, T0);
        assert!(again.actions.is_empty());
        assert_eq!(again.state.call_id, "c1");
    }

    #[test]
    fn the_silenced_list_survives_a_call() {
        let silenced = step(&idle(), offer("in1", "ben", "me", Some(CallQuietKind::Dnd)), T0).state;
        let s = step(&silenced, tap(false), T0 + 1000).state;
        let done = step(&s, E::OfferFailed, T0 + 2000).state;
        assert_eq!(done.silenced.len(), 1, "the breakthrough rule still knows who called");
    }

    #[test]
    fn the_phase_announcements_are_iosts_words() {
        use CallPhaseKind::*;
        assert_eq!(call_phase_announcement(Idle, Outgoing).as_deref(), Some("Calling\u{2026}"));
        assert_eq!(call_phase_announcement(Idle, Incoming), None);
        assert_eq!(call_phase_announcement(Incoming, Connecting).as_deref(), Some("Connecting\u{2026}"));
        assert_eq!(call_phase_announcement(Connecting, Active).as_deref(), Some("Connected"));
        assert_eq!(call_phase_announcement(Active, Idle).as_deref(), Some("Call ended"));
        assert_eq!(call_phase_announcement(Idle, Idle), None);
        assert_eq!(call_phase_announcement(Active, Active), None);
    }

    #[test]
    fn fingerprint_clock_and_the_relay_rule() {
        assert_eq!(call_fingerprint("v=0\r\na=fingerprint:sha-256 ab:cd:ef\r\nm=audio".into()).as_deref(), Some("AB:CD:EF"));
        assert_eq!(call_fingerprint("v=0\na=other:1\n  a=fingerprint:sha-256 01:02  \n".into()).as_deref(), Some("01:02"));
        assert_eq!(call_fingerprint("v=0".into()), None);
        assert_eq!(call_clock(0.0), "0:00");
        assert_eq!(call_clock(59.4), "0:59");
        assert_eq!(call_clock(61.0), "1:01");
        assert_eq!(call_clock(252.0), "4:12");
        assert_eq!(call_clock(3_725.0), "1:02:05");
        assert!(call_relay_allowed(false, false));
        assert!(call_relay_allowed(true, true));
        assert!(!call_relay_allowed(true, false), "always relay with no credentials never calls directly");
        assert!(call_relay_unavailable_words().contains("Always relay calls"));
        let timeouts = call_timeouts();
        assert_eq!((timeouts.hint_seconds, timeouts.ring_seconds, timeouts.connect_seconds, timeouts.unavailable_seconds, timeouts.breakthrough_seconds), (10.0, 45.0, 30.0, 2.0, 180.0));
    }

    // ---- CallTests: the missed filter, CallHistoryTests, CallBackActionTests

    #[test]
    fn the_missed_filter_counts_silenced_calls_and_not_unavailable() {
        assert!(call_result_is_missed(CallResult::Missed));
        assert!(call_result_is_missed(CallResult::MissedDnd));
        assert!(call_result_is_missed(CallResult::MissedHours));
        for r in [CallResult::Completed, CallResult::Declined, CallResult::NoAnswer, CallResult::Busy, CallResult::Failed, CallResult::Unavailable] {
            assert!(!call_result_is_missed(r), "{r:?}");
        }
    }

    #[test]
    fn the_stored_words_round_trip_and_an_unknown_one_is_unknown() {
        for r in [CallResult::Completed, CallResult::Missed, CallResult::Declined, CallResult::NoAnswer, CallResult::Busy, CallResult::Failed, CallResult::MissedDnd, CallResult::MissedHours, CallResult::Unavailable] {
            assert_eq!(call_result_parse(call_result_raw(r)), Some(r));
        }
        assert_eq!(call_result_raw(CallResult::NoAnswer), "noAnswer");
        assert_eq!(call_result_raw(CallResult::MissedDnd), "missed_dnd");
        assert_eq!(call_result_parse("nonsense".into()), None);
        assert_eq!(call_quiet_parse(call_quiet_raw(CallQuietKind::WorkHours)), Some(CallQuietKind::WorkHours));
        assert_eq!(call_quiet_parse("x".into()), None);
    }

    #[test]
    fn a_calls_line_and_its_words_in_the_details() {
        assert_eq!(call_log_line(entry(CallResult::Completed, false, true, 252_000)), "Voice call \u{00B7} 4:12");
        assert_eq!(call_log_line(entry(CallResult::Completed, true, false, 31_000)), "Video call \u{00B7} 0:31");
        assert_eq!(call_log_line(entry(CallResult::Missed, false, false, 0)), "Missed call");
        assert_eq!(call_log_line(entry(CallResult::Missed, true, false, 0)), "Missed video call");
        assert_eq!(call_log_line(entry(CallResult::Missed, false, true, 0)), "No answer");
        assert_eq!(call_log_line(entry(CallResult::Declined, false, false, 0)), "Declined call");
        assert_eq!(call_log_line(entry(CallResult::Declined, true, true, 0)), "Video call declined");
        assert_eq!(call_log_line(entry(CallResult::NoAnswer, false, true, 0)), "No answer");
        assert_eq!(call_log_line(entry(CallResult::Busy, false, true, 0)), "Jean was busy");
        assert_eq!(call_log_line(entry(CallResult::Failed, true, true, 0)), "Video call failed");
        assert_eq!(call_log_line(entry(CallResult::MissedDnd, false, false, 0)), "Missed call");
        assert_eq!(call_log_line(entry(CallResult::Unavailable, false, true, 0)), "Unavailable");
        assert_eq!(call_log_outcome_text(entry(CallResult::Completed, false, true, 61_000)), "1:01");
        assert_eq!(call_log_outcome_text(entry(CallResult::Missed, false, false, 0)), "Missed");
        assert_eq!(call_log_outcome_text(entry(CallResult::Missed, false, true, 0)), "No answer");
        assert_eq!(call_log_outcome_text(entry(CallResult::MissedDnd, false, false, 0)), "Silenced \u{00B7} Do Not Disturb");
        assert_eq!(call_log_outcome_text(entry(CallResult::MissedHours, false, true, 0)), "No answer");
        assert_eq!(call_log_row_note(CallResult::MissedHours).as_deref(), Some("Silenced \u{00B7} Work hours"));
        assert_eq!(call_log_row_note(CallResult::Unavailable).as_deref(), Some("Unavailable"));
        assert_eq!(call_log_row_note(CallResult::Missed), None);
    }

    fn at(day: i64, hour: i64, minute: i64) -> i64 {
        // October 2026, UTC: day 1 is 2026-10-01T00:00Z = 1_790_812_800 s.
        (1_790_812_800 + (day - 1) * 86_400 + hour * 3600 + minute * 60) * 1000
    }
    fn call(id: &str, when: i64, result: CallResult, peer: &str, video: bool, outgoing: bool) -> CallLogEntry {
        CallLogEntry { id: id.into(), peer_id: peer.into(), peer_name: peer.into(), video, outgoing, at_ms: when, duration_ms: 60_000, result }
    }

    #[test]
    fn consecutive_calls_of_the_same_person_kind_day_and_missed_class_form_one_row() {
        let groups = call_log_groups(
            vec![
                call("a", at(10, 15, 0), CallResult::Missed, "jean", false, false),
                call("b", at(10, 14, 0), CallResult::Missed, "jean", false, false),
                call("c", at(10, 13, 0), CallResult::Missed, "jean", false, false), // 3 missed, same day
                call("d", at(10, 12, 0), CallResult::Completed, "jean", false, false), // answered: a new row
                call("e", at(10, 11, 0), CallResult::Missed, "jean", false, false), // missed again after an answered one
                call("f", at(9, 20, 0), CallResult::Missed, "jean", false, false), // another day
                call("g", at(9, 19, 0), CallResult::Missed, "sam", false, false), // another person
                call("h", at(9, 18, 0), CallResult::Missed, "sam", true, false), // another kind
            ],
            0,
        );
        assert_eq!(groups.iter().map(|g| g.entries.len()).collect::<Vec<_>>(), vec![3, 1, 1, 1, 1, 1]);
        assert_eq!(groups[0].id, "a");
        assert!(groups[0].is_missed_incoming);
        assert!(!groups[1].is_missed_incoming);
        // the input order does not matter: newest first
        let shuffled = call_log_groups(vec![call("b", at(10, 14, 0), CallResult::Missed, "jean", false, false), call("a", at(10, 15, 0), CallResult::Missed, "jean", false, false)], 0);
        assert_eq!(shuffled.len(), 1);
        assert_eq!(shuffled[0].id, "a");
        // an outgoing "missed" is not a missed incoming call, so it does not merge with one
        let mixed = call_log_groups(vec![call("o", at(10, 15, 0), CallResult::Missed, "jean", false, true), call("i", at(10, 14, 0), CallResult::Missed, "jean", false, false)], 0);
        assert_eq!(mixed.len(), 2);
        // the person's own day: 23:30 and 00:30 UTC are the same day at UTC+1
        let tz = call_log_groups(vec![call("n", at(10, 23, 30), CallResult::Missed, "jean", false, false), call("m", at(10, 22, 30), CallResult::Missed, "jean", false, false)], 3600);
        assert_eq!(tz.len(), 2, "UTC+1: 00:30 on the 11th and 23:30 on the 10th are two days");
    }

    #[test]
    fn the_time_labels_are_time_yesterday_weekday_then_date() {
        let now = at(10, 16, 30);
        assert_eq!(call_time_label_kind(at(10, 16, 12), now, 0), CallTimeLabel::Time);
        assert_eq!(call_time_label_kind(at(9, 23, 0), now, 0), CallTimeLabel::Yesterday);
        assert_eq!(call_time_label_kind(at(7, 9, 0), now, 0), CallTimeLabel::Weekday, "3 days ago: a weekday");
        assert_eq!(call_time_label_kind(at(3, 9, 0), now, 0), CallTimeLabel::Weekday, "7 days ago is still a weekday");
        assert_eq!(call_time_label_kind(at(1, 9, 0), now, 0), CallTimeLabel::Date, "older than 7 days: a short date");
        assert_eq!(call_short_date_kind(at(10, 11, 1), now, 0, true), CallShortDate::Time);
        assert_eq!(call_short_date_kind(at(9, 11, 1), now, 0, true), CallShortDate::YesterdayTime);
        assert_eq!(call_short_date_kind(at(1, 11, 1), now, 0, true), CallShortDate::DateTime { with_year: false });
        assert_eq!(call_short_date_kind(at(1, 11, 1), now, 0, false), CallShortDate::DateTime { with_year: true });
    }

    #[test]
    fn what_tapping_a_call_does() {
        assert_eq!(call_back_choice(false, None), CallBackChoice::CallPerson);
        assert_eq!(call_back_choice(false, Some("abc".into())), CallBackChoice::CallPerson);
        assert_eq!(call_back_choice(true, Some("abc".into())), CallBackChoice::JoinGroup { call_id: "abc".into() });
        assert_eq!(call_back_choice(true, None), CallBackChoice::StartGroup);
        assert!(call_peer_is_group("grp:abc".into()) && !call_peer_is_group("dm:abc".into()));
    }

    // ---- CallBubbleTests

    #[test]
    fn titles_details_and_the_one_line_summary_for_every_outcome() {
        let done = call_bubble_words(true, 23_000, CallResult::Completed, true);
        assert_eq!((done.title.as_str(), done.detail.as_str(), done.summary.as_str()), ("Video call", "0:23", "Video call \u{00B7} 0:23"));
        let missed = call_bubble_words(false, 0, CallResult::Missed, false);
        assert!(missed.is_missed_incoming);
        assert_eq!((missed.title.as_str(), missed.summary.as_str()), ("Missed voice call", "Missed voice call"));
        // an outgoing call I ended before an answer is "Cancelled"; nobody picking up is "No answer"
        let cancelled = call_bubble_words(false, 0, CallResult::Missed, true);
        assert_eq!(cancelled.detail, "Cancelled");
        assert!(!cancelled.is_missed_incoming);
        assert_eq!(call_bubble_words(false, 0, CallResult::NoAnswer, true).summary, "Voice call \u{00B7} No answer");
        assert_eq!(call_bubble_words(false, 0, CallResult::Declined, true).detail, "Declined");
        assert_eq!(call_bubble_words(false, 0, CallResult::Busy, true).detail, "Busy");
        assert_eq!(call_bubble_words(false, 252_000, CallResult::Completed, false).summary, "Voice call \u{00B7} 4:12");
    }

    #[test]
    fn the_cores_body_becomes_the_bubble() {
        let body = r#"{"video":true,"duration_ms":23000,"outcome":"completed","outgoing":true}"#;
        assert_eq!(call_bubble_from_body(body.into(), true).map(|b| b.summary), Some("Video call \u{00B7} 23".replace("23", "0:23")));
        assert_eq!(call_bubble_from_body("not json".into(), true), None);
        assert_eq!(call_bubble_from_body(r#"{"video":true}"#.into(), true), None, "an unknown outcome is not a call");
        assert_eq!(call_bubble_from_body(r#"{"outcome":"nonsense"}"#.into(), true), None);
        // a group call: live, then ended
        let live = call_bubble_from_body(r#"{"group":true,"outcome":"live","video":false,"started_by":"u1"}"#.into(), false).expect("a group call");
        assert!(live.is_group && live.live);
        assert_eq!(live.summary, "Group call \u{00B7} Join");
        assert_eq!(call_bubble_title(live.clone(), false, Some("Jean".into())), "Jean started a call");
        assert_eq!(call_bubble_title(live.clone(), true, Some("Jean".into())), "Call started", "never You");
        assert_eq!(call_bubble_title(live.clone(), false, None), "Someone started a call");
        assert_eq!(call_bubble_chat_detail(live), "Join");
        let ended = call_bubble_from_body(r#"{"group":true,"outcome":"completed","duration_ms":200000}"#.into(), false).expect("ended");
        assert_eq!(call_bubble_title(ended.clone(), false, None), "Call ended");
        assert_eq!(ended.summary, "Call ended \u{00B7} 3:20");
    }

    #[test]
    fn silenced_and_unavailable_calls_say_why() {
        let dnd = call_bubble_words(false, 0, CallResult::MissedDnd, false);
        assert_eq!((dnd.title.as_str(), dnd.detail.as_str()), ("Missed voice call", "Silenced \u{00B7} Do Not Disturb"));
        assert!(dnd.is_missed_incoming);
        assert_eq!(call_bubble_words(true, 0, CallResult::MissedHours, false).detail, "Silenced \u{00B7} Work hours");
        let mine = call_bubble_words(false, 0, CallResult::Unavailable, true);
        assert_eq!(mine.detail, "Unavailable");
        assert!(!mine.is_missed_incoming);
        assert_eq!(mine.summary, "Voice call \u{00B7} Unavailable");
    }

    #[test]
    fn the_live_card_says_who_is_there() {
        let n = |v: &[&str]| v.iter().map(|s| s.to_string()).collect::<Vec<_>>();
        assert_eq!(call_live_card_who(n(&[]), 0, false), "Nobody is there yet");
        assert_eq!(call_live_card_who(n(&[]), 1, false), "1 person is there");
        assert_eq!(call_live_card_who(n(&[]), 4, false), "4 people are there");
        assert_eq!(call_live_card_who(n(&[]), 1, true), "Waiting for others");
        assert_eq!(call_live_card_who(n(&["Jean Chung"]), 1, false), "Jean is there");
        assert_eq!(call_live_card_who(n(&["Jean Chung"]), 3, false), "Jean is there and 2 others");
        assert_eq!(call_live_card_who(n(&["Jean Chung"]), 2, false), "Jean is there and 1 other");
        assert_eq!(call_live_card_who(n(&["Jean Chung", "Lee Wong"]), 2, false), "Jean and Lee are there");
        assert_eq!(call_live_card_who(n(&["Jean", "Lee", "Sam", "Ana"]), 4, false), "Jean, Lee and 2 others are there");
        assert_eq!(call_live_card_who(n(&["Jean", "Lee", "Sam"]), 3, false), "Jean, Lee and 1 other are there");
    }

    // ---- group call rules and PiPGridPlanTests

    #[test]
    fn a_group_call_rings_by_the_cores_word_and_is_silenced_by_do_not_disturb() {
        assert!(group_call_should_ring(5, None));
        assert!(!group_call_should_ring(5, Some(CallQuietKind::Dnd)));
        assert!(!group_call_should_ring(5, Some(CallQuietKind::WorkHours)));
        assert!(!group_call_should_ring(11, None), "a big group gets a chat line, not a ring");
        assert!(!group_call_starts_in_speaker_view(12));
        assert!(group_call_starts_in_speaker_view(13));
        assert_eq!(group_call_title("Grade 4".into(), true, vec!["Jean Chung".into()]), "Grade 4");
        assert_eq!(group_call_title("Grade 4".into(), false, vec!["Jean Chung".into(), "Shem Lee".into()]), "Jean, Shem");
        assert_eq!(group_call_title("Grade 4".into(), false, vec![]), "Grade 4");
    }

    fn people(others: usize, speaking: &[&str], pictures: bool) -> Vec<GridPerson> {
        let mut v = vec![GridPerson { id: "me".into(), name: "Me".into(), is_me: true, speaking: false, has_picture: pictures }];
        for i in 0..others {
            v.push(GridPerson { id: format!("p{i}"), name: format!("P{i}"), is_me: false, speaking: speaking.contains(&format!("p{i}").as_str()), has_picture: pictures });
        }
        v
    }
    fn ids(cells: &[GridCell]) -> Vec<String> {
        cells.iter().map(|c| c.id.clone()).collect()
    }

    #[test]
    fn one_two_three_four_and_more_others() {
        let cells = |n: usize, recent: &[&str]| pip_grid_cells(people(n, &[], true), recent.iter().map(|s| s.to_string()).collect(), None, true);
        assert!(cells(0, &[]).is_empty(), "nobody else: the group's own picture");
        assert_eq!(ids(&cells(1, &[])), vec!["p0"]);
        assert_eq!(ids(&cells(2, &[])), vec!["p0", "p1"]);
        assert_eq!(ids(&cells(3, &[])), vec!["p0", "p1", "p2", "me"], "three others: my own picture is the fourth cell");
        assert_eq!(ids(&cells(4, &[])), vec!["p0", "p1", "p2", "p3"]);
        let six = cells(6, &["p4", "p1", "p5"]);
        assert_eq!(ids(&six), vec!["p4", "p1", "p5", "more"], "the three who spoke most recently and a +N cell");
        assert_eq!(six.last().and_then(|c| c.more), Some(3));
        assert_eq!(six.last().map(|c| c.name.as_str()), Some("+3"));
        assert_eq!(ids(&cells(7, &[]))[..3], ["p0", "p1", "p2"], "nobody has spoken: the first three");
    }

    #[test]
    fn the_speaker_is_marked_and_a_person_without_a_picture_is_never_live() {
        let cells = pip_grid_cells(people(2, &["p1"], true), vec![], Some("p1".into()), true);
        assert_eq!(cells.iter().map(|c| c.speaking).collect::<Vec<_>>(), vec![false, true]);
        assert_eq!(cells.iter().map(|c| c.live).collect::<Vec<_>>(), vec![true, true]);
        let off = pip_grid_cells(people(2, &[], false), vec![], Some("p1".into()), true);
        assert_eq!(off.iter().map(|c| c.live).collect::<Vec<_>>(), vec![false, false], "camera off or no key: the photo");
    }

    #[test]
    fn the_heat_guard_lightens_the_grid_to_the_speaker_only() {
        let hot = pip_grid_cells(people(3, &[], true), vec![], Some("p2".into()), false);
        assert_eq!(hot.iter().map(|c| c.live).collect::<Vec<_>>(), vec![false, false, true, false]);
        assert_eq!(pip_grid_live_count(hot), 1);
    }

    #[test]
    fn heat_goes_on_at_serious_and_off_after_two_calm_minutes_without_flapping() {
        let t0 = 1_000_000;
        let s = pip_heat_new();
        let fair = pip_heat_step(s, false, t0);
        assert!(!fair.changed && !fair.heat.reduced);
        let hot = pip_heat_step(fair.heat, true, t0);
        assert!(hot.changed && hot.heat.reduced);
        let still = pip_heat_step(hot.heat, false, t0 + 10_000);
        assert!(!still.changed && still.heat.reduced, "fair is not yet calm enough");
        let again = pip_heat_step(still.heat, true, t0 + 100_000);
        let calm = pip_heat_step(again.heat, false, t0 + 110_000);
        let almost = pip_heat_step(calm.heat, false, t0 + 110_000 + 119_000);
        assert!(almost.heat.reduced);
        let back = pip_heat_step(almost.heat, false, t0 + 110_000 + 120_000);
        assert!(back.changed && !back.heat.reduced, "back after 2 calm minutes");
        let critical = pip_heat_step(back.heat, true, t0 + 300_000);
        assert!(critical.changed && critical.heat.reduced);
    }

    #[test]
    fn the_mode_comes_from_the_call_and_the_choice_not_from_who_is_in_the_room() {
        assert_eq!(pip_grid_view(None, 4), GridView::Grid);
        assert_eq!(pip_grid_view(None, 5), GridView::Speaker);
        assert_eq!(pip_grid_view(Some(GridView::Speaker), 2), GridView::Speaker);
        assert_eq!(pip_grid_mode(false, Some(GridView::Grid), 2), GridMode { view: GridView::Speaker, why: "voice call".into() });
        assert_eq!(pip_grid_mode(true, Some(GridView::Speaker), 2), GridMode { view: GridView::Speaker, why: "chosen: speaker".into() });
        assert_eq!(pip_grid_mode(true, None, 3), GridMode { view: GridView::Grid, why: "default for 3 other people".into() });
        assert_eq!(pip_grid_mode(true, None, 9), GridMode { view: GridView::Speaker, why: "default for 9 other people".into() });
    }
}
