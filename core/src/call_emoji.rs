//! Emoji call verification (LIME-119): both people on a 1:1 call see the same four emoji if, and only if, they hold the same media
//! keys, which means nobody is in between. The four come from the two DTLS fingerprints (each phone signs its own into its offer or
//! answer, so a relay cannot swap them) and the call id. Kept in the core so other platforms show the same four.
//!
//! The list is fixed: 256 simple, distinct, nameable emoji (animals, food, plants, objects). No flags, no skin tones, no emoji made
//! from several parts, and none that look alike. **Never reorder or edit it**: that would change what two phones of different
//! versions show for the same call.

use sha2::{Digest, Sha256};

/// One of the four, with its spoken name for screen readers.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct CallEmoji {
    pub emoji: String,
    pub name: String,
}

pub(crate) const EMOJI: [(&str, &str); 256] = [
    ("🐶", "dog"),
    ("🐱", "cat"),
    ("🐭", "mouse"),
    ("🐹", "hamster"),
    ("🐰", "rabbit"),
    ("🦊", "fox"),
    ("🐻", "bear"),
    ("🐼", "panda"),
    ("🐨", "koala"),
    ("🐯", "tiger"),
    ("🦁", "lion"),
    ("🐮", "cow"),
    ("🐷", "pig"),
    ("🐸", "frog"),
    ("🐵", "monkey"),
    ("🐔", "chicken"),
    ("🐧", "penguin"),
    ("🐦", "bird"),
    ("🦆", "duck"),
    ("🦉", "owl"),
    ("🦇", "bat"),
    ("🐺", "wolf"),
    ("🐗", "boar"),
    ("🐴", "horse"),
    ("🦄", "unicorn"),
    ("🐝", "bee"),
    ("🐛", "caterpillar"),
    ("🦋", "butterfly"),
    ("🐌", "snail"),
    ("🐞", "ladybug"),
    ("🐜", "ant"),
    ("🐢", "turtle"),
    ("🐍", "snake"),
    ("🦎", "lizard"),
    ("🦖", "dinosaur"),
    ("🐙", "octopus"),
    ("🦑", "squid"),
    ("🦀", "crab"),
    ("🐠", "fish"),
    ("🐬", "dolphin"),
    ("🐳", "whale"),
    ("🦈", "shark"),
    ("🐊", "crocodile"),
    ("🐘", "elephant"),
    ("🦒", "giraffe"),
    ("🦓", "zebra"),
    ("🐪", "camel"),
    ("🐑", "sheep"),
    ("🐐", "goat"),
    ("🦌", "deer"),
    ("🦔", "hedgehog"),
    ("🦘", "kangaroo"),
    ("🦥", "sloth"),
    ("🦦", "otter"),
    ("🦩", "flamingo"),
    ("🦚", "peacock"),
    ("🦜", "parrot"),
    ("🦢", "swan"),
    ("🐓", "rooster"),
    ("🦃", "turkey"),
    ("🦭", "seal"),
    ("🍎", "apple"),
    ("🍐", "pear"),
    ("🍊", "orange"),
    ("🍋", "lemon"),
    ("🍌", "banana"),
    ("🍉", "watermelon"),
    ("🍇", "grapes"),
    ("🍓", "strawberry"),
    ("🍒", "cherries"),
    ("🥭", "mango"),
    ("🍍", "pineapple"),
    ("🥥", "coconut"),
    ("🥝", "kiwi"),
    ("🍅", "tomato"),
    ("🥑", "avocado"),
    ("🥕", "carrot"),
    ("🌽", "corn"),
    ("🥦", "broccoli"),
    ("🍄", "mushroom"),
    ("🥜", "peanuts"),
    ("🍞", "bread"),
    ("🥐", "croissant"),
    ("🥨", "pretzel"),
    ("🧀", "cheese"),
    ("🥚", "egg"),
    ("🥞", "pancakes"),
    ("🍔", "burger"),
    ("🍟", "fries"),
    ("🍕", "pizza"),
    ("🌭", "hot dog"),
    ("🌮", "taco"),
    ("🍿", "popcorn"),
    ("🍩", "doughnut"),
    ("🍪", "cookie"),
    ("🎂", "cake"),
    ("🍫", "chocolate"),
    ("🍬", "candy"),
    ("🍭", "lollipop"),
    ("🍦", "ice cream"),
    ("🍯", "honey"),
    ("☕", "coffee"),
    ("🍵", "tea"),
    ("🥛", "milk"),
    ("🥤", "cup with straw"),
    ("🍙", "rice ball"),
    ("🍜", "noodles"),
    ("🍣", "sushi"),
    ("🥟", "dumpling"),
    ("🥗", "salad"),
    ("🧁", "cupcake"),
    ("🥧", "pie"),
    ("🌵", "cactus"),
    ("🌴", "palm tree"),
    ("🌲", "pine tree"),
    ("🌳", "oak tree"),
    ("🍀", "clover"),
    ("🍁", "maple leaf"),
    ("🌻", "sunflower"),
    ("🌹", "rose"),
    ("🌷", "tulip"),
    ("🌸", "blossom"),
    ("🌼", "daisy"),
    ("🌿", "herb"),
    ("🌙", "moon"),
    ("⭐", "star"),
    ("🌈", "rainbow"),
    ("⛄", "snowman"),
    ("🔥", "fire"),
    ("💧", "droplet"),
    ("🌊", "wave"),
    ("🌋", "volcano"),
    ("🌍", "globe"),
    ("⚡", "lightning"),
    ("🪐", "ringed planet"),
    ("🌰", "chestnut"),
    ("🍂", "fallen leaves"),
    ("🎈", "balloon"),
    ("🎁", "gift"),
    ("🎸", "guitar"),
    ("🎹", "piano keys"),
    ("🥁", "drum"),
    ("🎺", "trumpet"),
    ("🎻", "violin"),
    ("🎨", "paint palette"),
    ("📚", "books"),
    ("📖", "open book"),
    ("📝", "notepad"),
    ("🔑", "key"),
    ("🔔", "bell"),
    ("🔨", "hammer"),
    ("🔧", "wrench"),
    ("🧲", "magnet"),
    ("🔦", "flashlight"),
    ("💡", "light bulb"),
    ("🔋", "battery"),
    ("📷", "camera"),
    ("🔭", "telescope"),
    ("🔬", "microscope"),
    ("🧭", "compass"),
    ("⏰", "alarm clock"),
    ("⌛", "hourglass"),
    ("🎲", "dice"),
    ("🧩", "puzzle piece"),
    ("🎯", "bullseye"),
    ("🏆", "trophy"),
    ("🏀", "basketball"),
    ("⚽", "soccer ball"),
    ("🏈", "football"),
    ("⚾", "baseball"),
    ("🎾", "tennis ball"),
    ("🏐", "volleyball"),
    ("🎳", "bowling pin"),
    ("🪁", "kite"),
    ("⛵", "sailboat"),
    ("🚲", "bicycle"),
    ("🚗", "car"),
    ("🚌", "bus"),
    ("🚂", "train"),
    ("🚀", "rocket"),
    ("🚁", "helicopter"),
    ("🛵", "scooter"),
    ("🚜", "tractor"),
    ("🏠", "house"),
    ("🏰", "castle"),
    ("⛺", "tent"),
    ("🧸", "teddy bear"),
    ("🪑", "chair"),
    ("🚪", "door"),
    ("🧦", "socks"),
    ("🧢", "cap"),
    ("👑", "crown"),
    ("💎", "gem"),
    ("👓", "glasses"),
    ("🎒", "backpack"),
    ("📌", "pushpin"),
    ("📎", "paperclip"),
    ("🧵", "thread"),
    ("🧶", "yarn"),
    ("🔍", "magnifier"),
    ("⚓", "anchor"),
    ("🧪", "test tube"),
    ("🧬", "dna"),
    ("🥇", "gold medal"),
    ("🧯", "fire extinguisher"),
    ("🎤", "microphone"),
    ("🎧", "headphones"),
    ("📻", "radio"),
    ("📺", "television"),
    ("💻", "laptop"),
    ("🍰", "shortcake"),
    ("🥔", "potato"),
    ("🌶", "chili"),
    ("🥖", "baguette"),
    ("🥩", "steak"),
    ("🍗", "drumstick"),
    ("🍤", "shrimp"),
    ("🍡", "dango"),
    ("🌑", "new moon"),
    ("🌞", "sun with face"),
    ("🍃", "leaves"),
    ("🌾", "rice plant"),
    ("🐚", "shell"),
    ("🪵", "log"),
    ("🧊", "ice cube"),
    ("🪄", "magic wand"),
    ("🎃", "pumpkin"),
    ("🎄", "christmas tree"),
    ("🎆", "fireworks"),
    ("🧳", "luggage"),
    ("🛶", "canoe"),
    ("🪂", "parachute"),
    ("🛹", "skateboard"),
    ("🪀", "yo-yo"),
    ("🎷", "saxophone"),
    ("🪕", "banjo"),
    ("🔮", "crystal ball"),
    ("🧿", "nazar amulet"),
    ("📡", "satellite dish"),
    ("🔌", "plug"),
    ("🧱", "brick"),
    ("🪞", "mirror"),
    ("🪟", "window"),
    ("🧴", "lotion bottle"),
    ("🧼", "soap"),
    ("🪥", "toothbrush"),
    ("🧹", "broom"),
    ("🪣", "bucket"),
    ("🛒", "shopping cart"),
    ("🥒", "cucumber"),
    ("🍠", "sweet potato"),
    ("🥬", "lettuce"),
    ("🧅", "onion"),
    ("🍈", "melon"),
    ("🥫", "canned food"),
    ("🍘", "rice cracker"),
];

