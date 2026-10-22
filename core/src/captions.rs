//! Captions for a jam post's videos and recordings (LIME-188o): a small WebVTT subset. They are made on the writer's phone and travel inside the
//! post's encrypted blob as one `text/vtt` attachment per media, named `captions-<n>.vtt` for the post's n-th attachment (counting from 0). The
//! server sees an attachment of that size like any other.

/// The most a captions file may hold, so one cannot make a post large or slow to read.
pub const MAX_CAPTION_BYTES: usize = 256 * 1024;
/// And the most cues, whatever the bytes.
const MAX_CUES: usize = 6000;

#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct CaptionCue {
    pub start_ms: u64,
    pub end_ms: u64,
    pub text: String,
}

/// `hh:mm:ss.mmm` or `mm:ss.mmm` to milliseconds.
fn parse_time(s: &str) -> Option<u64> {
    let s = s.trim();
    let (clock, millis) = s.split_once('.').or_else(|| s.split_once(','))?;
    let ms: u64 = format!("{:0<3}", &millis.chars().take(3).collect::<String>()).parse().ok()?;
    let parts: Vec<&str> = clock.split(':').collect();
    let nums: Option<Vec<u64>> = parts.iter().map(|p| p.parse().ok()).collect();
    let nums = nums?;
    let seconds = match nums.as_slice() {
        [m, s] if *s < 60 => m * 60 + s,
        [h, m, s] if *m < 60 && *s < 60 => h * 3600 + m * 60 + s,
        _ => return None,
    };
    Some(seconds * 1000 + ms)
}

fn strip_tags(line: &str) -> String {
    let mut out = String::new();
    let mut inside = false;
    for c in line.chars() {
        match c {
            '<' => inside = true,
            '>' if inside => inside = false,
            _ if !inside => out.push(c),
            _ => {}
        }
    }
    out
}

/// Text to cues, in time order. Never fails: what is not a cue is skipped; a file over the cap has none.
pub fn parse_vtt(text: &str) -> Vec<CaptionCue> {
    if text.len() > MAX_CAPTION_BYTES {
        return Vec::new();
    }
    let text = text.replace("\r\n", "\n").replace('\r', "\n");
    let mut cues = Vec::new();
    for block in text.split("\n\n") {
        let lines: Vec<&str> = block.lines().collect();
        let Some(at) = lines.iter().position(|l| l.contains("-->")) else { continue };
        let Some((from, to)) = lines[at].split_once("-->") else { continue };
        // The end may be followed by cue settings ("align:start"): the first word is the time.
        let to = to.trim().split_whitespace().next().unwrap_or("");
        let (Some(start_ms), Some(end_ms)) = (parse_time(from), parse_time(to)) else { continue };
        let words: Vec<String> = lines[at + 1..].iter().map(|l| strip_tags(l).trim().to_owned()).filter(|l| !l.is_empty()).collect();
        if end_ms > start_ms && !words.is_empty() {
            cues.push(CaptionCue { start_ms, end_ms, text: words.join("\n") });
        }
        if cues.len() >= MAX_CUES {
            break;
        }
    }
    cues.sort_by_key(|c| c.start_ms);
    cues
}

fn clock(ms: u64) -> String {
    format!("{:02}:{:02}:{:02}.{:03}", ms / 3_600_000, ms / 60_000 % 60, ms / 1000 % 60, ms % 1000)
}

/// Cues to the file that is sent (and that the writer's editor reads back).
pub fn write_vtt(cues: &[CaptionCue]) -> String {
    let mut out = String::from("WEBVTT\n");
    for cue in cues.iter().filter(|c| c.end_ms > c.start_ms && !c.text.trim().is_empty()) {
        let text: String = cue.text.lines().map(str::trim).filter(|l| !l.is_empty()).map(|l| l.replace("-->", "\u{2192}").replace('<', "\u{2039}").replace('>', "\u{203A}")).collect::<Vec<_>>().join("\n");
        out.push_str(&format!("\n{} --> {}\n{}\n", clock(cue.start_ms), clock(cue.end_ms), text));
    }
    if out.len() > MAX_CAPTION_BYTES {
        out.truncate(MAX_CAPTION_BYTES);
    }
    out
}

/// The cue showing at this time, if any.
pub fn cue_at(cues: &[CaptionCue], ms: u64) -> Option<&CaptionCue> {
    cues.iter().find(|c| c.start_ms <= ms && ms < c.end_ms)
}

/// Which attachment a captions file is for: `captions-3.vtt` is for the post's 4th attachment.
pub fn caption_target(name: &str) -> Option<u32> {
    let n = name.strip_prefix("captions-")?.strip_suffix(".vtt")?;
    (n.len() <= 2 && !n.is_empty() && n.bytes().all(|b| b.is_ascii_digit())).then(|| n.parse().ok()).flatten()
}

/// The file name for the captions of the n-th attachment.
pub fn caption_name(index: u32) -> String {
    format!("captions-{index}.vtt")
}

#[uniffi::export]
pub fn parse_captions(vtt: String) -> Vec<CaptionCue> {
    parse_vtt(&vtt)
}

#[uniffi::export]
pub fn captions_to_vtt(cues: Vec<CaptionCue>) -> String {
    write_vtt(&cues)
}

#[uniffi::export]
pub fn caption_media_index(name: String) -> Option<u32> {
    caption_target(&name)
}

#[uniffi::export]
pub fn caption_file_name(index: u32) -> String {
    caption_name(index)
}

#[uniffi::export]
pub fn max_caption_bytes() -> u64 {
    MAX_CAPTION_BYTES as u64
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_file_round_trips_and_a_cue_is_found_by_time() {
        let cues = vec![
            CaptionCue { start_ms: 0, end_ms: 1500, text: "Hello everyone".into() },
            CaptionCue { start_ms: 1500, end_ms: 4200, text: "Today: fractions\nwith a pizza".into() },
        ];
        let file = write_vtt(&cues);
        assert!(file.starts_with("WEBVTT"));
        assert_eq!(parse_vtt(&file), cues);
        assert_eq!(cue_at(&cues, 1499).unwrap().text, "Hello everyone");
        assert_eq!(cue_at(&cues, 1500).unwrap().text, "Today: fractions\nwith a pizza");
        assert!(cue_at(&cues, 4200).is_none());
    }

    #[test]
    fn other_vtt_shapes_are_read_and_junk_is_skipped() {
        let text = "WEBVTT\r\n\r\nNOTE a comment\r\n\r\nintro\r\n00:01.000 --> 00:02.500 align:start\r\n<v Sam>Hi <b>there</b>\r\n\r\nnot a cue\r\n\r\n00:00:03,000 --> 00:00:02,000\r\nbackwards\r\n";
        let cues = parse_vtt(text);
        assert_eq!(cues, vec![CaptionCue { start_ms: 1000, end_ms: 2500, text: "Hi there".into() }]);
    }

    #[test]
    fn a_file_over_the_cap_has_no_cues_and_names_point_at_attachments() {
        let big = format!("WEBVTT\n\n00:00.000 --> 00:01.000\n{}\n", "x".repeat(MAX_CAPTION_BYTES));
        assert!(parse_vtt(&big).is_empty());
        assert_eq!(caption_target("captions-3.vtt"), Some(3));
        assert_eq!(caption_target("captions-.vtt"), None);
        assert_eq!(caption_target("captions-123.vtt"), None);
        assert_eq!(caption_target("notes.vtt"), None);
        assert_eq!(caption_name(7), "captions-7.vtt");
    }
}
