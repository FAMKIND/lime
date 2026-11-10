//! Attachment rules that lived only in Swift (LIME-308): the voice message's waveform and clock words, the playback speeds and position, and the file limits
//! and their words. Mirrors `VoiceRecorder.bars`, `VoiceFormat`, `VoicePlayer.speeds` (`ios/Lime/Features/Attachments/VoiceMessages.swift`) and
//! `AttachmentProcessing` limits (`AttachmentModels.swift`, `ChatComposer.swift`). Pure functions. iOS keeps its Swift until LIME-133b.

// ---------------------------------------------------------------- limits

/// What a message may carry and how long a voice message may be.
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct AttachmentLimits {
    /// The most bytes of one file (the core rejects more).
    pub max_file_bytes: u64,
    /// The most files in one message.
    pub max_per_message: u32,
    /// A voice message is cut at this many seconds (it keeps the file small).
    pub max_voice_seconds: f64,
    /// Shorter than this is a tap, not a voice message.
    pub min_voice_seconds: f64,
}

#[uniffi::export]
pub fn attachment_limits() -> AttachmentLimits {
    AttachmentLimits { max_file_bytes: 50 * 1024 * 1024, max_per_message: 10, max_voice_seconds: 15.0 * 60.0, min_voice_seconds: 0.6 }
}

/// What checking a file against the limits says.
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum FileCheck {
    Ok,
    /// Nothing in it.
    Empty,
    TooLarge,
}

#[uniffi::export]
pub fn check_file_size(bytes: u64) -> FileCheck {
    if bytes == 0 {
        FileCheck::Empty
    } else if bytes > attachment_limits().max_file_bytes {
        FileCheck::TooLarge
    } else {
        FileCheck::Ok
    }
}

/// The title and message of the alert for a file that is too large.
#[uniffi::export]
pub fn file_too_large_words() -> Vec<String> {
    vec!["That file is too large".to_owned(), "Files can be up to 50 MB.".to_owned()]
}

// ---------------------------------------------------------------- voice

/// 64 (or `count`) bars from the loudness samples (0 to 1): the loudest in each stretch, scaled to 0...255, at least 8 so silence still shows a small bar.
#[uniffi::export]
pub fn voice_waveform_bars(samples: Vec<f32>, count: u32) -> Vec<u8> {
    let count = count.max(1) as usize;
    if samples.is_empty() {
        return vec![8; count];
    }
    (0..count)
        .map(|index| {
            let start = index * samples.len() / count;
            let end = (start + 1).max((index + 1) * samples.len() / count);
            let loudest = samples[start..end.min(samples.len())].iter().copied().fold(0.0_f32, f32::max);
            (loudest * 255.0).clamp(8.0, 255.0) as u8
        })
        .collect()
}

fn whole_seconds(seconds: f64) -> i64 {
    seconds.round() as i64
}

/// "0:07", "1:23" (and "1:02:03" for the very long).
#[uniffi::export]
pub fn voice_clock(seconds: f64) -> String {
    let total = whole_seconds(seconds).max(0);
    let (h, m, s) = (total / 3600, (total % 3600) / 60, total % 60);
    if h > 0 { format!("{h}:{m:02}:{s:02}") } else { format!("{m}:{s:02}") }
}

/// "7 seconds", "1 minute 23 seconds": what a screen reader says for a time.
#[uniffi::export]
pub fn voice_spoken(seconds: f64) -> String {
    let total = whole_seconds(seconds).max(0);
    let (h, m, s) = (total / 3600, (total % 3600) / 60, total % 60);
    let plural = |n: i64, one: &str, many: &str| format!("{n} {}", if n == 1 { one } else { many });
    let mut parts = Vec::new();
    if h > 0 {
        parts.push(plural(h, "hour", "hours"));
    }
    if m > 0 {
        parts.push(plural(m, "minute", "minutes"));
    }
    if s > 0 || parts.is_empty() {
        parts.push(plural(s, "second", "seconds"));
    }
    parts.join(" ")
}

/// "0:12 of 0:40": where a voice message is, for a screen reader's value.
#[uniffi::export]
pub fn voice_position(progress: f64, total: f64) -> String {
    format!("{} of {}", voice_clock(progress.clamp(0.0, 1.0) * total), voice_clock(total))
}

