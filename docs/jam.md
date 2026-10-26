# jam v1: encrypted subscriptions for teachers (design, LIME-185)

**Status: the design (LIME-185), decided by the user on 2026-10-21 and built in LIME-186 (core) and LIME-187 (server): archive = option C with private fetching, 1,000 subscribers, comments via the writer, any signed-in teacher can start a jam. Where the build differs from the design below, a note says so.** This replaces the public, server-readable jam of LIME-110.

## 0. What jam is for

lime is *Education for all: a private community where teachers connect and learn from each other.* **link** connects, **call** meets, **jam is where teachers create and learn from each other** (and later **discover** finds teachers by subject, grade and expertise). So jam is designed as **professional development first**; the Substack-like mechanics (posts, a free/subscribers-only wall, an archive, optional payment later) are only the tools.

- **Posts shaped for how teachers learn:** a lesson with its materials, a short classroom clip (under the student-privacy rules: no faces of students unless the teacher has the right to share), a reflection, a series. A post is the existing message format (the Markdown subset, `message-format.md`) plus attachments (api-v2, "Attachments (LIME-98c)"); no new content type is needed in v1. A "series" is a title tag on posts in v1.
- **Discovery** by subject, grade, topics and "teachers I know". In v1 a jam page carries these as chosen metadata (§7).
- **Room for shared jams** (a school, a district, a subject group): v1 is **one writer per jam**; the model keeps a `writers` list of length 1 so shared jams can lengthen it (§2).
- **Evidence to design for** (the 2024 Oxford/IBO teacher-wellbeing report): peer support and feedback are what teachers value most and rarely get (71% value peer feedback, 9% give it). So: **recognition is about growth, not performance**: ♥ counts are visible **to the writer only**; no public ranking, no "top posts", no follower counts shown to others. **jam must not add workload or pressure:** quiet by default (no notification unless the teacher turns it on per jam), no streaks, no "you haven't posted" nudges, no read receipts.

## 1. Decisions already made (the user, 2026-10-20)

