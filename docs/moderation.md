# Moderation: Report, the queue and takedowns (LIME-191)

App Store guideline 1.2 asks for three things in an app with user-generated content: a way to **report**, a way to **block**, and **action on reports**. Block exists (LIME-96); this is the other two. It must exist before "Everyone on lime" posts go live (`docs/jam.md` §13.9: the `open_posts_enabled` flag stays off until this and the student-privacy check ship).

## What a person can report

A message (long-press → Report), a person (their profile ⋯), a jam post (the card ⋯, the article's Options, the player ⋯), a comment (its ⋯) and a jam / org page (its ⋯). Not yet: a whole group (report a message in it), and a profile's photo, background or links on their own (report the person).

## The flow

Report → **reason** (Harassment or bullying · Spam or scam · Impersonation · Inappropriate or sexual content · **A child's safety** · Hate or violence · Something else) → optional note (500 characters) → **Include this message/post/comment** (on by default; the sheet shows what will be sent) → for a person's content, **Also block** (when there is a chat with them) → Send → "Thanks. lime's team will look at this." The reported person is never told who reported.

## What travels, and who learns what

The reporter's phone builds `{ id, subject_kind, subject_ids, reason, note, included, reporter, created }`, seals it to the server's **moderation key** (a key pair of its own, pinned in `core/src/client/moderation.rs`; X25519 + HKDF-SHA256 label `lime-report-v1` + AES-256-GCM, the mesh header's construction) and sends it to `report`.

| Who | Learns |
| --- | --- |
| lime's moderators (allow-listed, in the app) | exactly what the reporter included, the note, the reason, who reported, and the ids of what is reported |
| the `report` function / database | who reported, the kind of subject, the reason, when; the sealed bytes (it cannot open them) |
| the reported person, other members | nothing |

Nobody else's encryption changes: only the reporter's own copy of one item leaves their phone, by their choice. What the phone holds is what is reported: an edited message is the edited text; a deleted one has nothing to report. A post's report carries the **blob id** that holds the post now.

## Who moderates

An account in `moderators` (seeded by the founders in SQL). In the app: **Settings → Moderation** (shown only to those accounts; the phone asks the server once per launch). Open reports first, urgent (a child's safety) on top; each opens to what was sent, with: **Dismiss · Hide post · Take page down · Remove public picture · Suspend account** (each asks first; a note is kept). Every open and every action is logged in `moderation_actions` (who, when, what).

New reports also **email** `MODERATION_EMAIL` (needs `RESEND_API_KEY`; subject = the reason, "URGENT:" for a child's safety; **no content in the email**).

## What the server can do, and what it cannot

| Action | Effect | Limit |
| --- | --- | --- |
| Hide post | `jam-blob-get` refuses that blob | phones that already have the post keep it; an edit makes a new blob (report again, or take the page down) |
| Take page down | `jam-page` answers 410, the page leaves lookups | posts already on phones stay |
| Remove public picture | the Everyone photo / links / background object is deleted and its column cleared | contacts-only copies are ciphertext the server cannot read |
| Suspend account | sign-in and every call with a session are refused: "This account is suspended" | a **signed** send (no session, by design) cannot be tied to an account; messages already delivered stay |
| Lift a suspension | as it says | |

**Nothing can reach into anyone's phone.** Messages are end-to-end encrypted; the tool says so.

## Aims

Look at every report within **24 hours**; a child's safety **at once**. Reports are kept **180 days after they are resolved**, then deleted with their actions (`sweep_moderation`, run by the blob sweep).

## Child safety: the legal step still open

In the US, a provider that learns of child sexual abuse material must report it to NCMEC's CyberTipline (18 U.S.C. § 2258A), and keep what it reports for a period. Because reports are the only way lime learns of content, this applies to a "A child's safety" report that shows such material. **The exact process (who files, what is preserved, how it fits the 180-day deletion) needs the lawyer before launch.** Until then a child-safety report is only escalated by hand.

## Setting it up (staging)

1. Apply the migration and deploy the functions (`supabase/deploy-staging.sh`): `report`, `moderation-list`, `moderation-open`, `moderation-act`.
2. Set the moderation secret: `supabase secrets set --env-file ~/.lime/moderation-secret.env --project-ref <ref>` (the file holds `MODERATION_SECRET_KEY`; its public half is pinned as key id 1). Then delete the file or keep it somewhere safe: **it is the only copy of the secret**.
3. Optional: `MODERATION_EMAIL`, `RESEND_API_KEY` (and `MODERATION_FROM`).
4. Add yourself: `insert into public.moderators (user_id) values ('<your user id>');`
