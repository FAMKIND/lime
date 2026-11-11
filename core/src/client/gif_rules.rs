//! GIFs and stickers (LIME-313): what a GIF file must be to be sent (the bytes read here, so no platform decoder is needed to refuse a big or broken one), its size and
//! frame count, and lime's own sticker pack: which stickers a typed word finds and what a screen reader says for one. Mirrors `ios/Lime/Features/Attachments/GIFSupport.swift`
//! (`GIF.maxBytes`, `maxFrames`, `isGIF`, `frameCount`), `StickerPack.swift` (`matching`, `spokenName`). The pictures are decoded and drawn by the platform. iOS keeps its Swift
//! until LIME-133b. One difference, recorded: the finding words fold upper case but not accents (iOS also folds diacritics; the pack's words are plain letters).

/// The most a GIF may weigh to be sent (10 MiB) and the most frames it may have.
pub const GIF_MAX_BYTES: usize = 10 * 1024 * 1024;
pub const GIF_MAX_FRAMES: u32 = 500;
/// The name every lime sticker is sent under, so My GIFs does not keep a copy of it.
pub const STICKER_NAME_PREFIX: &str = "lime-sticker-";

#[uniffi::export]
pub fn gif_too_big_words() -> String {
    "This GIF is too big to send".to_owned()
}

#[uniffi::export]
pub fn sticker_name_prefix() -> String {
    STICKER_NAME_PREFIX.to_owned()
}

/// What the bytes of a GIF say about it.
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Record)]
pub struct GifFileInfo {
    pub frames: u32,
    pub width: u32,
    pub height: u32,
}

fn skip_sub_blocks(bytes: &[u8], mut at: usize) -> Option<usize> {
    loop {
        let size = *bytes.get(at)? as usize;
        at += 1;
        if size == 0 {
            return Some(at);
        }
        at = at.checked_add(size)?;
        if at > bytes.len() {
            return None;
        }
    }
}

/// Reads the GIF's header and counts its pictures. None when the bytes are not a GIF (a name ending in .gif proves nothing) or end before the first picture.
#[uniffi::export]
pub fn gif_inspect(bytes: Vec<u8>) -> Option<GifFileInfo> {
    if bytes.len() < 13 || !(bytes.starts_with(b"GIF87a") || bytes.starts_with(b"GIF89a")) {
        return None;
    }
    let width = u16::from_le_bytes([bytes[6], bytes[7]]) as u32;
    let height = u16::from_le_bytes([bytes[8], bytes[9]]) as u32;
    let flags = bytes[10];
    let mut at = 13usize;
    if flags & 0x80 != 0 {
        at += 3 * (1usize << ((flags & 0x07) + 1));
    }
    let mut frames = 0u32;
    loop {
        match bytes.get(at) {
            Some(0x3B) | None => break,
            Some(0x21) => at = skip_sub_blocks(&bytes, at + 2).unwrap_or(bytes.len()),
            Some(0x2C) => {
                let Some(descriptor) = bytes.get(at + 1..at + 10) else { break };
                let local = descriptor[8];
                at += 10;
                if local & 0x80 != 0 {
                    at += 3 * (1usize << ((local & 0x07) + 1));
                }
                at += 1; // the LZW code size
                match skip_sub_blocks(&bytes, at) {
                    Some(next) => {
                        frames += 1;
                        at = next;
                    }
                    None => break,
                }
            }
            Some(_) => break,
        }
    }
    (frames > 0 && width > 0 && height > 0).then_some(GifFileInfo { frames, width, height })
}

/// None when the GIF may be sent; otherwise the words to show: "This GIF is too big to send" for one over 10 MiB or 500 frames, or "That isn't a GIF" for something else.
#[uniffi::export]
pub fn gif_problem(bytes: Vec<u8>) -> Option<String> {
    let too_big = bytes.len() > GIF_MAX_BYTES;
    match gif_inspect(bytes) {
        None => Some("That isn\u{2019}t a GIF".to_owned()),
        Some(info) if too_big || info.frames > GIF_MAX_FRAMES => Some(gif_too_big_words()),
        Some(_) => None,
    }
}

/// One of lime's own stickers (an animated GIF drawn by lime, shipped inside the app).
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct StickerEntry {
    /// "thank-you" (no extension).
    pub file: String,
    /// "Thank you!"
    pub words: String,
    /// Other words that find it.
    pub find: Vec<String>,
}

fn tokens(text: &str) -> Vec<String> {
    text.to_lowercase().split(|c: char| !c.is_alphanumeric()).filter(|t| !t.is_empty()).map(str::to_owned).collect()
}

/// The stickers whose words (or other finding words) start with every word typed; all of them for nothing typed; none when the pack is hidden.
#[uniffi::export]
pub fn sticker_matching(query: String, pack: Vec<StickerEntry>, shown: bool) -> Vec<StickerEntry> {
    if !shown {
        return Vec::new();
    }
    let typed = tokens(&query);
    if typed.is_empty() {
        return pack;
    }
    pack.into_iter()
        .filter(|sticker| {
            let have: Vec<String> = tokens(&sticker.words).into_iter().chain(sticker.find.iter().flat_map(|f| tokens(f))).collect();
            typed.iter().all(|word| have.iter().any(|h| h.starts_with(word.as_str())))
        })
        .collect()
}

