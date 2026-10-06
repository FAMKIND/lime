//! The made-up sample content (teachers and groups only; no real names, emails or phone numbers).
//! It moved here from the iOS app's `SampleData.swift`.

use rusqlite::{params, Transaction};

use super::{new_id, ME_ID};

/// (id, name, avatar palette index)
const PEOPLE: &[(&str, &str, u32)] = &[
    (ME_ID, "Shem Rajoon", 4),
    ("jean", "Jean Chung", 3),
    ("grace", "Grace Ortiz", 0),
    ("rise", "Rise Okafor", 2),
    ("journey", "Journey Park", 6),
    ("autumn", "Autumn Reyes", 7),
    ("marcus", "Marcus Bell", 5),
];

struct Sample {
    id: &'static str,
    title: &'static str,
    members: &'static [&'static str],
    pinned: bool,
    unread: u32,
    /// (sender id, text, minutes ago)
    messages: &'static [(&'static str, &'static str, i64)],
}

const CONVERSATIONS: &[Sample] = &[
    Sample {
        id: "c1",
        title: "Journey Park",
        members: &["journey"],
        pinned: true,
        unread: 1,
        messages: &[
            (
                "journey",
                "Have you tried the new bakery by the school? Their muffins are huge.",
                60 * 26,
            ),
            (ME_ID, "Not yet! Is it worth the line?", 60 * 26 - 3),
            (
                "journey",
                "Totally. Want to go before first bell on Friday? I can save us a table.",
                55,
            ),
        ],
    },
    Sample {
        id: "c2",
        title: "Autumn Reyes",
        members: &["autumn"],
        pinned: false,
        unread: 2,
        messages: &[
            ("autumn", "Can you share the unit plan for fractions?", 120),
            (ME_ID, "Sending it over after lunch.", 118),
            (
                "autumn",
                "Thank you, that helps a lot. Also, do you have the exit tickets?",
                40,
            ),
        ],
    },
    Sample {
        id: "c3",
        title: "Jean, Rise & Me",
        members: &["jean", "rise"],
        pinned: false,
        unread: 0,
        messages: &[
            (
                "jean",
                "Did anyone get the field trip forms back yet?",
                60 * 30,
            ),
            (
                "rise",
                "Eleven so far. Two more families said they'd send them tomorrow.",
                60 * 29,
            ),
            (
                ME_ID,
                "Perfect, I'll make a list of who's still missing.",
                60 * 28,
            ),
            (
                "jean",
                "Thanks! The bus company wants a final headcount by Thursday.",
                60 * 27,
            ),
            (
                ME_ID,
                "Got it. I'll send the count Wednesday night.",
                60 * 26,
            ),
        ],
    },
    Sample {
        id: "c4",
        title: "Grade 4 Team",
        members: &["grace", "marcus", "jean", "rise"],
        pinned: false,
        unread: 0,
        messages: &[
            (
                "grace",
                "Reminder: report card comments are due Thursday.",
                60 * 52,
            ),
            (
                "marcus",
                "Thanks. Is the template still the one from last term?",
                60 * 51,
            ),
            (ME_ID, "Same template, same folder.", 60 * 50),
        ],
    },
    Sample {
        id: "c5",
        title: "Science Fair Committee",
        members: &["journey", "autumn", "grace", "marcus", "jean", "rise"],
        pinned: false,
        unread: 0,
        messages: &[
            ("marcus", "Judges are confirmed for the 14th.", 60 * 80),
            ("autumn", "I'll print the rubrics.", 60 * 79),
        ],
    },
];

pub(crate) fn insert(tx: &Transaction<'_>, now_ms: i64) -> rusqlite::Result<()> {
    for (id, name, tone) in PEOPLE {
        tx.execute(
            "INSERT OR IGNORE INTO people (id, name, tone) VALUES (?1, ?2, ?3)",
            params![id, name, tone],
        )?;
    }
    for conversation in CONVERSATIONS {
        tx.execute(
            "INSERT INTO conversations (id, title, is_group, is_pinned, unread)
             VALUES (?1, ?2, ?3, ?4, ?5)",
            params![
                conversation.id,
                conversation.title,
                conversation.members.len() > 1,
                conversation.pinned,
                conversation.unread
            ],
        )?;
        // Everyone in the conversation, me included, with a stable display order.
        for (position, person) in conversation.members.iter().enumerate() {
            tx.execute(
                "INSERT INTO members (conversation_id, person_id, position) VALUES (?1, ?2, ?3)",
                params![conversation.id, person, position as i64],
            )?;
        }
        tx.execute(
            "INSERT INTO members (conversation_id, person_id, position) VALUES (?1, ?2, ?3)",
            params![conversation.id, ME_ID, conversation.members.len() as i64],
        )?;
        for (sender, text, minutes_ago) in conversation.messages {
            tx.execute(
                "INSERT INTO messages (id, conversation_id, sender_id, body, sent_at, local_state)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
                params![
                    new_id(),
                    conversation.id,
                    sender,
                    text,
                    now_ms - minutes_ago * 60_000,
                    super::LOCAL_STATE_SENT_LOCAL
                ],
            )?;
        }
    }
    Ok(())
}