| | Decision |
|---|---|
| J1 | Posts are **end-to-end encrypted** to subscribers (a one-way encrypted channel built on lime's group messaging). The server cannot read posts. |
| J2 | **Anyone signed in can subscribe** (Subscribe on a teacher's profile or jam link); the writer can remove someone. |
| J3 | A **new subscriber gets the full archive** (handed over by the writer's side). |
| J4 | Responses: **♥ likes**, **comments all subscribers see**, and a **private "reply to the writer"** that opens a 1:1 chat. |
| – | **Tiers in the model from v1** (free / paid subscribers; a post is `free` or `subscribers`), **payments off in v1**. **Every jam has free posts** (a writer cannot be paywall-only). Reading even free posts needs a (free) subscription, so every post stays encrypted. |
| – | Not v1: payments and tips; public feeds. |

### 1b. Redesign decisions (the user, 2026-10-21, after trying LIME-188; LIME-188b)

The first jam tab ("Following" beside a "Your jam" area you had to set up) was confusing. The user wants **the shape of Substack's app**: one feed, a **+** to post, the **profile as the publication page**. Decided:

- **Counts are public, there are no rankings.** ♥, comment and **remix** counts, and a profile's **subscriber count**, are visible to everyone who can see the post or the profile; there is **no "#N in ..." leaderboard and no "top posts"**. This **replaces** the earlier rule (sections 0 and 5) that ♥ counts are visible to the writer only. The wellbeing aim is kept in the other ways: quiet by default, no streaks, no "you haven't posted" nudges, recognition by what was said and not a ranking. (Counts of ♥/comments/remixes arrive with LIME-189; the subscriber count is here.)
- **Post kinds:** a **quick post** (words and photos, no title), an **article** (title, subtitle, body) and a **recording**, which is a podcast (LIME-188g): audio by default (up to 60 minutes, about 14 MB at 32 kbps, inside a jam file's 24 MiB) or video with the camera on (up to 3 minutes, re-encoded to fit 24 MiB), a title, optional co-hosts (the 188f credit flow), and a waveform computed on the writer's phone and sent in the attachment's `thumb`. The player scrubs, skips (−15 s / +30 s), changes speed (1× / 1.5× / 2×) and plays on the lock screen. Captions are out of v1. Go Live is later.
- **One button: Subscribe** (free). There is no separate Follow.
- **Remix** (Substack's "restack", renamed): a teacher re-shares another's post to their own subscribers. It needs an encryption design of its own (LIME-189b); the feed card shows a dimmed "remix" icon until then.
- **An article is a page, and its photos stand in the text** (LIME-188e): the article page is the full composer (photo, camera and file in the bar above the keyboard, with the formatting); each picture goes **in the text at the caret** as a block of its own, written `![caption](attachment:n)` (jam posts only; see `docs/message-format.md`). The reader shows each one in place; a quick post keeps its photos as a row under the words. A subtitle is one short line (at most 160 characters) and never holds the article.
- **Co-authors and co-hosts (LIME-188f/g): a credit, and two profiles.** A writer can ask up to four of their contacts to be credited on a post. The post lives in the writer's jam and goes only to the writer's subscribers; the co-author gets an encrypted **request** (with the post's title and where to download it), answers it in a calm prompt, and **only once they accept** does "with Jean Chung" show (the writer's phone announces the acceptance to the subscribers in the post's own session). An accepted post is also kept on the co-author's phone with the posts they are credited on. A declined or unanswered request shows nothing. The server learns nothing new (all of it is encrypted). *Not yet:* the co-author's profile as seen by other people (it needs the discovery data of LIME-190: viewers who are not subscribers would see "Subscribe to <writer> to read").
- **Post as:** you, for now; the chooser is there for a school or subject group when shared jams exist.
- **Nothing to set up:** a teacher's jam is made on their **first post** (named for them, with their profile's about line); its title, about and topics are edited from their profile ("Edit jam page").
- **The profile is the jam page:** name, username, subscriber count, **Subscribe / Subscribed**, and posts (readable once subscribed; before that the page says "Subscribe to read their posts", because the server's page holds no post text).

## 2. The model

A **jam** is a new conversation kind beside `dm:` and `grp:`: `jam:<jam_id>`.

**Phase 1 (a): can it sit on LIME-97's group-state log?** *The crypto and plumbing, yes; the state log itself, no.* Reuse: sender certificates and op signatures (`protocol/`), Olm delivery of control ops (`send_to_user`, sealed where we hold the delivery key), Megolm sessions shared as a `group.session`-style op (`core/src/client/groups.rs`), the conversation store, the mesh/outbox. Do **not** reuse `protocol::group` and its member roster: that log makes every member a state author, replays a full roster on every phone (`group.history` sends the whole log to a joiner, api-v2 §11), caps at `MAX_MEMBERS = 100` (`protocol/group.rs:25`) and shows everyone to everyone. A jam wants the opposite: **one author, many readers who do not need to see each other.** So:

- **Jam state** (signed by the writer only, tiny): `jam.create { title, about, topics[], tiers }`, `jam.update`, `jam.remove { subscriber }`, `jam.end`. Every subscriber stores it; none holds a roster.
- **Subscriber set** lives **only on the writer's phone** (a table `jam_subscribers(user, since, tier, removed_at)`), never sent to subscribers. (Comments reveal their authors by design; nothing else does.)
- **Ops:** `jam.subscribe` (subscriber → writer, Olm), `jam.welcome` (writer → subscriber: the jam state, the current session key, the archive index, §3), `jam.post` (writer → subscribers, Megolm), `jam.session` (writer → subscribers, Olm: a new session key), `jam.react` and `jam.comment` (§5), `jam.remove`.
- A post is an ordinary encrypted message body with `{ post_id, tier: free|subscribers, title, markdown, attachments[], series? }`, authored (signed) by the writer's device.
- `writers: [user]` has length 1 in v1. A shared jam later makes it longer, each writer with their own Megolm session (as groups do per sending device).

## 3. Rotation, the archive, and keys (Phase 1 b and c)

**(b) Rotation.** Today `ensure_group_session` (`core/src/client/groups.rs` ~555) replaces the outbound session when `rotate` is set (set on any membership change, `store/groups.rs:144`), after **100 messages** or **7 days** (`ROTATE_AFTER_MESSAGES`, `ROTATE_AFTER_MS`), or when the recipient fingerprint changes. For a jam: since every new subscriber receives the whole archive anyway (J3), **rotating on a join protects nothing, so do not.** Rotate on **removal** (so a removed subscriber cannot read later posts), after 100 posts or 7 days as now (limits the damage of one stolen key to a window; the cost is one `jam.session` Olm message per subscriber device per rotation), and on `jam.end`. This is sound: forward secrecy for a removed person is kept, nothing else was ever protected by rotating on a join. The writer's phone keeps the **first-index key of every session it ever made** (a ~229-byte `SessionKey` each; see below) so the archive can be handed over.

**(c) The archive: three options.**

| | How | Server learns / holds | Cost |
|---|---|---|---|
| **A. Writer's phone re-sends** | On `jam.welcome` the writer re-sends every past post (and its keys) over the same encrypted channel | Nothing new (just ordinary mailbox traffic) | The writer must be online for each joiner; a 200-post archive with attachments is a big upload per joiner; joins in bursts hurt. Undelivered mailbox items last 30 days (api-v2 §2). |
| **B. Server ciphertext archive** | Each post is uploaded **once** as an encrypted blob (the attachment pipeline, api-v2 "Attachments (LIME-98c)": AES-256-GCM, key in the post, `blobs` bucket) with a new long retention class; the writer sends subscribers only the post id + key | A blob exists: its **size, time, id** and **which accounts fetch it**, for the life of the jam (today files live ~1 h after the last fetch or 30 days: `architecture.md` ~85, so this is **new retention**). It cannot read content. | Writer need not be online; one upload per post; fan-out is a small notice. Needs a server change (retention + quota). |
| **C. Both (recommended)** | Posts are blobs (B); the writer's phone hands a joiner the **index of post ids + keys + the session first-index keys** in `jam.welcome` (A's channel, but tiny) | As B | The welcome is a few KB for hundreds of posts. A joiner fetches blobs at its own pace, from the server, with the writer offline. The writer's phone remains the only holder of the *keys* (the server holds only ciphertext it cannot open). |

**Experiment (throwaway, not committed):** with `vodozemac` 0.11.1, a subscriber given a writer session's **first-index key** (`GroupSession::session_key()` taken at creation, 229 bytes) decrypted five earlier posts **and** a later one; `InboundGroupSession::export_at(i)` produced a key that reads from index *i* on and refused earlier posts. So one stored key per session is enough to give a joiner the whole archive of that session, and a key at index *i* could give a "from here on" view if ever wanted.

**Built (LIME-186/187): C, with private fetching.** In the build the archive travels as an **index** (`jam.index`: post id, title, blob id, key, hash, size, for each post a subscriber may read) and each post is a blob on the server fetched **without a session** (`jam-blob-get`); the welcome carries only the *current* session keys (the old first-index keys of the design are not needed, because each blob has its own key). **Recommendation was: C.** It is the only option that works while the writer is offline and does not make the writer's phone a server, and the extra the server learns (blob sizes, times, who fetches) is the same class it already learns for attachments.

## 4. Scale (Phase 1 d)

Limits today: groups hold **100** people (`MAX_MEMBERS`); `/v2/send` takes **500 recipient devices** per request (api-v2 §11 implementation guards) and the client chunks at **100** (`SEND_CHUNK`). For a jam of *N* subscribers with *D* devices each:

- A post is encrypted **once**; the same ciphertext goes to all *N·D* devices in ⌈*N·D*/100⌉ chunked sends (the server's 500 cap is per request, so it is not a hard ceiling, only more requests). With blobs (option C) the Megolm message is only a notice with a post id and key, a few hundred bytes.
- A rotation costs *N·D* Olm messages (key distribution), done lazily as for groups.
- A subscribe is one Olm message in and one welcome out.

**v1's honest limit: 100 subscribers per jam**, so the first build reuses the group sending code, sizes and tests as they are. The design carries to **~1,000** by chunking (≈ 20 requests per post at 2 devices each) plus a background queue; beyond that, a different distribution (a relay or a server-side fan-out of ciphertext) would be needed and is out of scope. **The product decision:** is 100 enough for teachers' first jams? (A teacher with a following larger than that is the case to watch.)

## 5. Responses (Phase 1 e)

- **♥ likes (LIME-189, built):** a signed `jam.react { post_id, on }` sent **only to the writer** (Olm), accepted from a **current subscriber** (who may read the post) or the writer. The writer's phone keeps `jam_reactions (post_id, user, at)`, idempotent; "off" removes. The subscriber's own heart shows at once (`jam_my_reactions`). **Counts are public to everyone who can read the post**: the writer's phone sends `jam.counts { post_id, version, likes, comments, remixes: 0, likers[] }` in the post's own session, **coalesced to at most one a minute per post** through the paced queue; a subscriber keeps the newest by `version`. No rankings. The app shows the count and only the faces of the reader's own contacts among `likers`; the writer sees everyone.
- **Private reply to the writer:** opens an ordinary 1:1 chat with the writer (`dm:`), quoting the post. Existing code.
- **Comments all subscribers see: two options.**
  - **E1: every commenter is a Megolm sender to all subscribers** (as in a group). Each commenter device needs its own outbound session shared with every subscriber device: at 100 subscribers that is up to 100 sessions × 100 devices of key distribution, and every subscriber learns every commenter's device; quadratic growth makes it unworkable beyond ~100.
  - **E2 (recommended): comments go to the writer, who republishes them.** A comment is a signed op the commenter sends to the writer (Olm); the writer's phone checks the author is a subscriber and republishes it inside the jam's session as `jam.comment { author, text, post_id, author_sig }`, so subscribers can verify it is the author's own words and not the writer's invention. Cost: one session (the writer's), nothing quadratic. Trade-off: **comments appear only while the writer's phone is online**, and the writer can drop a comment (a moderation tool, but also a power).
  
  Recommended for v1: E2, with the limit stated in the UI ("comments appear when the writer's phone is next online").

  **E2 as built (LIME-189).** A comment is `jam.comment { post_id, comment_id, parent_id?, author, text }`, **signed by the author's device** (so it carries the author's own signature), sent to the writer (Olm; the op id is the comment id). The writer's phone checks the sender is a current subscriber who may read the post, the post exists and is not deleted, the text is 1 to 2,000 characters, the author named is the sender, the comment is new, and **at most 20 a minute per author**; **one level of replies**: a parent that is not a comment of that post is refused, and a reply to a reply is attached to its top-level parent. It then **republishes** it in the post's session as `jam.comment.published { post_id, comment }` where `comment` is the **author's own signed op with the author's device certificate**. A subscriber verifies the certificate (the master key signed the device), the signature, that it is a `jam.comment` of this very jam and post, and, if it knows the author, that the master key is the one pinned for them; so the writer cannot put words in someone's mouth. (A subscriber who does not know the author takes the writer's word for who they are, which is all they could have anyway.) The commenter's own comment shows at once as **pending** and becomes published when it comes back. **Delete:** the author sends `jam.comment.delete { comment_id }` (Olm) and the writer can remove any comment on their posts; either way the writer's phone republishes `jam.comment.removed { post_id, comment_id }`; removing a top-level comment removes its replies. A comment on a co-authored post still goes to the post's writer. New comments mark the post **unseen** on the writer's phone (local; the app's badge, no push by default). **A deleted post (LIME-195)** drops its hearts, comments and counts on every phone.

## 6. Removal and report (Phase 1 g)

- **Remove a subscriber:** the writer's phone sets `removed_at`, rotates the session (§3) and does not send the new key to them; they keep what they already had (as with groups: a delete or a removal cannot unsee).
- **Report a post or comment** (App Store rule 1.2 for user content; LIME-113's Report path): the **reporter's phone** forwards the reported item, which it can already read, with its sender signature, the jam id and the writer's id, to the abuse contact (a user-initiated disclosure; end-to-end encryption is intact for everyone else). The platform's powers are: take the **jam page** down (§7), refuse to serve the post blobs (the ciphertext, so the content is gone for new fetchers and for the archive), and ban the account. It cannot reach into subscribers' phones. This needs the Report path (LIME-113) to accept a jam item; no new mechanism.
- **Unsubscribe:** the subscriber's phone sends nothing the server can see beyond a `jam.unsubscribe` to the writer; it keeps its archive (or deletes it locally).

## 7. The jam page, and discovery (Phase 1 f, brief item i)

A non-subscriber must see *something* to decide to subscribe. **Plot's lean, evaluated:** a **jam page** is the **only public, server-readable part**: name, about, topics (subject, grade, tags), the post titles the writer chooses to show, and the post count. **Posts, including free ones, stay encrypted: reading any post needs a (free) subscription, one tap.**

| | Option 1 (recommended): page public, all posts encrypted | Option 2: free posts readable by any signed-in teacher |
|---|---|---|
| Server | reads the page (as it reads a profile today: name, school, about) | reads every free post (plain), so it can be compelled, scanned, leaked |
| Writer | chooses what the page shows | cannot take back a free post |
| Subscribers | learn nothing about each other | same |
| Non-subscribers | see the page, not the posts | see free posts with no relationship |
| Moderation | takedown of a page; posts are ciphertext | takedown of readable content, easier |
| Fit with J1 | **keeps J1** | breaks J1 for free posts |

**Recommendation: Option 1. (Amended by LIME-210, section 13: Option 1 stays the default for every post; a writer may now choose "Everyone on lime" for a post, which is a deliberate, per-post exception.)** It is also the minimum new server metadata a **Subscribe** button needs: a `jams` table (jam id, writer id, title, about, topics, post count, created) readable by signed-in users, the same trust class as `profiles` (api-v2 §11, "Profiles"). A directory search over it (by subject, grade, topic, name) is a server query; it learns *what* is searched, as the user directory does today. "Teachers I know" is local (the contacts and groups already on the phone).

**Subscribing reveals to the server** that *this account contacted that writer* (a message to a writer you may not have chatted with, an identified first send: the existing "stranger's first message" limit, api-v2 §9). **Downloading does not reveal the account** (LIME-187): a post is fetched by its unguessable id from `jam-blob-get`, which needs **no session and no token**, so the server sees the request's network address, the time and the blob id, and **no account**. It can still guess that addresses that fetch the same jam's blobs belong together, and an address behind a school's network says little. The bucket the function limits by is the address alone (never the blob id), and the function writes no log line of its own. **What the hosting platform itself logs is not ours to switch off:** its Edge Function request log records the call (path, status, time and the client address in the request headers, not the JSON body, so not the blob id), and its **Storage request log records the signed download itself, whose path is the blob id, with the address.** So for the platform's log retention the platform can tie an address to a blob id. To be confirmed against the staging project's log settings before launch. Further mitigation to weigh later: fetch blobs through the LIME-139 relay path.

## 8. What each party learns (v1, option C + E2 + Option 1; extended by LIME-210 in section 13.10)

| Party | Learns |
|---|---|
| **The server** | The jam page (public by design: title, about, topics, **the subscriber count the writer's phone publishes**, post count). That blobs exist, with their sizes and times, **and which network addresses fetch which blob ids, but not which accounts** (the fetch carries no session). The writer's uploads (account, time, size). The recipient sets of each notice send (the existing limit, api-v2 §9). Timing and IP addresses. **Never**: post, comment or ♥ content; titles; who liked or commented. |
| **The writer** | Everything about their jam: who subscribed (and when), every ♥, every comment, who removed. |
| **Subscribers** | The posts (all of the archive), the comments the writer republished with their authors, **the counts and (LIME-189) the list of who liked each post** (it rides in the tally to every subscriber's phone; the app shows only the reader's own contacts' faces, but the list is on the phone). Not who the other subscribers are. |
| **Non-subscribers** | The jam page only. |
| **A removed subscriber** | What they already received. Nothing after the rotation. |

## 9. Payments, later (brief item j)

No payment code in v1; the model has `tier` and `tiers` so it can arrive without a migration of posts. **Rules to design for:** Apple requires In-App Purchase for digital subscriptions in an app (Patreon was moved to IAP by 2026-11-01: 30%, 15% after the first year / small business program); US apps may link out to a web checkout after the Epic ruling (the allowed commission is still being set after the December 2025 appeal). **Options for a 0% lime cut, for a later decision:** (1) US: a "pay on the web" link to the writer's own processor (Stripe, etc.), no IAP; (2) elsewhere: IAP, with the platform's cut visible to the writer; (3) tips as one-time purchases. Whichever, **the paid-ness is enforced by the writer's phone handing out keys** (a paid subscriber gets the `subscribers` posts' keys); the server never decides who may read. Every jam still has free posts.

## 10. Honest limits and open questions

- 100 subscribers in v1 (§4). Comments need the writer online (§5). A subscriber's device that misses a rotation misses those posts until the writer next sends the key (same as groups).
- The server **holds** a ciphertext archive (new retention; stated in `architecture.md`); a jam that ends, or a post the writer deletes, has its blobs removed (`jam-page` end).
- **Key distribution is the slow part of a big jam.** Every rotation and every new subscriber costs an Olm message per device, which the server limits (60 key claims and 120 items a minute): a 1,000-subscriber jam takes about 17 minutes to key everyone, though a *post* takes about two. A cheaper rotation by age or count would hand the next session's key *inside* the current session (a key chain), reserving the individual Olm messages for a removal; not built.
- Student privacy: lime cannot see classroom clips; the writer is responsible. A one-time notice at the first clip upload ("Don't share students' faces or names without permission") is a copy decision, not a technical one.
- Who may create a jam (any signed-in teacher? after some verification?) is undecided; spam and impersonation (a fake "famous teacher" jam) need the Report path and a verified-name policy.
- Shared jams (school/district) change §2's `writers`, §5's comment path and the page's ownership; not v1.

## 11. Proposed split into build briefs (for plot to draft; LIME-186+)

*Built so far: 186 (core), 187 (server), 188 (the jam tab: start a jam, write posts with photos and files, subscribe from a profile, read, the writer's subscriber list). A post's files are jam-class blobs of their own, downloaded when shown, with no session; v1 has no tier picker (every post is free).*

1. **Core (186):** conversation kind `jam:`; `jam.*` ops and state; the writer's session store (first-index keys), rotation on removal / 100 / 7 days; `jam.subscribe` / `welcome` / `post` / `session` / `remove`; tests in the fake server. (No UI.)
2. **Server (187), only if option C:** a `jams` page table and RLS; a long-retention blob class with quota and deletion on `jam.end`; rate limits; `docs/api-v2.md` + `architecture.md`.
3. **iOS write and read (188):** a Jam tab: your jam (create, write a post with the existing composer + attachments, free/subscribers), subscriptions list, post reader, the archive.
4. **Responses (189):** ♥ to the writer, private reply, comments (E2) with the "when the writer is online" copy.
5. **Page and discovery (190):** the jam page, Subscribe, directory search by subject / grade / topic, "teachers I know".
6. **Report and moderation (191):** Report on a jam item (LIME-113's path), takedown tooling.
7. **Later:** payments (§9), shared jams, notifications settings per jam (off by default).

## 12. The decisions this needs from the user

1. **Archive:** C (blobs + welcome), as recommended, accepting the new server retention? (Or A, no server change but the writer must be online.)
2. **Subscriber limit** in v1: 100 (the group code as is) or build chunking for ~1,000?
3. **Comments:** E2 (the writer republishes; appear when the writer is online)?
4. **Page vs posts:** Option 1 (public page, encrypted posts)?
5. **Who may create a jam** in v1, and the Report/takedown policy before TestFlight.

## Freewall (LIME-188n, marker only) and what is planned
A post may carry one `[[freewall]]` line (docs/message-format.md). In v1 every reader is a subscriber and sees the whole post, with a quiet "Subscribers' part starts here" rule at the marker; **nothing new goes to the server**. **Planned (LIME-190, now designed in section 13 as LIME-210's Preview):** a non-subscriber who opens a post in discovery would see only what stands above the marker. That needs the free part to be readable without the subscribers' session; **what each party will learn then** (the server would hold the open part, or a second blob for it, and so learn that a post has a free part, its size and its time, and who fetched it by network address, as for any jam blob) must be decided in that brief before it is built.

## Captions (LIME-188o)
A video or recording may carry captions, made **on the writer's phone** with Apple's speech recognition **on the device only** (`requiresOnDeviceRecognition`; if the phone cannot recognise that language by itself there are no captions, never the server recogniser). They are a WebVTT file (`core/src/captions.rs`: at most 256 KB and 6,000 cues) that travels as **one more attachment of the post**, `text/vtt` named `captions-<n>.vtt` for the post's n-th attachment, inside the same encrypted blob. **What each party learns:** the server nothing new (one more blob of a small size, like any attachment); subscribers get the captions with the post; Apple nothing (on-device only). The writer reads and corrects the lines before posting, or turns them off for the post. Recordings over five minutes get no captions in this version; posting waits up to ten seconds for captions still being made and then goes without them (a later follow-up message, like `jam.credit`, could add them afterwards).

## Posting as the jam (LIME-188q)
A post can say it is shown as the **jam's** (`display_as: "jam"` in the encrypted post payload; the default and anything else is `person`): its card and page then show the jam's name as the author line with "by <writer>" under it, as a publication does. It is part of the post blob (a migration adds the column on the phone), so **nothing new goes to the server, and what each party learns is unchanged**. A school or subject group as the author comes with LIME-193.

## 13. Public and private posts, the Preview, series and communities (LIME-210, design only)

**Decided (DESIGN-16, the user, 2026-10-24).** A post's audience is **Subscribers** (the default: end-to-end encrypted, as built) or **Everyone on lime** (open, signed by the writer, readable by lime's server). A `[[freewall]]` makes the part above it a public **Preview** and the rest for subscribers. **Contacts follow each other's jams automatically** (free; unsubscribing sticks). **Series** of articles, videos and podcasts. A **community chat** subscribers can join. **All before TestFlight 1.** Subscribing is always free.

**What this contradicts, stated plainly.** (1) §7 and J1 ("all teachers' posts stay encrypted; reading any post needs a free subscription") become "**by default**": an open post is an explicit, per-post choice that makes that post readable by the server, the same exception `docs/orgs-and-channels.md` §2 made for lime's own posts, now open to every writer. (2) The Freewall section's "planned LIME-190" is this design (the Preview). (3) §5/189 accept hearts and comments only from current subscribers: unchanged (13.5). (4) The word **tier** already means `free | subscribers` on a post (a future paid tier, §7 end). **Audience is a new, separate field** (`subscribers | everyone`); do not reuse `tier` (a free-tier post is still encrypted: it is free for *subscribers*). (5) A jam holds 1,000 subscribers (§4): automatic contact follows (13.6) spend that budget; a writer with more than 1,000 contacts is not realistic in v1, and a full jam answers `refused: full` to an automatic follow quietly.

### 13.1 Audiences

- **The composer's chip** (beside "Post as", article and quick post and recording): **Subscribers** (default) or **Everyone on lime**. Choosing Everyone shows once per post, before Post: *"Everyone on lime can read this, and so can lime's server."* with **Post to everyone** / **Keep it for subscribers**. A post with a freewall shows the chip as "Everyone (the part above the line) and Subscribers (the rest)" and asks the same question about the top part.
- **Changing it later (Edit, LIME-195).** *Subscribers → Everyone* publishes a **new open copy** of the post (same post id; the encrypted original stays for subscribers). *Everyone → Subscribers* **deletes the open copy** from the server (row and public files) and tells nobody; the copy says plainly: **"People may already have read, saved or copied it."** Deleting the post deletes both copies.
- **On the card:** an Everyone post shows a small **globe** beside the date and, for a reader who is not a subscriber, the card is the same card with the globe and a quiet "Subscribe" in ⋯; a subscribers-only post shows nothing (the default needs no mark); a post with a Preview shows a **lock and "Preview"** to non-subscribers (13.4).
- **For plot / the user:** whether Everyone can be the *default* for a new jam's first post (recommend: no, the default is always Subscribers).

### 13.2 Open posts for teachers: one store

**Recommendation: one store**, generalising 193b's `org_posts` into **`open_posts`** (`post_id`, `author_kind` (`person` | `org`), `author_id` (user id or org id), `jam_id`, `kind`, `title`, `subtitle`, `markdown`, `attachments[]` as public blob ids, `topics[]`, `series?`, `preview_of?` (13.4), `important?` (lime only, 193b), `version`, `created`, `edited_at`, `deleted_at`, `signature`, `signer_cert`). One reader, one cache, one cursor feed, one takedown path; two tables would duplicate Discover and the report path. lime's own posts are rows with `author_kind = org`; they are signed under the org certificate chain to lime's pinned root (193 §1/§2); a teacher's are signed by **the writer's device**, with the **device certificate** (the master key signs the device keys: `protocol/mod.rs` `SenderCert`), and a phone accepts a row only if the signature verifies, the certificate verifies, and (when it knows the writer) the certificate's master key is the one pinned for them; otherwise the server's check at publish (the signed-in account's own master key) is the writer's voucher, as for a stranger's comment (13.5 / 189). **Public file class:** a new `open` class beside `jam` (`blob` function, 193b's "public blob class"): unencrypted, no expiry while the post exists, a plain cacheable URL, deleted with the post (the jam class's deletion path, 195).
- **Edit and delete:** an edit is a new `version` of the same `post_id` (signed again; readers replace in place; the old files are removed); a delete sets `deleted_at` and removes the public files (the row stays as a tombstone so a phone with an older cursor learns of it).
- **Per-writer limits (configuration, starting values for plot):** 20 open posts a day, 100 open files a day, 24 MiB a file (as jam), an **open storage quota separate from the jam class** (500 MiB a writer), rate-limited like other writes (`api-v2` §rate limits). An unverified new account may publish at most 3 open posts a day for its first week (spam brake; for plot).
- **What the server stores and can be asked for:** the full text and files of every open post (that is the choice the writer made), who wrote it and when, versions, and takedown records; it **can** be compelled to produce them and can read them; it still cannot read any subscribers-only post, comment or reaction.

### 13.3 Discover

A new member's **Discover** is the open feed: **public posts from everyone, newest first, no rankings** (§1b), with **lime's own posts in a "From lime" section above** (193b). **Recommendation: a signed-in cursor list for the index, sessionless fetch for the files.**
- `GET open-feed?since=<cursor>&limit=50` returns post **metadata and the signed row** (the whole row for a short post; the markdown can be large, so the list returns title, subtitle, a 240-character excerpt, topics, author, counts of files and the file ids; the page fetches the full signed row by id). Signed-in because the server then rate-limits abuse per account and nobody scrapes the whole corpus anonymously; it learns "this account opened Discover", which every member does (no signal), the same argument as 193b's feed.
- **Filters by subject, grade or topic are done on the phone** over the pages it fetched (the topics are in each post's metadata), so **the server never learns what a person is interested in**. (A server-side search by topic would make it learn the query, as the directory search does; cheap to add later; not recommended for v1.) The file URLs are plain and cacheable (no session), so the server sees an address fetching a public file, the same as any public web page.
- **For plot:** a topic and grade picker at publish time (the jam's topics are the default).

### 13.4 The Preview

A post with a `[[freewall]]` (docs/message-format.md, 188n) is, in the audience model, **always "Everyone" for its top part**: an **open row** `open_posts` with `preview_of = <post_id>` and `has_rest = true` carrying the markdown **above the marker** and only the files that stand above it; and the **encrypted full post** exactly as today (jam blob + notice to subscribers), linked by the same `post_id`. A subscriber's phone already has the whole post, so the open row is for people who are not subscribers.
- **A non-subscriber's card** shows the title, the top excerpt, the **lock and "Preview"**; **the page** shows the open part and, at the cut, a quiet rule and **"Subscribe to read the rest"** (and, if the jam has a community, "Join <writer>'s community" after subscribing, 13.8). Subscribing is the ordinary free `jam.subscribe`; the welcome's index then delivers the full post (and the open copy on their phone is replaced by the whole). Nothing new is sent when they subscribe.
- **Editing** the part above the marker re-signs the open row (a new version); moving the marker changes what is public (the copy at the choice names this). Removing the marker removes the open row (the post is then subscribers-only; same copy as 13.1).

### 13.5 Responses on public posts

**Options:** (a) only subscribers respond: a non-subscriber taps ♥ or Comment and sees **"Subscribe to like and comment"** (one tap, free); (b) anyone signed in responds through the writer's phone (189's path widened: the writer's phone would accept ♥ and comments from non-subscribers, and publish them to subscribers only, so a non-subscriber's comment is not shown to other non-subscribers); (c) open responses stored on the server (the first server-readable teacher comments; needs moderation: wait for 191 and beyond). **Recommendation: (a) for v1.** It keeps 189 as built (current subscribers only, comments end-to-end encrypted through the writer), keeps comments out of the server, and the prompt doubles as the subscribe call to action. (b) is a small later widening if it is wanted (a per-writer limit would be needed); (c) is not before reporting and moderation are mature. **Counts are not shown to non-subscribers** (the tally goes to subscribers, §5), so an open card shows no ♥ n for them. **For the user:** is that enough, or should the open card show a public ♥ count (that would need the open store to hold counts: not recommended in v1)?

### 13.6 Contacts follow each other's jams

When a 1:1 chat is **accepted**, each phone subscribes to the other's jam if there is one, **quietly, free**: the same `jam.subscribe` (Olm, to the writer), no prompt. When a contact **starts** a jam later, the phone notices it the way a profile does (the `jam-page` lookup the profile view already makes, which reports a jam if the person has one) and subscribes. **Unsubscribing sticks:** the phone keeps `jam_follow_off(jam_id)`, set whenever the person unsubscribes by hand, and never auto-subscribes that jam again (also if the contact is re-added); a writer's own **Remove** also sticks on the writer's side (`removed`, §6). **Existing contacts at upgrade:** one pass subscribes them once, paced (at most 20 lookups and 20 subscribes a minute, resuming) so the server's key-claim and item limits (§10) are respected; a jam that is `full` or `ended` is skipped. **What the server learns:** a `jam.subscribe` is an Olm op between two people who already chat (it sees the same sealed envelope as any message); the **`jam-page` lookups** name the writer (the server already learns that an account looked at a profile): for a contact that is ordinary. At upgrade, the lookups come in a paced run (an account looking at its contacts' pages), which reveals nothing the contact list itself did not (the server holds no contact list, but the chats themselves are already sealed-sender traffic); to avoid even that burst, **the profile fetch carries `has_jam`** (for plot: already fetched when a contact's profile is stored, so no extra request).

### 13.7 Series

**Recommendation: a field in the post, no separate record:** `series { id, title, part, of? }` in the post payload (and in the open row's metadata): `id` is a UUID the writer's phone makes on the first part, `title` repeats in every part, `part` is the number, `of` is optional ("Part 2 of 6" when set, "Part 2" when not). **The series page is assembled on each phone** from the posts it has (the archive for subscribers; open rows for everyone): the parts in order, locked parts shown as "Subscribers" with the Preview if any, **progress kept on the phone** (which parts are read or played; local, never sent). Articles, videos and podcasts can be parts of one series. Each part keeps **its own audience and Preview**, so a series can open with a public first part. **Adding and reordering:** Edit (195) gains a series picker ("Add to series… / New series… / Remove from series") and the part number (the writer renumbers by editing `part`; no bulk reorder UI in v1). Its cost is one small JSON field; **a signed series record** (so a series could span several writers' posts, or carry its own cover and description) is the alternative, deferred to shared jams (193d) and to the series cover picture (194). **What each party learns:** subscribers and open readers see the series field they can already read in the posts; the server learns series titles only for open posts.

### 13.8 The community chat

A **community** is a **group (`grp:`) linked to the jam**: the jam's state (`jam.update`, to subscribers) carries `community: <group_id>?`, and the public page carries only the boolean **`has_community`** (so the Preview can say "Join <writer>'s community" without naming the group). **Joining without the writer approving each one:** the subscriber's phone sends `jam.community.join` (Olm, signed) to the writer's phone; the writer's phone checks the sender is an **active subscriber** and runs **today's group add** (the existing group invite path with the member added by an admin op) **automatically**; it only needs the writer's phone online (as comments do, §5; the app says "You will be added when <writer>'s phone is next online"). **Leaving:** the ordinary group leave; **removing a subscriber** (§6) also removes them from the community (the writer's phone does both). **Cap:** `protocol/group.rs` allows 100 members (`MAX_MEMBERS`), a jam allows 1,000 subscribers: the community takes the **first 100 joiners**, then answers "The community is full"; for bigger audiences the **announcement channel** mode (193c: admin-only posting, members react or reply per the three settings, no roster shown) is the answer and is the same group with its `announce` flag. **193c link:** the writer chooses at creation **Community** (everyone chats, up to 100) or **Channel** (the writer posts; reactions, comments and replies each on or off, 193c). **What the server learns:** the existing group rules and nothing more (group traffic is sealed; the server does not hold the roster); the one new public bit is `has_community`.

### 13.9 Safety first (required before an Everyone post can be published)

**Report and takedown (LIME-191) and the student-privacy check ship before the "Everyone on lime" option is switchable on** (a server flag, `open_posts_enabled`, off until then; the chip is hidden, not disabled). **The student-privacy check** at the choice: (1) the one-time notice: *"Don't share students' faces, names or voices without permission."*; (2) **a required confirmation per open post** ("I have permission to share any students who appear or are heard"); (3) on-device help: **face detection on a photo or a video's poster** (Vision, on the phone, nothing sent) warns "This photo has faces" before Post, since a classroom photo is the likeliest breach; audio and video cannot be checked reliably and rely on the confirmation. **Report** is on every open post for every reader (191); **takedown of an open post:** a lime operator marks the row `taken_down`, the server removes the row's public files and serves a tombstone; **copies already fetched by phones remain** (stated in the writer's copy and the report outcome); the writer's encrypted original is untouched (it is not readable by lime) and the writer is told. Repeat takedowns can end a writer's right to publish open posts (a flag on the account), never a power over subscribers-only content.

### 13.10 What each party learns (new rows; §8's table is extended)

| Party | Learns, with public posts, Previews, Discover, auto-follow, series and communities |
|---|---|
| **The server** | **Open posts and their files in full, who wrote them, versions and takedowns** (a deliberate choice per post); that an account opened Discover (every member does); an address fetching a public file; `has_jam`/`has_community` on the page; series titles of open posts. **Still not:** any subscribers-only post, comment, reaction, series of a private post, community roster or messages, who is auto-followed (an Olm op between contacts), or what a person filters Discover by (filters are on the phone). |
| **The writer** | As before, plus who joined the community (they add them) and that contacts auto-followed (they are subscribers). |
| **Subscribers** | As before (the posts, counts and **who liked**, §8 above), plus the series and the community's members as a group shows them. |
| **A non-subscriber** | Open posts, Previews and the open feed; **nothing** of the encrypted rest, the comments or the counts. |
| **A contact** | That I follow their jam (they see me as a subscriber, as any subscriber). |
| **Anyone who fetches a public file** | The file; (the server sees their address). |

### 13.11 The build split (for plot; estimates in working days)

1. **LIME-191 Report and takedown** (first; M, 3 d): the report path for open posts and the operator tool; the `open_posts_enabled` flag stays off until 4 and 8 are done.
2. **210a Server: `open_posts` and the `open` file class** (M, 3 d): table (the generalised `org_posts`), functions (publish with signature and certificate check, edit, delete, list by cursor, fetch by id, takedown), per-writer limits, tests with the fake server. Supersedes 193b's table shape (193b's lime posts become `author_kind = org` rows).
3. **210b Core: audience, signed open rows, Preview, series field** (L, 5 d): the `audience`/`series`/`preview_of` fields in the post payload and the open row, sealing and verifying signed rows, the Preview split at the freewall, changing audience in Edit, open delete, tests for chains and tampering.
4. **210c App: the audience chip and copy, the globe, Discover** (L, 5 d): composer and Edit, the card and page for open posts, the Preview card/page and "Subscribe to read the rest", the Discover feed with phone-side filters.
5. **210d Safety: student-privacy check** (S, 2 d): the notice, the per-post confirmation, the on-device face warning; then switch `open_posts_enabled` on.
6. **210e Contacts follow automatically** (M, 3 d): core (`jam_follow_off`, accepted-chat hook, paced upgrade pass, `has_jam` in the profile fetch) and the quiet UI.
7. **210f Series** (M, 3 d): the picker in compose and Edit, the series page and local progress.
8. **210g Community chat** (M, 4 d): `jam.update`'s `community`, `jam.community.join`, the writer's automatic add and removal, the public `has_community`, the app's Join, the Community/Channel choice (with 193c).
**Order:** 191 → 210a → 210b → 210c → 210d → 210e → 210f → 210g (everything before TestFlight 1, per the decision; the Everyone option goes live only after 191 and 210d).

## Writing an article together (LIME-233)

Co-authors can write an article together in the editor, like Google Docs: a shared draft with each other's cursors, instant and encrypted, and only the writer (the jam's owner) publishes. Posts and their sealing are unchanged. See `docs/coedit.md` (the design as built, what each party learns, limits and Android notes) and `docs/api-v2.md` section 16 (the `draft.*` ops).
