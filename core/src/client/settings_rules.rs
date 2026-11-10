//! Settings rules that lived only in Swift (LIME-306): the app lock's delay rule, the media download and keep rules, and the words of a notification or banner for
//! the person's preview choice. Mirrors `AppLock.shouldLock` / `hidesNotificationText` (`ios/Lime/Core/Security/AppLock.swift`), `AutoDownload` / `KeepMedia` /
//! `StorageGuard.mayAutoDownload` (`ios/Lime/Core/Storage/MediaPolicy.swift`) and `NotificationPolicy.content` / `shortened`
//! (`ios/Lime/Core/Notifications/NotificationPolicy.swift`). Pure functions; where a choice is *kept* is the app's (iOS: UserDefaults; Android: private
//! preferences). iOS keeps its Swift until LIME-133b.

// ---------------------------------------------------------------- app lock

/// How long lime may be away before it asks again.
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum LockDelay {
    Immediately,
    OneMinute,
    FifteenMinutes,
    OneHour,
}

/// Every delay, in the order Settings lists them.
#[uniffi::export]
pub fn lock_delays() -> Vec<LockDelay> {
    vec![LockDelay::Immediately, LockDelay::OneMinute, LockDelay::FifteenMinutes, LockDelay::OneHour]
}

/// The seconds a delay stands for (what is stored).
#[uniffi::export]
pub fn lock_delay_seconds(delay: LockDelay) -> u32 {
    match delay {
        LockDelay::Immediately => 0,
        LockDelay::OneMinute => 60,
        LockDelay::FifteenMinutes => 900,
        LockDelay::OneHour => 3600,
    }
}

/// A stored number of seconds back to a delay (anything unknown is Immediately, the safe one).
#[uniffi::export]
pub fn lock_delay_from_seconds(seconds: u32) -> LockDelay {
    lock_delays().into_iter().find(|d| lock_delay_seconds(*d) == seconds).unwrap_or(LockDelay::Immediately)
}

/// The words of a delay.
#[uniffi::export]
pub fn lock_delay_title(delay: LockDelay) -> String {
    match delay {
        LockDelay::Immediately => "Immediately",
        LockDelay::OneMinute => "After 1 minute",
        LockDelay::FifteenMinutes => "After 15 minutes",
        LockDelay::OneHour => "After 1 hour",
    }
    .to_owned()
}

/// Whether being away for `elapsed_ms` calls for the lock.
#[uniffi::export]
pub fn should_lock(elapsed_ms: i64, delay: LockDelay) -> bool {
    elapsed_ms >= i64::from(lock_delay_seconds(delay)) * 1000
}

/// Notifications show no message text while the lock is on and the app is locked, or away long enough to be locked. `left_at_ms`: when the app left the front.
#[uniffi::export]
pub fn hides_notification_text(enabled: bool, locked: bool, left_at_ms: Option<i64>, now_ms: i64, delay: LockDelay) -> bool {
    if !enabled {
        return false;
    }
    if locked {
        return true;
    }
    match left_at_ms {
        Some(left) => should_lock(now_ms - left, delay),
        None => false,
    }
}

// ---------------------------------------------------------------- media

/// Automatic download choices.
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum AutoDownload {
    WifiAndMobile,
    WifiOnly,
    Never,
}

/// Every choice, in the order Settings lists them.
#[uniffi::export]
pub fn auto_downloads() -> Vec<AutoDownload> {
    vec![AutoDownload::WifiAndMobile, AutoDownload::WifiOnly, AutoDownload::Never]
}

#[uniffi::export]
pub fn auto_download_title(choice: AutoDownload) -> String {
    match choice {
        AutoDownload::WifiAndMobile => "Wi-Fi and mobile data",
        AutoDownload::WifiOnly => "Wi-Fi only",
        AutoDownload::Never => "Never",
    }
    .to_owned()
}

/// How long to keep received media on this phone.
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum KeepMedia {
    Forever,
    Year,
    Month,
}

#[uniffi::export]
pub fn keep_media_choices() -> Vec<KeepMedia> {
    vec![KeepMedia::Forever, KeepMedia::Year, KeepMedia::Month]
}

#[uniffi::export]
pub fn keep_media_title(choice: KeepMedia) -> String {
    match choice {
        KeepMedia::Forever => "Forever",
        KeepMedia::Year => "1 year",
        KeepMedia::Month => "30 days",
    }
    .to_owned()
}

/// Files of messages older than this many days are removed; `None` keeps everything.
#[uniffi::export]
pub fn keep_media_days(choice: KeepMedia) -> Option<u32> {
    match choice {
        KeepMedia::Forever => None,
        KeepMedia::Year => Some(365),
        KeepMedia::Month => Some(30),
    }
}

/// What kind of file a download is about.
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum MediaKind {
    Audio,
    Image,
    Video,
    File,
}

