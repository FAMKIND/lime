# Writing an article together (LIME-233, DESIGN-20, DESIGN-22): the design as built

**Status: built (LIME-233a to 233e, 2026-10-26), behind the app flag `coedit`** (on in Debug builds, off in Release until switched on). This replaces the first design draft; where that draft and DESIGN-22 differed, DESIGN-22 won, and where the build differed from DESIGN-22 the difference is listed in section 12.

The aim: teachers write a curriculum or lesson plan together, like Google Docs. Co-authors open the same article draft, see each other's coloured cursors with a photo and first name, and each other's keystrokes appear **instantly** ("in an emergency two seconds can be life or death"), all end-to-end encrypted. Only the writer (the jam's owner) publishes.

## 1. The document

A draft is an **Automerge** document (Rust crate `automerge =0.12.0`, in LimeCore, so Android gets it through UniFFI). Shape:

```
root { title: Text, subtitle: Text, cover: str, blocks: List<Map> }
block { id, kind, level, ordered, number, attachment, caption, url, colour, list_start, text: Text with marks }
```

Kinds: `paragraph`, `h1` to `h6`, `quote`, `indent`, `item` (list item with level and numbered flag), `code`, `image` (a file by number), `button`, `divider`, `freewall`. Marks: bold, italic, underline, strike, code, link, mention. Positions are Unicode characters (the app converts from UTF-16). It imports from and exports to the **same post Markdown** the editor makes today (`format::parse_post` / `serialize_post`), so **publishing is unchanged**.

- **Persistence:** SQLCipher tables `drafts` (snapshot, post link, sync state) and `draft_chunks` (incremental saves); compaction to one snapshot after 200 changes.
- **Merging:** two documents merge only if one began as a copy of the other, so a late joiner is given a **snapshot**, never a fresh document.
- **The editor feeds the draft by reconcile** (`DraftDoc::reconcile`, call `draft_reconcile`): the editor still works on its own attributed text; after each change (120 ms debounce) its Markdown is compared with the draft and the **fewest operations** are applied (unchanged blocks untouched; a changed block gets only the differing characters and style runs). One typed letter is about 100 bytes, so another author's edit to the same paragraph **merges** instead of being replaced. Remote changes come back as patches; the editor redraws from the draft and relocates the caret by the characters around it (`CaretAnchor`), keeping focus.
- **Limits:** about 200 KB of text and 2,000 blocks per draft, 5 authors, 10 files.

## 2. Two paths for one draft

**(a) Instant.** A **public Supabase Realtime broadcast channel**, one per draft: topic `realtime:draft:<channel id>` (a random 128-bit id, 32 hex characters), joined with the **public API key only and no user token** (`private: false`, `self: false`), so the server cannot tie the channel to an account. Each message is `nonce(12) || AES-256-GCM` of a signed inner message, under a key derived from the draft key (`HKDF-SHA256(draft_key, "lime-draft-instant-v1")`) with the channel id as associated data. The inner message is the usual signed sealed-sender envelope: an op of type `draft.live` signed by the author's **device key**, with the device certificate chained to the author's pinned master key. A receiver drops anything that: does not decrypt, is not signed by a current active author's device (cert chain to the pinned key), is from itself, or names another draft. Nothing is stored by the relay. Payloads: `k:"c"` (Automerge changes since the last instant send) and `k:"p"` (presence). Reconnect with backoff; typical delay 1 to 20 ms on the stack tested (21 ms to the hosted staging project; the test asserts under 500 ms).

**(b) Durable.** The same changes go to each other author as **pairwise sealed control ops** through the ordinary mailbox, with 232's save-before-send outbox (`draft_outbox`): `draft.change {bytes}` batched **at most once per 5 s per draft** while typing (so at most 12 sends a minute per author per draft, well under the server's limit), and `draft.hello {heads}` every 60 s and on opening (the receiver sends back what the other lacks, so offline authors, late joiners and dropped sockets converge). **A deliberate difference from DESIGN-22's "draft group":** with at most 5 authors, pairwise Olm sealing reuses the best-tested path and avoids a new Megolm group per draft; it costs up to 4 sends per batch, still inside the limit.

## 3. Authors, keys, removal

- **Invite** (`share_draft`): the writer adds accepted contacts (up to 4 besides themselves). Each gets `draft.invite {draft_id, channel_id, key, writer, authors, snapshot}` sealed to them: the channel, the key and the whole draft. In the app, picking a co-author in the editor's person-plus picker sends it at once; the invitee sees **"Shem invited you to write <title>"** in Activity (own profile) and **Open draft** on the post's ⋯, and opening it marks the invitation seen. (The publish-time credit request of LIME-188f is separate and unchanged.)
- **Removal** (`remove_draft_author`): the writer takes someone out; the key changes and the others get it (`draft.key`); the removed phone gets `draft.removed`, drops the key and its outbox, and anything it sends later fails to verify. **Leave** (`leave_draft`) says `draft.leave`.
- `draft.authors` tells existing authors about a new one.

## 4. Presence: what you see

Sent over the instant path, never stored. My place is a **block id plus a character offset** (and an end for a selection), not an editor position (those differ between phones). At most ten sends a second, on every move and change; a **10 s heartbeat**; **away** when the editor closes.

