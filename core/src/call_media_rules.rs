//! The rules of a call's media that are not the media (LIME-426): what video a phone sends, the in-call control channel's messages and the checks on a mid-call
//! description, and where the sound goes. Ported from iOS (`CallSettings.swift` `CallVideoPlan`, `CallManager.swift` `handleControl` / `receivedRenegotiation*`,
//! `CallRoute.swift`) and tested with the iOS cases (`CallTests`, `CallVideoPlanTests`). The camera, WebRTC and the audio manager stay in the platform.

use crate::call_rules::call_fingerprint;

// ---------------------------------------------------------------------------------------------------- what video is sent

/// The camera size and rate a call asks for.
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct CallCapture {
    pub width: u32,
    pub height: u32,
    pub fps: u32,
}

/// The most video data Low Data Mode lets one call send (bits per second).
pub const CALL_LOW_DATA_MAX_BITRATE: u32 = 350_000;

/// Normal: 720p (30 fps in a group, up to 24 in a one-to-one call: WebRTC adapts down). On mobile data in a group: 480p at 24. Low Data Mode: 360p at 15, whatever else.
#[uniffi::export]
pub fn call_video_capture(low_data: bool, cellular: bool, group: bool) -> CallCapture {
    if low_data {
        return CallCapture { width: 640, height: 360, fps: 15 };
    }
    if group {
        return if cellular { CallCapture { width: 848, height: 480, fps: 24 } } else { CallCapture { width: 1280, height: 720, fps: 30 } };
    }
    CallCapture { width: 1280, height: 720, fps: 24 }
}

/// The bitrate cap in Low Data Mode, none otherwise.
#[uniffi::export]
pub fn call_video_max_bitrate(low_data: bool) -> Option<u32> {
    low_data.then_some(CALL_LOW_DATA_MAX_BITRATE)
}

/// The frame-rate cap in Low Data Mode, none otherwise.
#[uniffi::export]
pub fn call_video_max_fps(low_data: bool) -> Option<u32> {
    low_data.then_some(15)
}

// ---------------------------------------------------------------------------------------------------- the control channel

/// A control message may be this many bytes; a bigger one is ignored unread.
pub const CALL_CONTROL_LIMIT: usize = 64 * 1024;

/// What the other phone said over the `lime-ctl` channel. `Ignored` is anything unknown (a newer lime), malformed or oversized.
#[derive(Debug, Clone, PartialEq, uniffi::Enum)]
pub enum CallControlMessage {
    State { muted: Option<bool>, camera: Option<bool> },
    Offer { sdp: String },
    Answer { sdp: String },
    Ignored,
}

#[uniffi::export]
pub fn parse_call_control(text: String) -> CallControlMessage {
    if text.len() > CALL_CONTROL_LIMIT {
        return CallControlMessage::Ignored;
    }
    let Ok(value) = serde_json::from_str::<serde_json::Value>(&text) else { return CallControlMessage::Ignored };
    let Some(kind) = value.get("t").and_then(serde_json::Value::as_str) else { return CallControlMessage::Ignored };
    let sdp = || value.get("sdp").and_then(serde_json::Value::as_str).map(str::to_string);
    match kind {
        "state" => CallControlMessage::State {
            muted: value.get("muted").and_then(serde_json::Value::as_bool),
            camera: value.get("camera").and_then(serde_json::Value::as_bool),
        },
        "offer" => sdp().map_or(CallControlMessage::Ignored, |sdp| CallControlMessage::Offer { sdp }),
        "answer" => sdp().map_or(CallControlMessage::Ignored, |sdp| CallControlMessage::Answer { sdp }),
        _ => CallControlMessage::Ignored,
    }
}

/// My state as the channel carries it: `{"t":"state","muted":false,"camera":true}`.
#[uniffi::export]
pub fn call_control_state(muted: bool, camera: bool) -> String {
    serde_json::json!({ "t": "state", "muted": muted, "camera": camera }).to_string()
}