/// What a screen reader says for a sticker: "lime sticker: Thank you!".
#[uniffi::export]
pub fn sticker_label(words: String) -> String {
    format!("lime sticker: {words}")
}

/// What a screen reader says for a received GIF from its file name: the sticker's label when it is one of lime's, else "Sticker".
#[uniffi::export]
pub fn sticker_spoken_name(file_name: String, pack: Vec<StickerEntry>) -> String {
    let Some(rest) = file_name.strip_prefix(STICKER_NAME_PREFIX) else { return "Sticker".to_owned() };
    let file = rest.strip_suffix(".gif").unwrap_or(rest);
    pack.iter().find(|s| s.file == file).map(|s| sticker_label(s.words.clone())).unwrap_or_else(|| "Sticker".to_owned())
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A 2x3 GIF89a with a 2-colour global table and `frames` one-pixel pictures.
    fn gif(frames: usize) -> Vec<u8> {
        let mut b = b"GIF89a".to_vec();
        b.extend([2, 0, 3, 0, 0x80, 0, 0]);
        b.extend([0, 0, 0, 255, 255, 255]);
        for _ in 0..frames {
            b.extend([0x21, 0xF9, 4, 0, 10, 0, 0, 0]); // a graphic control extension
            b.extend([0x2C, 0, 0, 0, 0, 2, 0, 3, 0, 0]); // image descriptor, no local table
            b.extend([2, 2, 0x44, 0x01, 0]); // LZW size, one sub-block of two bytes, end
        }
        b.push(0x3B);
        b
    }

    // GIFSupport's isGIF / frameCount.
    #[test]
    fn the_bytes_say_what_a_gif_is_and_how_many_pictures_it_has() {
        assert_eq!(gif_inspect(gif(3)), Some(GifFileInfo { frames: 3, width: 2, height: 3 }));
        assert_eq!(gif_inspect(gif(1)).map(|i| i.frames), Some(1));
        assert_eq!(gif_inspect(b"\x89PNG\r\n\x1a\n and some more bytes".to_vec()), None, "a PNG with a .gif name is not a GIF");
        assert_eq!(gif_inspect(b"GIF89a".to_vec()), None);
        assert_eq!(gif_inspect(gif(0)), None, "a header with no picture");
        let mut cut = gif(2);
        cut.truncate(cut.len() - 9);
        assert_eq!(gif_inspect(cut).map(|i| i.frames), Some(1), "a file cut short keeps the pictures before the cut");
    }

    #[test]
    fn a_big_or_broken_gif_is_refused_with_words() {
        assert_eq!(gif_problem(gif(3)), None);
        assert_eq!(gif_problem(gif(501)).as_deref(), Some("This GIF is too big to send"));
        assert_eq!(gif_problem(gif(500)), None);
        let mut heavy = gif(1);
        heavy.splice(heavy.len() - 1..heavy.len() - 1, std::iter::repeat(0u8).take(GIF_MAX_BYTES));
        assert_eq!(gif_problem(heavy).as_deref(), Some("This GIF is too big to send"));
        assert_eq!(gif_problem(b"hello".to_vec()).as_deref(), Some("That isn\u{2019}t a GIF"));
    }

    fn pack() -> Vec<StickerEntry> {
        let e = |file: &str, words: &str, find: &[&str]| StickerEntry { file: file.into(), words: words.into(), find: find.iter().map(|s| s.to_string()).collect() };
        vec![e("hi", "Hi!", &["hello", "hey"]), e("thank-you", "Thank you!", &["thanks", "ty"]), e("good-morning", "Good morning!", &["morning", "gm"])]
    }

    // StickerPackTests.
    #[test]
    fn a_typed_word_finds_the_stickers_it_starts() {
        let names = |q: &str, shown: bool| sticker_matching(q.into(), pack(), shown).into_iter().map(|s| s.file).collect::<Vec<_>>();
        assert_eq!(names("", true), ["hi", "thank-you", "good-morning"], "nothing typed: all of them");
        assert_eq!(names("thank", true), ["thank-you"]);
        assert_eq!(names("TY", true), ["thank-you"], "another finding word, any case");
        assert_eq!(names("good mor", true), ["good-morning"], "every typed word must start a word");
        assert_eq!(names("hey", true), ["hi"]);
        assert_eq!(names("zzz", true), Vec::<String>::new());
        assert_eq!(names("hi", false), Vec::<String>::new(), "the pack is hidden in Settings");
    }

    #[test]
    fn a_received_sticker_is_named_for_a_screen_reader() {
        assert_eq!(sticker_spoken_name("lime-sticker-thank-you.gif".into(), pack()), "lime sticker: Thank you!");
        assert_eq!(sticker_spoken_name("lime-sticker-unknown.gif".into(), pack()), "Sticker");
        assert_eq!(sticker_spoken_name("funny.gif".into(), pack()), "Sticker");
        assert_eq!(sticker_name_prefix(), "lime-sticker-");
    }
}