/// May lime fetch this by itself? Voice always (within the low-storage rule); pictures and the rest by the person's settings.
#[uniffi::export]
pub fn may_auto_download(kind: MediaKind, photos: AutoDownload, video_and_files: AutoDownload, on_wifi: bool, storage_low: bool) -> bool {
    if storage_low {
        return false;
    }
    let setting = match kind {
        MediaKind::Audio => return true,
        MediaKind::Image => photos,
        MediaKind::Video | MediaKind::File => video_and_files,
    };
    match setting {
        AutoDownload::WifiAndMobile => true,
        AutoDownload::WifiOnly => on_wifi,
        AutoDownload::Never => false,
    }
}

// ---------------------------------------------------------------- notification words

/// What a notification or banner shows.
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum NotificationPreview {
    NameAndMessage,
    NameOnly,
    Hidden,
}

#[uniffi::export]
pub fn notification_previews() -> Vec<NotificationPreview> {
    vec![NotificationPreview::NameAndMessage, NotificationPreview::NameOnly, NotificationPreview::Hidden]
}

#[uniffi::export]
pub fn notification_preview_title(preview: NotificationPreview) -> String {
    match preview {
        NotificationPreview::NameAndMessage => "Name and message",
        NotificationPreview::NameOnly => "Name only",
        NotificationPreview::Hidden => "No preview",
    }
    .to_owned()
}

/// A message that just arrived from someone else, ready to be announced.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct IncomingWords {
    pub conversation_title: String,
    pub sender_name: String,
    /// The words without Markdown.
    pub text: String,
    /// A reply in a thread.
    pub is_reply: bool,
    pub is_group: bool,
    /// A stranger's first message: nothing of it is shown.
    pub is_request: bool,
}

/// The title and body of a banner or notification.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct NotificationWords {
    pub title: String,
    pub body: String,
}

/// The words for the person's preview choice. A request never shows its words, whatever the choice. `hide_text` (the lock hides it) counts as No preview.
#[uniffi::export]
pub fn notification_words(message: IncomingWords, preview: NotificationPreview, hide_text: bool) -> NotificationWords {
    let preview = if hide_text { NotificationPreview::Hidden } else { preview };
    if message.is_request {
        return NotificationWords { title: message.sender_name, body: "Wants to message you".to_owned() };
    }
    let new_thing = if message.is_reply { "New reply" } else { "New message" };
    match preview {
        NotificationPreview::Hidden => NotificationWords { title: "lime".to_owned(), body: new_thing.to_owned() },
        NotificationPreview::NameOnly => NotificationWords { title: message.conversation_title, body: new_thing.to_owned() },
        NotificationPreview::NameAndMessage => {
            let who = if message.is_group { format!("{}: ", message.sender_name) } else { String::new() };
            let body = format!("{}{}{}", if message.is_reply { "Replied in a thread: " } else { "" }, who, shortened(message.text, 140));
            NotificationWords { title: message.conversation_title, body }
        }
    }
}

/// One short line: whitespace folded, cut at about `limit` characters.
#[uniffi::export]
pub fn shortened(text: String, limit: u32) -> String {
    let folded = text.split_whitespace().collect::<Vec<_>>().join(" ");
    let limit = limit as usize;
    if folded.chars().count() <= limit {
        return folded;
    }
    let cut: String = folded.chars().take(limit).collect();
    format!("{}…", cut.trim_end())
}

#[cfg(test)]
mod tests {
    use super::*;

    // ios/LimeTests/AppLock269Tests.swift: testTheDelayDecidesWhetherComingBackLocks.
    #[test]
    fn the_delay_decides_whether_coming_back_locks() {
        assert!(should_lock(0, LockDelay::Immediately));
        assert!(!should_lock(59_000, LockDelay::OneMinute));
        assert!(should_lock(60_000, LockDelay::OneMinute));
        assert!(!should_lock(899_000, LockDelay::FifteenMinutes));
        assert!(should_lock(3_600_000, LockDelay::OneHour));
    }

    // testNotificationsShowNoTextWhileLocked.
    #[test]
    fn notifications_show_no_text_while_locked() {
        let now = 10_000_000;
        assert!(!hides_notification_text(false, true, Some(0), now, LockDelay::Immediately), "off by default: nothing is hidden");
        assert!(hides_notification_text(true, true, None, now, LockDelay::OneHour), "locked");
        assert!(!hides_notification_text(true, false, None, now, LockDelay::OneHour), "unlocked and in front: the text shows");
        assert!(!hides_notification_text(true, false, Some(now), now + 60_000, LockDelay::OneHour), "inside the delay it is not locked yet");
        assert!(hides_notification_text(true, false, Some(now), now + 3_601_000, LockDelay::OneHour), "past the delay it is");
    }