fn normalise(fingerprint: &str) -> String {
    fingerprint.trim().to_ascii_uppercase()
}

/// The four emoji for a call: the first four bytes of `SHA-256("lime-call-emoji-v1" || call_id || fp_caller || fp_callee)`, each
/// indexing the list. The fingerprints are the DTLS `a=fingerprint` values (case and spacing do not matter); the caller's is the
/// one in the offer and the callee's the one in the answer, so both phones compute the same four whichever side they are.
pub(crate) fn emoji_for(call_id: &str, fp_caller: &str, fp_callee: &str) -> [usize; 4] {
    let mut hasher = Sha256::new();
    hasher.update(b"lime-call-emoji-v1");
    hasher.update(call_id.as_bytes());
    hasher.update(normalise(fp_caller).as_bytes());
    hasher.update(normalise(fp_callee).as_bytes());
    let digest = hasher.finalize();
    [digest[0] as usize, digest[1] as usize, digest[2] as usize, digest[3] as usize]
}

/// The four emoji to compare on a call (see the module notes).
#[uniffi::export]
pub fn call_emoji(call_id: String, fp_caller: String, fp_callee: String) -> Vec<CallEmoji> {
    emoji_for(&call_id, &fp_caller, &fp_callee)
        .into_iter()
        .map(|index| CallEmoji { emoji: EMOJI[index].0.to_owned(), name: EMOJI[index].1.to_owned() })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashSet;

    #[test]
    fn the_list_has_256_unique_single_codepoint_emoji_and_unique_names() {
        assert_eq!(EMOJI.len(), 256);
        assert_eq!(EMOJI.iter().map(|(e, _)| *e).collect::<HashSet<_>>().len(), 256, "emoji are unique");
        assert_eq!(EMOJI.iter().map(|(_, n)| *n).collect::<HashSet<_>>().len(), 256, "names are unique");
        for (emoji, name) in EMOJI {
            assert_eq!(emoji.chars().count(), 1, "{name} is one code point (no joiners, no skin tones, no variation selectors)");
            assert!(!name.is_empty());
            assert!(!('\u{1F1E6}'..='\u{1F1FF}').contains(&emoji.chars().next().unwrap()), "no flags");
            assert!(!('\u{1F3FB}'..='\u{1F3FF}').contains(&emoji.chars().next().unwrap()), "no skin tones");
        }
    }

    #[test]
    fn fixed_test_vectors_so_every_platform_shows_the_same_four() {
        // These must never change: another platform checks the same vectors (the digest was also computed independently with Python's hashlib).
        let fp_a = "AB:CD:EF:01:23:45:67:89";
        let fp_b = "01:23:45:67:89:AB:CD:EF";
        assert_eq!(emoji_for("call-1", fp_a, fp_b), [160, 252, 66, 95]);
        let words: Vec<String> = call_emoji("call-1".into(), fp_a.into(), fp_b.into()).into_iter().map(|e| e.name).collect();
        assert_eq!(words, [EMOJI[160].1, EMOJI[252].1, EMOJI[66].1, EMOJI[95].1]);
    }

    #[test]
    fn the_same_four_whichever_phone_computes_them_and_however_the_fingerprints_are_written() {
        let a = call_emoji("call-9".into(), "ab:cd:ef".into(), "01:02:03".into());
        let b = call_emoji("call-9".into(), "AB:CD:EF".into(), " 01:02:03 ".into());
        assert_eq!(a, b);
        assert_eq!(a.len(), 4);
    }

    #[test]
    fn a_changed_fingerprint_or_call_changes_the_emoji() {
        let base = emoji_for("call-9", "AB:CD:EF", "01:02:03");
        assert_ne!(base, emoji_for("call-9", "AB:CD:EE", "01:02:03"), "a swapped caller key");
        assert_ne!(base, emoji_for("call-9", "AB:CD:EF", "01:02:04"), "a swapped callee key");
        assert_ne!(base, emoji_for("call-10", "AB:CD:EF", "01:02:03"), "another call");
        assert_ne!(base, emoji_for("call-9", "01:02:03", "AB:CD:EF"), "the roles are not interchangeable");
    }
}