/// The progress (0 to 1) after moving by `seconds`, kept inside the message.
#[uniffi::export]
pub fn voice_moved(progress: f64, total: f64, by_seconds: f64) -> f64 {
    if total <= 0.0 {
        return 0.0;
    }
    (progress + by_seconds / total).clamp(0.0, 1.0)
}

/// The playback speeds: 1x, 1.5x, 2x.
#[uniffi::export]
pub fn voice_speeds() -> Vec<f32> {
    vec![1.0, 1.5, 2.0]
}

/// The speed after this one (1 to 1.5 to 2 and round again).
#[uniffi::export]
pub fn voice_next_speed(current: f32) -> f32 {
    let speeds = voice_speeds();
    let at = speeds.iter().position(|s| (*s - current).abs() < 1e-6).unwrap_or(0);
    speeds[(at + 1) % speeds.len()]
}

#[cfg(test)]
mod tests {
    use super::*;

    // ios/LimeTests/VoiceVideoTests.swift: testTheWaveformIs64BarsFromTheLoudestSampleOfEachStretch.
    #[test]
    fn the_waveform_is_64_bars_from_the_loudest_sample_of_each_stretch() {
        assert_eq!(voice_waveform_bars(vec![], 64).len(), 64);
        let mut quiet_then_loud = vec![0.1_f32; 100];
        quiet_then_loud.extend(vec![0.9_f32; 100]);
        let bars = voice_waveform_bars(quiet_then_loud, 64);
        assert_eq!(bars.len(), 64);
        assert!(bars[10] < 60);
        assert!(bars[60] > 200);
        assert!(*bars.iter().min().unwrap() >= 8, "silence still shows a small bar");
        assert_eq!(*voice_waveform_bars(vec![2.0], 64).iter().max().unwrap(), 255, "never above the top");
    }

    // testTheClockReadsLikeAVoiceMessage.
    #[test]
    fn the_clock_reads_like_a_voice_message() {
        assert_eq!(voice_clock(0.0), "0:00");
        assert_eq!(voice_clock(7.4), "0:07");
        assert_eq!(voice_clock(83.0), "1:23");
        assert_eq!(voice_clock(3723.0), "1:02:03");
    }

    #[test]
    fn spoken_times_and_the_position() {
        assert_eq!(voice_spoken(7.0), "7 seconds");
        assert_eq!(voice_spoken(1.0), "1 second");
        assert_eq!(voice_spoken(83.0), "1 minute 23 seconds");
        assert_eq!(voice_spoken(3723.0), "1 hour 2 minutes 3 seconds");
        assert_eq!(voice_spoken(0.0), "0 seconds");
        assert_eq!(voice_position(0.3, 40.0), "0:12 of 0:40");
        assert_eq!(voice_position(2.0, 40.0), "0:40 of 0:40", "progress is kept inside the message");
    }

    #[test]
    fn moving_stays_inside_the_message_and_the_speed_goes_round() {
        assert!((voice_moved(0.5, 40.0, 10.0) - 0.75).abs() < 1e-9);
        assert_eq!(voice_moved(0.1, 40.0, -10.0), 0.0);
        assert_eq!(voice_moved(0.9, 40.0, 10.0), 1.0);
        assert_eq!(voice_moved(0.5, 0.0, 10.0), 0.0);
        assert_eq!(voice_next_speed(1.0), 1.5);
        assert_eq!(voice_next_speed(1.5), 2.0);
        assert_eq!(voice_next_speed(2.0), 1.0);
    }

    // AttachmentTests.swift: a file over 50 MB is too large; ChatComposer.swift's words.
    #[test]
    fn files_are_checked_against_the_limits() {
        let l = attachment_limits();
        assert_eq!((l.max_file_bytes, l.max_per_message), (50 * 1024 * 1024, 10));
        assert_eq!(l.max_voice_seconds, 900.0);
        assert_eq!(check_file_size(0), FileCheck::Empty);
        assert_eq!(check_file_size(1), FileCheck::Ok);
        assert_eq!(check_file_size(l.max_file_bytes), FileCheck::Ok);
        assert_eq!(check_file_size(l.max_file_bytes + 1), FileCheck::TooLarge);
        assert_eq!(file_too_large_words(), ["That file is too large", "Files can be up to 50 MB."]);
    }
}