    #[test]
    fn delays_are_stored_as_seconds_and_unknown_ones_are_the_safe_one() {
        for d in lock_delays() {
            assert_eq!(lock_delay_from_seconds(lock_delay_seconds(d)), d);
        }
        assert_eq!(lock_delay_from_seconds(7), LockDelay::Immediately);
        assert_eq!(lock_delays().into_iter().map(lock_delay_title).collect::<Vec<_>>(), ["Immediately", "After 1 minute", "After 15 minutes", "After 1 hour"]);
    }

    #[test]
    fn keep_media_and_the_download_choices_and_their_words() {
        assert_eq!(keep_media_days(KeepMedia::Forever), None);
        assert_eq!(keep_media_days(KeepMedia::Year), Some(365));
        assert_eq!(keep_media_days(KeepMedia::Month), Some(30));
        assert_eq!(keep_media_choices().into_iter().map(keep_media_title).collect::<Vec<_>>(), ["Forever", "1 year", "30 days"]);
        assert_eq!(auto_downloads().into_iter().map(auto_download_title).collect::<Vec<_>>(), ["Wi-Fi and mobile data", "Wi-Fi only", "Never"]);
    }

    // StorageGuard.mayAutoDownload: voice always, pictures and the rest by the settings, nothing when storage is low.
    #[test]
    fn voice_always_downloads_and_the_rest_follow_the_settings_and_the_network() {
        use AutoDownload::*;
        use MediaKind::*;
        assert!(may_auto_download(Audio, Never, Never, false, false), "voice always");
        assert!(!may_auto_download(Audio, WifiAndMobile, WifiAndMobile, true, true), "unless storage is low");
        assert!(may_auto_download(Image, WifiAndMobile, Never, false, false));
        assert!(!may_auto_download(Image, WifiOnly, WifiAndMobile, false, false), "photos: Wi-Fi only, on mobile data");
        assert!(may_auto_download(Image, WifiOnly, Never, true, false));
        assert!(!may_auto_download(Video, WifiAndMobile, Never, true, false));
        assert!(may_auto_download(File, Never, WifiOnly, true, false));
        assert!(!may_auto_download(File, Never, WifiOnly, false, false));
    }

    fn incoming(text: &str, group: bool, reply: bool, request: bool) -> IncomingWords {
        IncomingWords { conversation_title: if group { "Staff".into() } else { "Lee Wong".into() }, sender_name: "Lee Wong".into(), text: text.into(), is_reply: reply, is_group: group, is_request: request }
    }

    // ios/LimeTests/NotificationTests.swift: testPreviewChoicesAndGroupingByChat.
    #[test]
    fn preview_choices() {
        let m = || incoming("Can we plan the lesson?", false, false, false);
        assert_eq!(notification_words(m(), NotificationPreview::NameAndMessage, false), NotificationWords { title: "Lee Wong".into(), body: "Can we plan the lesson?".into() });
        assert_eq!(notification_words(m(), NotificationPreview::NameOnly, false), NotificationWords { title: "Lee Wong".into(), body: "New message".into() });
        let hidden = notification_words(m(), NotificationPreview::Hidden, false);
        assert_eq!(hidden, NotificationWords { title: "lime".into(), body: "New message".into() });
        assert!(!(hidden.title + &hidden.body).contains("Lee"), "no name, no words");
        // The lock hides the words whatever the choice.
        assert_eq!(notification_words(m(), NotificationPreview::NameAndMessage, true).body, "New message");
    }

    // testGroupsNameTheSenderRepliesSayTheyAreAndTheTapKnowsTheThread.
    #[test]
    fn groups_name_the_sender_and_replies_say_they_are() {
        let group = notification_words(incoming("Can we plan the lesson?", true, false, false), NotificationPreview::NameAndMessage, false);
        assert_eq!((group.title.as_str(), group.body.as_str()), ("Staff", "Lee Wong: Can we plan the lesson?"));
        let reply = notification_words(incoming("Can we plan the lesson?", false, true, false), NotificationPreview::NameAndMessage, false);
        assert_eq!(reply.body, "Replied in a thread: Can we plan the lesson?");
        assert_eq!(notification_words(incoming("x", false, true, false), NotificationPreview::NameOnly, false).body, "New reply");
    }

    // testARequestNeverShowsItsWordsWhateverThePreview.
    #[test]
    fn a_request_never_shows_its_words_whatever_the_preview() {
        for preview in notification_previews() {
            let content = notification_words(incoming("secret words", false, false, true), preview, false);
            assert!(!content.body.contains("secret"), "{preview:?}");
            assert_eq!(content.body, "Wants to message you");
        }
    }

    // testLongMessagesAreCutToOneLine.
    #[test]
    fn long_messages_are_cut_to_one_line() {
        let long = "word ".repeat(80);
        let body = notification_words(incoming(&long, false, false, false), NotificationPreview::NameAndMessage, false).body;
        assert!(body.chars().count() <= 141);
        assert!(body.ends_with('…'));
        assert_eq!(shortened("a\n\nb   c".into(), 140), "a b c");
    }
}