/// A mid-call description: `{"t":"offer","sdp":"…"}` or `{"t":"answer","sdp":"…"}`; `None` when it would not fit the limit.
#[uniffi::export]
pub fn call_control_description(is_offer: bool, sdp: String) -> Option<String> {
    let text = serde_json::json!({ "t": if is_offer { "offer" } else { "answer" }, "sdp": sdp }).to_string();
    (text.len() <= CALL_CONTROL_LIMIT).then_some(text)
}

/// What to do with a description that arrives mid-call.
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum RenegotiationVerdict {
    /// Take it (an offer is answered, an answer is applied).
    Accept,
    /// Its media key is not the one both phones signed: the call ends failed.
    KeyChanged,
    /// Both phones offered at once and the other side's offer is the one that stands: drop mine-losing duplicates (this one is ignored).
    Glare,
    /// Not in a state to take it (not active, no offer of mine waiting for this answer).
    Ignore,
}

fn same_key(sdp: &str, remote_fingerprint: &Option<String>) -> bool {
    match (call_fingerprint(sdp.to_string()), remote_fingerprint) {
        (Some(a), Some(b)) => a == *b,
        _ => false,
    }
}

/// The other phone's offer (turning the call into video, or its camera going on).
#[uniffi::export]
pub fn call_renegotiation_offer(active: bool, sdp: String, remote_fingerprint: Option<String>, renegotiating: bool, my_id: String, peer_id: String) -> RenegotiationVerdict {
    if !active {
        return RenegotiationVerdict::Ignore;
    }
    if !same_key(&sdp, &remote_fingerprint) {
        return RenegotiationVerdict::KeyChanged;
    }
    // Both sides adding video at once: the lower user id's offer stands, the other side's is dropped.
    if renegotiating && my_id < peer_id {
        return RenegotiationVerdict::Glare;
    }
    RenegotiationVerdict::Accept
}

/// The other phone's answer to my mid-call offer.
#[uniffi::export]
pub fn call_renegotiation_answer(active: bool, renegotiating: bool, sdp: String, remote_fingerprint: Option<String>) -> RenegotiationVerdict {
    if !active || !renegotiating {
        return RenegotiationVerdict::Ignore;
    }
    if !same_key(&sdp, &remote_fingerprint) {
        return RenegotiationVerdict::KeyChanged;
    }
    RenegotiationVerdict::Accept
}

/// Whether the screen draws the other person's picture: a video call, their camera on and their video arriving. Otherwise their avatar, never a frozen or black frame.
#[uniffi::export]
pub fn call_remote_video_showing(video: bool, remote_camera_on: bool, receiving: bool) -> bool {
    video && remote_camera_on && receiving
}

/// Whether the camera is sending: a video call, a camera added, the person has it on, and nothing holds it (another app has the camera, or lime is in the background).
#[uniffi::export]
pub fn call_camera_sending(video: bool, has_camera: bool, camera_on: bool, held: bool) -> bool {
    video && has_camera && camera_on && !held
}

// ---------------------------------------------------------------------------------------------------- where the sound goes

#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum CallRouteKind {
    Earpiece,
    Speaker,
    Wired,
    Bluetooth,
}

/// The word for a route, as the call screen and the toast say it ("Audio now on Speaker"). A Bluetooth device is named by what it is, never by its own name.
#[uniffi::export]
pub fn call_route_name(kind: CallRouteKind) -> String {
    match kind {
        CallRouteKind::Earpiece => "Phone",
        CallRouteKind::Speaker => "Speaker",
        CallRouteKind::Wired => "Headphones",
        CallRouteKind::Bluetooth => "Bluetooth",
    }
    .to_string()
}

/// The toast and the spoken line when the route changes during a call.
#[uniffi::export]
pub fn call_route_toast(kind: CallRouteKind) -> String {
    format!("Audio now on {}", call_route_name(kind))
}

/// Which route a call uses: the speaker when the person chose it (or a video call starts there); otherwise a Bluetooth headset, then wired headphones, then the earpiece.
/// A route that is not there (a headset taken off) falls through to the next.
#[uniffi::export]
pub fn call_route_choice(available: Vec<CallRouteKind>, speaker_wanted: bool) -> CallRouteKind {
    let has = |k: CallRouteKind| available.contains(&k);
    if speaker_wanted {
        CallRouteKind::Speaker
    } else if has(CallRouteKind::Bluetooth) {
        CallRouteKind::Bluetooth
    } else if has(CallRouteKind::Wired) {
        CallRouteKind::Wired
    } else if has(CallRouteKind::Earpiece) {
        CallRouteKind::Earpiece
    } else {
        CallRouteKind::Speaker
    }
}

