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

- **♥ likes:** a signed `jam.react` sent **only to the writer** (Olm). The writer's phone keeps the count and the list. *Superseded by the 2026-10-21 decision (section 1b): counts are public, so the writer's phone publishes the count with the post's page entry or re-shares it to subscribers; to be designed in LIME-189.*
- **Private reply to the writer:** opens an ordinary 1:1 chat with the writer (`dm:`), quoting the post. Existing code.
- **Comments all subscribers see: two options.**
  - **E1: every commenter is a Megolm sender to all subscribers** (as in a group). Each commenter device needs its own outbound session shared with every subscriber device: at 100 subscribers that is up to 100 sessions × 100 devices of key distribution, and every subscriber learns every commenter's device; quadratic growth makes it unworkable beyond ~100.
  - **E2 (recommended): comments go to the writer, who republishes them.** A comment is a signed op the commenter sends to the writer (Olm); the writer's phone checks the author is a subscriber and republishes it inside the jam's session as `jam.comment { author, text, post_id, author_sig }`, so subscribers can verify it is the author's own words and not the writer's invention. Cost: one session (the writer's), nothing quadratic. Trade-off: **comments appear only while the writer's phone is online**, and the writer can drop a comment (a moderation tool, but also a power).
  
  Recommended for v1: E2, with the limit stated in the UI ("comments appear when the writer's phone is next online").

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

**Recommendation: Option 1.** It is also the minimum new server metadata a **Subscribe** button needs: a `jams` table (jam id, writer id, title, about, topics, post count, created) readable by signed-in users, the same trust class as `profiles` (api-v2 §11, "Profiles"). A directory search over it (by subject, grade, topic, name) is a server query; it learns *what* is searched, as the user directory does today. "Teachers I know" is local (the contacts and groups already on the phone).

**Subscribing reveals to the server** that *this account contacted that writer* (a message to a writer you may not have chatted with, an identified first send: the existing "stranger's first message" limit, api-v2 §9). **Downloading does not reveal the account** (LIME-187): a post is fetched by its unguessable id from `jam-blob-get`, which needs **no session and no token**, so the server sees the request's network address, the time and the blob id, and **no account**. It can still guess that addresses that fetch the same jam's blobs belong together, and an address behind a school's network says little. The bucket the function limits by is the address alone (never the blob id), and the function writes no log line of its own. **What the hosting platform itself logs is not ours to switch off:** its Edge Function request log records the call (path, status, time and the client address in the request headers, not the JSON body, so not the blob id), and its **Storage request log records the signed download itself, whose path is the blob id, with the address.** So for the platform's log retention the platform can tie an address to a blob id. To be confirmed against the staging project's log settings before launch. Further mitigation to weigh later: fetch blobs through the LIME-139 relay path.

## 8. What each party learns (v1, option C + E2 + Option 1)

| Party | Learns |
|---|---|
| **The server** | The jam page (public by design: title, about, topics, **the subscriber count the writer's phone publishes**, post count). That blobs exist, with their sizes and times, **and which network addresses fetch which blob ids, but not which accounts** (the fetch carries no session). The writer's uploads (account, time, size). The recipient sets of each notice send (the existing limit, api-v2 §9). Timing and IP addresses. **Never**: post, comment or ♥ content; titles; who liked or commented. |
| **The writer** | Everything about their jam: who subscribed (and when), every ♥, every comment, who removed. |
| **Subscribers** | The posts (all of the archive), the comments the writer republished with their authors. Not who the other subscribers are, not who ♥'d, not how many. |
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
A post may carry one `[[freewall]]` line (docs/message-format.md). In v1 every reader is a subscriber and sees the whole post, with a quiet "Subscribers' part starts here" rule at the marker; **nothing new goes to the server**. **Planned (LIME-190):** a non-subscriber who opens a post in discovery would see only what stands above the marker. That needs the free part to be readable without the subscribers' session; **what each party will learn then** (the server would hold the open part, or a second blob for it, and so learn that a post has a free part, its size and its time, and who fetched it by network address, as for any jam blob) must be decided in that brief before it is built.

## Captions (LIME-188o)
A video or recording may carry captions, made **on the writer's phone** with Apple's speech recognition **on the device only** (`requiresOnDeviceRecognition`; if the phone cannot recognise that language by itself there are no captions, never the server recogniser). They are a WebVTT file (`core/src/captions.rs`: at most 256 KB and 6,000 cues) that travels as **one more attachment of the post**, `text/vtt` named `captions-<n>.vtt` for the post's n-th attachment, inside the same encrypted blob. **What each party learns:** the server nothing new (one more blob of a small size, like any attachment); subscribers get the captions with the post; Apple nothing (on-device only). The writer reads and corrects the lines before posting, or turns them off for the post. Recordings over five minutes get no captions in this version; posting waits up to ten seconds for captions still being made and then goes without them (a later follow-up message, like `jam.credit`, could add them afterwards).

## Posting as the jam (LIME-188q)
A post can say it is shown as the **jam's** (`display_as: "jam"` in the encrypted post payload; the default and anything else is `person`): its card and page then show the jam's name as the author line with "by <writer>" under it, as a publication does. It is part of the post blob (a migration adds the column on the phone), so **nothing new goes to the server, and what each party learns is unchanged**. A school or subject group as the author comes with LIME-193.