In the editor: an **authors' row** at the top (a dot in the author's colour on whoever was heard in the last 25 s), **"Jean is editing..."** while someone typed in the last 5 s (VoiceOver: "Jean is editing the third paragraph"), and in the page each other author's **caret in their colour with a small tag (photo or initial, first name)** above it; the tag **fades to just the caret after 3 s without a move** and returns when they move; their **selection is tinted** in their colour. The colour is their avatar tone, **darkened (light mode) or lightened (dark mode) until it reads at 3:1 against the page**. The cursor layer is drawn inside the text view (it scrolls with the page, takes no touches); `CoEditMap` maps draft blocks onto the editor's lines and back.

## 5. Pictures and video from any author

`draft_add_file` (any author): the file is kept on the adder's phone, **encrypted there and uploaded once** (the ordinary attachment upload, chunked and resumable), and the key and details go to every other author in the sealed op `draft.file {number, file descriptor}` (never to the server). The number is random (so two authors adding at once do not collide). Each author's phone fetches and verifies the bytes on demand (`draft_file_data`), showing the tiny thumbnail meanwhile. The editor swaps its own list index for the draft's file number whenever it writes to the draft, so every author's editor shows the picture and the writer's publish includes it.

## 6. Publishing

**Only the writer publishes** (DESIGN-22 section 6, the user: "ok"): the post lives in and is signed by the writer's jam. A co-author sees **"Shem publishes this article"** and a **Ready** button (`draft_set_ready`, sealed `draft.ready` to the writer only); the writer sees **"Jean is ready"**. After a publish the writer's phone sends `draft.published {post_id, at, heads}` to every author (`draft_mark_published`), which clears all Ready flags; everyone sees **"Published by Shem · <time>"**, and **"Changes since the last publish"** when the draft's heads differ from the heads sent. In the app the writer's Post and Update are unchanged (the editor's own Markdown and file list, so covers, captions and link cards work as before) and then call `draft_mark_published`; a co-author's toolbar button is **Done**. `publish_draft` (core-first, for Android and tests) publishes the draft directly: pictures from any author become the post's files numbered from 0 in order of appearance.

## 7. What each party learns

- **The server (Supabase):** for the **durable path**, the same as a busy group chat: that these accounts exchange sealed items, their sizes and times; nothing of the text. For the **instant path (new metadata):** that some network addresses are connected to one random channel at the same moment, and the sizes and times of encrypted messages on it; **not accounts** (no token is sent), not text. For **pictures:** one more encrypted blob and its size, like any attachment. The relay cannot read, forge or replay anything useful: it holds no key; forged or replayed messages fail the signature or the author check.
- **Someone who learns a channel id** (it is never sent to the server in a form tied to an account, only used as a topic name) can join the topic and see ciphertext and sizes, or inject junk, which is dropped. They cannot read it.
- **Co-authors:** the whole draft and its history, their colleagues' cursors, the pictures. A removed co-author keeps what they already had and gets nothing after the key change.
- **Subscribers:** only published versions; nothing of the drafting, presence or Ready flags.

## 8. Limits for v1

5 authors per draft; about 200 KB of text and 2,000 blocks; 10 files per draft; articles only (not quick posts, podcasts, or org posts by several writers); compaction after 200 changes; presence at most ten sends a second; durable batches at most one per 5 s per draft.

## 9. Android notes

Everything above except two adapters is in LimeCore (Rust through UniFFI) and `./core/check-android.sh` passes: the document, reconcile, the instant wire format and verification, the durable ops, files, status, `publish_draft`. Android needs: (1) a **Realtime WebSocket client** like iOS's `DraftRealtime` (the Phoenix protocol: `phx_join` with `private:false`, `broadcast` event `d` with payload `{w: base64}`, a heartbeat every 25 s, backoff on reconnect); (2) the editor and cursor rendering. The iOS editor feeds the draft by Markdown reconcile because its text view is the source of truth; an Android editor could call the block-level edit calls (`draft_insert_text`, `draft_mark`, ...) directly.

## 10. Operations

See `docs/api-v2.md` section 16 for the `draft.*` ops.

## 11. Tests

Core (`client_tests.rs`, `drafts/tests.rs`): two authors typing in one paragraph end equal (durable); a late joiner catches up from a snapshot and is then heard; a removed co-author gets nothing and what they send is dropped; offline edits merge; durable sends stay within 12 a minute while typing; a bad signature or a removed author's instant message is dropped; a lost send answer loses nothing; the instant path against the real Realtime stack (worst 12 ms); only the writer publishes, Ready, the published banner and "changes since"; a co-author's picture is in the writer's post. iOS: unit tests for colours (3:1, all 8 tones, both modes), the block-to-editor map, presence timing, pictures drawn without changing words; UI tests in the demo with simulated authors (faces, cursor tag, remote words in place, my caret stays, no Post button for a co-author, Ready, the published banner).

## 12. Differences from DESIGN-22, and what is not built

- The durable path is **pairwise sealed ops, not a Megolm "draft group"** (section 2).
- Inviting sends `draft.invite` **when the co-author is picked**, not "once they accept", because the existing co-author ask happens at publish time; accepting is opening the invitation.
- **"Changes since the last publish"** is a line at the top, **not a highlight on each changed paragraph** (that needs a copy of the published text to compare with).
- A picture's server blob lives for the ordinary attachment retention; an author who opens a draft long after may find an old picture gone (the adder's phone could re-upload on demand: not built).
- The editor redraws its text when another author's change arrives, which **resets that text view's undo stack**; the caret, selection and keyboard are kept.
- Cursors are best-effort for blocks the editor draws differently from the draft's words (pictures, buttons and dividers have no cursor).
- Org posts by several writers (193d) and podcast descriptions are later.