/// A video call starts on the speaker, a voice call at the ear; turning a voice call into video moves it to the speaker.
#[uniffi::export]
pub fn call_speaker_by_default(video: bool) -> bool {
    video
}

/// The proximity sensor blanks the screen only for a voice call held at the ear (never in video, on the speaker or on a headset).
#[uniffi::export]
pub fn call_proximity_on(video: bool, route: CallRouteKind) -> bool {
    !video && route == CallRouteKind::Earpiece
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sdp(fp: &str) -> String {
        format!("v=0\r\na=fingerprint:sha-256 {fp}\r\n")
    }

    #[test]
    fn the_video_plan_is_the_one_ios_uses() {
        assert_eq!(call_video_capture(false, false, false), CallCapture { width: 1280, height: 720, fps: 24 });
        assert_eq!(call_video_capture(false, false, true), CallCapture { width: 1280, height: 720, fps: 30 });
        assert_eq!(call_video_capture(false, true, true), CallCapture { width: 848, height: 480, fps: 24 });
        assert_eq!(call_video_capture(true, true, true), CallCapture { width: 640, height: 360, fps: 15 });
        assert_eq!(call_video_max_bitrate(true), Some(350_000));
        assert_eq!(call_video_max_bitrate(false), None);
        assert_eq!(call_video_max_fps(true), Some(15));
        assert_eq!(call_video_max_fps(false), None);
    }

    #[test]
    fn control_messages_parse() {
        assert_eq!(parse_call_control(call_control_state(true, false)), CallControlMessage::State { muted: Some(true), camera: Some(false) });
        assert_eq!(parse_call_control("{\"t\":\"state\",\"muted\":false}".into()), CallControlMessage::State { muted: Some(false), camera: None });
        let offer = call_control_description(true, sdp("AA")).unwrap();
        assert_eq!(parse_call_control(offer), CallControlMessage::Offer { sdp: sdp("AA") });
        let answer = call_control_description(false, sdp("BB")).unwrap();
        assert_eq!(parse_call_control(answer), CallControlMessage::Answer { sdp: sdp("BB") });
    }

    #[test]
    fn unknown_oversized_and_malformed_control_messages_are_ignored() {
        assert_eq!(parse_call_control("{\"t\":\"wave\",\"x\":1}".into()), CallControlMessage::Ignored);
        assert_eq!(parse_call_control("not json".into()), CallControlMessage::Ignored);
        assert_eq!(parse_call_control("{\"muted\":true}".into()), CallControlMessage::Ignored);
        assert_eq!(parse_call_control("{\"t\":\"offer\"}".into()), CallControlMessage::Ignored);
        let big = format!("{{\"t\":\"state\",\"muted\":true,\"pad\":\"{}\"}}", "x".repeat(70_000));
        assert_eq!(parse_call_control(big), CallControlMessage::Ignored);
        assert_eq!(call_control_description(true, "x".repeat(70_000)), None);
    }

    #[test]
    fn a_mid_call_offer_with_the_same_key_is_taken() {
        assert_eq!(call_renegotiation_offer(true, sdp("cc:dd"), Some("CC:DD".into()), false, "a".into(), "b".into()), RenegotiationVerdict::Accept);
    }

    #[test]
    fn a_mid_call_description_with_another_key_ends_the_call() {
        assert_eq!(call_renegotiation_offer(true, sdp("EE:FF"), Some("CC:DD".into()), false, "a".into(), "b".into()), RenegotiationVerdict::KeyChanged);
        assert_eq!(call_renegotiation_answer(true, true, sdp("99:99"), Some("CC:DD".into())), RenegotiationVerdict::KeyChanged);
        // No key stored, or none in the description: refused, never waved through.
        assert_eq!(call_renegotiation_offer(true, sdp("CC:DD"), None, false, "a".into(), "b".into()), RenegotiationVerdict::KeyChanged);
        assert_eq!(call_renegotiation_offer(true, "v=0\r\n".into(), Some("CC:DD".into()), false, "a".into(), "b".into()), RenegotiationVerdict::KeyChanged);
    }

    #[test]
    fn both_adding_video_at_once_the_lower_id_wins() {
        // I offered and am waiting; theirs arrives. I am `a` (lower): my offer stands, theirs is dropped.
        assert_eq!(call_renegotiation_offer(true, sdp("CC:DD"), Some("CC:DD".into()), true, "a".into(), "b".into()), RenegotiationVerdict::Glare);
        // I am `b`: theirs stands, I answer it.
        assert_eq!(call_renegotiation_offer(true, sdp("CC:DD"), Some("CC:DD".into()), true, "b".into(), "a".into()), RenegotiationVerdict::Accept);
    }

    #[test]
    fn nothing_is_taken_outside_an_active_call_or_without_my_offer() {
        assert_eq!(call_renegotiation_offer(false, sdp("CC:DD"), Some("CC:DD".into()), false, "a".into(), "b".into()), RenegotiationVerdict::Ignore);
        assert_eq!(call_renegotiation_answer(true, false, sdp("CC:DD"), Some("CC:DD".into())), RenegotiationVerdict::Ignore);
        assert_eq!(call_renegotiation_answer(false, true, sdp("CC:DD"), Some("CC:DD".into())), RenegotiationVerdict::Ignore);
        assert_eq!(call_renegotiation_answer(true, true, sdp("CC:DD"), Some("CC:DD".into())), RenegotiationVerdict::Accept);
    }

    #[test]
    fn the_picture_shows_only_when_there_is_one() {
        assert!(call_remote_video_showing(true, true, true));
        assert!(!call_remote_video_showing(true, false, true), "their camera is off: their avatar, not a frozen or black picture");
        assert!(!call_remote_video_showing(true, true, false));
        assert!(!call_remote_video_showing(false, true, true));
        assert!(call_camera_sending(true, true, true, false));
        assert!(!call_camera_sending(true, true, true, true), "held by another app or the background");
        assert!(!call_camera_sending(false, true, true, false));
        assert!(!call_camera_sending(true, false, true, false));
    }

    #[test]
    fn the_route_is_chosen_from_what_is_there() {
        use CallRouteKind::*;
        assert_eq!(call_route_choice(vec![Earpiece, Speaker], false), Earpiece);
        assert_eq!(call_route_choice(vec![Earpiece, Speaker], true), Speaker);
        assert_eq!(call_route_choice(vec![Earpiece, Speaker, Bluetooth], false), Bluetooth);
        assert_eq!(call_route_choice(vec![Earpiece, Speaker, Wired], false), Wired);
        assert_eq!(call_route_choice(vec![Earpiece, Speaker, Wired, Bluetooth], false), Bluetooth);
        assert_eq!(call_route_choice(vec![Speaker, Bluetooth], true), Speaker, "the person's Speaker wins over a headset");
        assert_eq!(call_route_choice(vec![Speaker], false), Speaker, "a tablet has no earpiece");
        assert_eq!(call_route_choice(vec![], false), Speaker);
    }

    #[test]
    fn routes_have_words_and_a_toast() {
        assert_eq!(call_route_name(CallRouteKind::Speaker), "Speaker");
        assert_eq!(call_route_toast(CallRouteKind::Bluetooth), "Audio now on Bluetooth");
        assert_eq!(call_route_toast(CallRouteKind::Earpiece), "Audio now on Phone");
    }

    #[test]
    fn video_starts_on_the_speaker_and_the_sensor_only_blanks_a_voice_call_at_the_ear() {
        assert!(call_speaker_by_default(true));
        assert!(!call_speaker_by_default(false));
        assert!(call_proximity_on(false, CallRouteKind::Earpiece));
        assert!(!call_proximity_on(true, CallRouteKind::Earpiece));
        assert!(!call_proximity_on(false, CallRouteKind::Speaker));
        assert!(!call_proximity_on(false, CallRouteKind::Bluetooth));
    }
}
