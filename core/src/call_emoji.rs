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

/// One person's current media key in a group call, for `group_call_emoji`.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct GroupCallKey {
    pub participant: String,
    pub key: Vec<u8>,
}

/// The four emoji for a group call (LIME-147, v2 in LIME-147b): the first four bytes of
/// `SHA-256("lime-group-call-emoji-v2" || len32(call_id) || call_id || u32(count) || for each participant, sorted by participant id (byte
/// order of the id as sent): len32(participant_id) || participant_id || SHA-256(that participant's current key))`, every length and the count
/// a big-endian u32, the first four bytes indexing the list. Every variable-length field carries its length, so no two different calls or
/// groups of people can make the same input. Everyone in the call, me included, gets the same four exactly when every phone holds the same
/// current keys for the same people: a swapped key, or a hidden extra participant, changes them on someone's screen.
pub(crate) fn group_emoji_for(call_id: &str, mut people: Vec<(String, [u8; 32])>) -> [usize; 4] {
    people.sort_by(|a, b| a.0.as_bytes().cmp(b.0.as_bytes()));
    let mut hasher = Sha256::new();
    hasher.update(b"lime-group-call-emoji-v2");
    hasher.update((call_id.len() as u32).to_be_bytes());
    hasher.update(call_id.as_bytes());
    hasher.update((people.len() as u32).to_be_bytes());
    for (participant, key_hash) in &people {
        hasher.update((participant.len() as u32).to_be_bytes());
        hasher.update(participant.as_bytes());
        hasher.update(key_hash);
    }
    let digest = hasher.finalize();
    [digest[0] as usize, digest[1] as usize, digest[2] as usize, digest[3] as usize]
}

pub(crate) fn key_hash(key: &[u8]) -> [u8; 32] {
    Sha256::digest(key).into()
}

pub(crate) fn emoji_records(indexes: [usize; 4]) -> Vec<CallEmoji> {
    indexes.into_iter().map(|index| CallEmoji { emoji: EMOJI[index].0.to_owned(), name: EMOJI[index].1.to_owned() }).collect()
}

/// The four emoji to compare on a group call, from everyone's current keys (see `group_emoji_for`). The order the people are given in does
/// not matter. (The app asks the core for the call's own emoji; this is the same computation with the keys given, for other platforms and tests.)
#[uniffi::export]
pub fn group_call_emoji(call_id: String, participants: Vec<GroupCallKey>) -> Vec<CallEmoji> {
    emoji_records(group_emoji_for(&call_id, participants.into_iter().map(|p| (p.participant, key_hash(&p.key))).collect()))
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

    const GROUP_VECTOR: [usize; 4] = [60, 86, 17, 90];

    fn key(byte: u8) -> Vec<u8> {
        vec![byte; 32]
    }

    #[test]
    fn group_emoji_fixed_test_vector_so_every_platform_shows_the_same_four() {
        // Never change: another platform checks the same vector (the digest was also computed independently with Python's hashlib, v2).
        let call = "ab".repeat(32);
        let people = vec![
            GroupCallKey { participant: "0a".repeat(16), key: key(1) },
            GroupCallKey { participant: "0b".repeat(16), key: key(2) },
            GroupCallKey { participant: "0c".repeat(16), key: key(3) },
        ];
        let got = group_emoji_for(&call, people.iter().map(|p| (p.participant.clone(), key_hash(&p.key))).collect());
        assert_eq!(got, GROUP_VECTOR);
        let names: Vec<String> = group_call_emoji(call, people).into_iter().map(|e| e.name).collect();
        assert_eq!(names, GROUP_VECTOR.map(|i| EMOJI[i].1.to_owned()));
    }

    #[test]
    fn group_emoji_do_not_depend_on_the_order_the_people_are_listed_in() {
        let call = "cd".repeat(32);
        let a = GroupCallKey { participant: "01".repeat(16), key: key(9) };
        let b = GroupCallKey { participant: "02".repeat(16), key: key(8) };
        let c = GroupCallKey { participant: "03".repeat(16), key: key(7) };
        let one = group_call_emoji(call.clone(), vec![a.clone(), b.clone(), c.clone()]);
        assert_eq!(one, group_call_emoji(call.clone(), vec![c.clone(), a.clone(), b.clone()]));
        assert_eq!(one, group_call_emoji(call, vec![b, c, a]));
        assert_eq!(one.len(), 4);
    }

    #[test]
    fn a_changed_key_a_hidden_extra_person_another_call_or_a_swapped_key_changes_the_group_emoji() {
        let call = "ef".repeat(32);
        let a = GroupCallKey { participant: "01".repeat(16), key: key(1) };
        let b = GroupCallKey { participant: "02".repeat(16), key: key(2) };
        let base = group_call_emoji(call.clone(), vec![a.clone(), b.clone()]);
        let rekeyed = GroupCallKey { participant: b.participant.clone(), key: key(3) };
        assert_ne!(base, group_call_emoji(call.clone(), vec![a.clone(), rekeyed]), "a changed key");
        let hidden = GroupCallKey { participant: "03".repeat(16), key: key(4) };
        assert_ne!(base, group_call_emoji(call.clone(), vec![a.clone(), b.clone(), hidden]), "an extra participant nobody else sees");
        assert_ne!(base, group_call_emoji("00".repeat(32), vec![a.clone(), b.clone()]), "another call");
        let swapped = vec![GroupCallKey { participant: a.participant.clone(), key: b.key.clone() }, GroupCallKey { participant: b.participant.clone(), key: a.key.clone() }];
        assert_ne!(base, group_call_emoji(call, swapped), "the same keys given to the other people");
    }

    #[test]
    fn group_emoji_input_is_unambiguous_where_the_first_version_was_not() {
        let hash = key_hash(&key(5));
        // The call id and the participant id used to be concatenated bare: moving a character from one to the other made the same bytes.
        let a = group_emoji_for("ab", vec![("c".to_owned(), hash)]);
        let b = group_emoji_for("a", vec![("bc".to_owned(), hash)]);
        assert_ne!(a, b, "the boundary between the call id and a participant id matters");
        // The same between two participant ids.
        let c = group_emoji_for("call", vec![("ab".to_owned(), hash), ("c".to_owned(), hash)]);
        let d = group_emoji_for("call", vec![("a".to_owned(), hash), ("bc".to_owned(), hash)]);
        assert_ne!(c, d);
        // And the label says which version this is: v1's vector is not v2's.
        assert_ne!(group_emoji_for(&"ab".repeat(32), vec![("0a".repeat(16), key_hash(&key(1)))]), [185, 93, 172, 216]);
    }
}
