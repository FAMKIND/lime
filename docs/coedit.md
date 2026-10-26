# Live co-editing: the design (LIME-233, DESIGN-20)

**Status: a design for the user's review. Nothing in this document is built.** The decision already made (DESIGN-20, the user): **B, live co-editing**. Co-authors join the article editor and write together, like Google Docs, for curriculums and lesson plans made by several teachers. This document answers how, with the trade-offs, and ends with what each party learns, the limits for v1, and the build split.

## 0. What exists today (the survey)

- **The document.** The article editor keeps an `NSAttributedString` (`ComposerDocument.swift`) and converts it to and from a **Markdown subset** through LimeCore (`core/src/format.rs`, "the one place the grammar lives"). Inline: bold, italic, underline, strike, code, mentions. Blocks: paragraph, headings 1 to 6, quote, indent, bullet and numbered lists (with levels), code, **button** (https address, caption, palette colour), divider, **freewall** (the paywall marker, 188n), and **pictures, videos and audio as references to the post's n-th attachment** (`![](attachment:n)`), plus the cover (219). Drag to arrange blocks (188r). A post's Markdown is capped at **30,000 bytes** (`MAX_POST_BYTES`).
- **A post is sealed once, by one person.** The writer's phone writes the Markdown and the attachments into one encrypted **blob** (a jam-class file on the server, AES key inside the jam's per-tier Megolm notice), signs a small notice with the writer's device key, and sends it to the subscribers in the writer's per-tier Megolm session. An **edit** (195) is a new version of the same post id: a new blob, a new notice. **Co-authors** (188f/g, 195b) are a *credit*: up to four of the writer's contacts are asked, accept, and then "with Jean Chung" shows; they receive the edits, but they cannot change the post. Nothing in the app lets two people write one document.
- **Groups** (`protocol/group.rs`, `client/groups.rs`): an encrypted group is a conversation with a signed state log (owner/admin/member, up to 100), one **Megolm** outbound session per sender, rotated on membership change, 100 messages or 7 days; keys travel over Olm. 232/232b made the Olm and Megolm paths safe against lost answers and drift.
- **Orgs** (`docs/orgs-and-channels.md` §3, 193d): several writers post as one org; a **writers' group** (the group machinery, capped at about 20) shares the subscriber roster; writers hold certificates from the org key.
- **Two clocks, not one.** There is no shared clock between phones; ordering in groups uses a hybrid logical clock (`Hlc`).

## 1. The CRDT

**The need.** Several people type into one document at once, some offline; every phone must end with the same document, without a server that understands the content. Rich text (marks over a run), ordered blocks, per-block settings, references to files.

| | **A. Automerge** (`automerge` 0.12, Rust) | **B. Yrs** (`yrs` 0.28, the Rust port of Yjs) | **C. Block-level last-writer-wins** (own, simple) |
| --- | --- | --- | --- |
| Fit | Rust, so it lives in LimeCore; iOS and Android reach it through our own UniFFI functions (we never expose its API) | Rust, same | Rust, a few hundred lines |
| Rich text | Native text with **marks** (Peritext rules: a bold run survives concurrent edits at its edges) | Text with formatting attributes (the Yjs editors' model) | Whole blocks only: a paragraph's text is one value |
| Concurrent typing in one paragraph | Merges per character | Merges per character | **One person's edit wins; the other's is lost.** Not acceptable for "writing together" |
| History and size | Columnar and compressed: in my throwaway test, **2,000 single-character edits by two authors saved as 2.6 KB** (a document of 2,041 characters) | **43 KB** for the same edits (update format; garbage collection of deleted text keeps it from growing without bound) | n/a |
| Sync | A built-in sync protocol and incremental changes (`get_changes`, `apply_changes`) | State vectors and diff updates; **awareness** (presence) protocol included | Our own |
| Maturity | Newer than Yjs in editors; the Rust core is the reference implementation | The most deployed in editors (ProseMirror, Quill) | Ours to get right |
| Static library | about 7.4 MB before linking and dead-stripping (the app's core is 53 MB the same way) | about 6.3 MB | negligible |
| Cost of being wrong | A format change between versions needs care (documents are long-lived) | Same | We own every bug |

I merged the same three concurrent edits (two at one spot, one at the start) in both libraries: **both converged to the identical string** (`"# Fractions that stick\n\n (draft)A lesson."`).

**Recommendation: Automerge**, because (1) its compressed history is an order of magnitude smaller, which matters when a curriculum is edited for months and every change is an encrypted message, (2) marks give us bold/italic/underline/strike/code/mention as first-class, (3) one `save()` snapshot is a complete, compact thing to hand to a new author. Yrs is the credible alternative and would also work; its advantage (awareness, editor ecosystem) is mostly for web editors we do not use. Option C is rejected: it cannot do "Google Docs".

**The mapping (one Automerge document per draft):**

```
root
  blocks: List of Map          # the order of blocks IS the list (concurrent inserts and moves converge)
    { id: uuid, kind: "paragraph"|"h1".."h6"|"quote"|"indent"|"bullet"|"number"|"code"|"button"|"divider"|"freewall"|"file",
      level: int,                # list nesting
      text: Text (with marks)    # bold, italic, underline, strike, code, mention{user}
      attrs: Map                 # button: url, caption, colour (each field last-writer-wins); file: file_id, caption; number list: start
    }
  files: Map of file_id -> { name, mime, kind, blob_id, key, sha256, size, width, height, duration, added_by }
  meta: Map                      # title, subtitle (each a small Text), cover: file_id, topics
```

- **Rich text** is a `Text` with marks, one per block, so a Return splits a block (a new Map inserted after, the tail of the text moved) the way the editor does today.
- **Block order and drag to arrange** are list operations (move = delete and insert of the same block id with its content copied; blocks are small, so copy-and-delete is acceptable whether or not the library offers a native list move, which I did not check).
- **Images, videos, audio** are `file` blocks that point at a **stable `file_id`**, not at "the n-th attachment" (that index changes when files are added or removed). **At publish** the file blocks are turned back into today's `![](attachment:n)` with the attachments in document order; the cover is the first `cover.jpg` as now. Nothing downstream (the reader, the sealed post, subscribers) changes.
- **Buttons and the freewall** are blocks (their address, caption and colour are `attrs`; two authors editing the same button field is last-writer-wins, which is what a person expects).
- **The conversion** between the editor's attributed string and these blocks stays where the grammar already lives: LimeCore. The iOS editor sends **text deltas** (replace range r with string s, apply mark m over a range) and receives deltas for remote changes; Android will do the same with its own editor.
- **Undo** is per author: your undo reverts your own latest changes, never someone else's. (Implemented by remembering the operations of the local actor; an Automerge actor id is per device.)
- **Authorship colours** (who wrote this) are possible because each change carries its actor id; a signed `draft.actor` op in the draft room maps actor ids to users (§2). Not in the first build (§8).

## 2. The channel

**Recommendation: each draft has its own small encrypted room made from the existing group machinery**, so we reuse Megolm, signed state, rotation and the mailbox, and inherit 232/232b's guarantees.

- **The room.** A conversation of a new kind (`dr:<draft id>`, hidden from Messages) with the group state log: the **writer** is the owner; each **accepted co-author** (the 188f request and accept, unchanged) is a member. Not shown as a chat anywhere; it surfaces only inside the article editor ("Drafting with Jean").
- **Ops in the room** (each signed by the author's device, like a group message, sealed in the sender's Megolm session):
  - `draft.change { changes }`: a batch of Automerge changes (a few hundred bytes; typing is coalesced to **at most one batch every 1.5 seconds** per author while typing).
  - `draft.snapshot { doc, heads }`: a complete `save()` of the document, sent when someone joins, after a long offline gap, and every 200 changes or 24 hours so that old change messages can be forgotten.
  - `draft.heads { heads }`: a small hello sent when a phone comes online, so peers can send what is missing (this is the Automerge sync idea carried on the room's messages, without a live connection).
  - `draft.actor { actor_id }`: maps a device's actor id to a person (for authorship colours).
- **Who is in it, adding and removing.** Adding an author = the writer adds them to the room's state log (they already accepted the credit request); the room's Megolm session rotates and the new member receives the key **and a snapshot** over Olm, so they see the whole draft. **Removing** an author rotates the session: they read nothing new. What they already wrote stays in the document (a CRDT cannot unwrite; the writer reverts by editing), and what they already read they keep on their phone (no one can take that back; the screen says so).
- **Offline edits and merging.** Each phone keeps its replica and its pending changes. On reconnect it sends `draft.heads`; peers answer with the changes the sender lacks (or a snapshot if that is smaller). Because merges are commutative, order of arrival does not matter. A phone that was offline for a long time may receive a snapshot and many changes: it applies them all, then shows a brief "Updated with Jean's changes" line.
- **History size and compaction.** Automerge keeps the whole history (that is what makes concurrent merges exact). A draft's `save()` is the compact form (2.6 KB for 2,000 edits in my test). Change messages sit in a device's server mailbox only until that device fetches and acknowledges them (and expire there like any mailbox item); the long-term copy is each phone's replica. A snapshot every 200 changes bounds what a new or long-absent device must fetch. After the post is published and the draft is archived, a snapshot is the last thing sent.
- **Sessions and rotation reuse the group rules:** a new outbound Megolm session after a membership change, 100 messages or 7 days (typing batches are many messages, so rotation will be frequent; the cost is one small key message per author per rotation).
- **Authentication.** Every op is signed by the author's device and checked against the pinned master key like any group message. A member cannot forge another's edit; any member can *make* an edit (that is the point).

## 3. Presence

- **What is shown:** who is in the draft now (small circles at the top of the editor), a **remote caret and selection** in each author's colour with their first name when they move, and "Jean is typing".
- **Mechanism:** ephemeral `draft.presence { anchor, head, typing }` ops in the same room. The anchors are **positions in the CRDT** (an element id plus offset), so a caret stays in place while others type before it.
- **Traffic discipline (so the server sees a sane amount):** presence is sent **at most once a second** per author, **only while the editor is on screen and the author has moved or typed in the last 10 seconds**, and **only to authors who sent presence themselves in the last 60 seconds** (others are offline or not looking). It stops 10 seconds after the last movement. Presence is **not stored**: a small server change adds an `ephemeral` flag to `send` that gives the item a 60-second expiry (so a phone that was offline does not wake up to a pile of old carets). Without that server change presence would still work but would sit in mailboxes; it is cheap to add.
- **Rate limits:** the existing per-address send limit applies; at 1 presence message per second per active author and 4 other authors it is far under it. Drafts are limited to **5 authors** (§8).

## 4. Files

An image, video, audio or file one author adds while others are editing:

1. The author's phone encrypts it (the same chunked AES the attachments use) and uploads it **once** as a new **`draft` blob class** (owned by the uploader, counted against their quota, **30-day expiry that is renewed while the draft is edited**; abandoned drafts clean themselves up).
2. It writes the file into the document (`files` map: id, name, mime, size, hash, dimensions, **blob id and key**), so the **key travels inside the encrypted room**, never to the server. Every author's phone then shows a placeholder and downloads the blob in the background; the CRDT carries only the small record.
3. **At publish** the writer's phone has all the files (it downloaded them) and uploads them as ordinary **jam-class** blobs inside the post, exactly as for a post written alone. Draft blobs are deleted. So the published post and its files are indistinguishable from today's: no new trust on the server, no new reader code.

Removing a file from the draft removes its block; the blob lapses at its expiry (or is deleted by the uploader's phone when no one references it).

## 5. Publishing

- **The draft and the post are different things.** The draft lives only in the authors' room. The **published post** is today's post: one sealed blob, signed by the writer's device, sent in the writer's jam session to the subscribers.
- **Who may Publish and Update: the writer only (recommended for v1).** The writer's phone holds the jam's outbound sessions and signs the notice; letting a co-author publish would mean handing them the jam's session keys or a signing delegation, which weakens "this is the writer's jam" and has a long tail (revoking, per-tier sessions, rotation). Co-authors get a **"Ready" button** instead: it marks the draft ready (a small op in the room) and the writer sees "Jean marked it ready". The writer taps Publish.
- **Publishing from a draft:** the writer's phone renders the current document to the Markdown subset (and the file list), checks the 30,000-byte cap and the free/subscribers audience as the editor does today, and publishes through the existing path. The post records the draft's **heads at the moment of publishing** (locally; not sent).
- **After publishing:** the draft **stays open**. Further changes accumulate; the editor shows "12 changes since published" and **Update post** (the writer only) sends a new version through the existing edit path (195/195b: a new blob, the same post id). Co-authors' credits are the same as today.
- **Series, covers, audience, topics, the Preview marker (210):** unchanged; they are the writer's choices at publish, not co-edited (the title and subtitle are co-edited).

## 6. Org posts and podcasts

- **Org posts (multi-writer orgs, 193d).** The org's writers' group is the natural member list: an org post's draft room has **the post's starter plus any org writers they invite** (up to the same 5, not all 20; large rooms are a typing-traffic problem). **Publish and Update** need the org certificate; every org writer holds one (193d), so **any org writer in the draft may publish as the org**, unlike a personal jam. This depends on 193d and is built after it; the draft room itself does not change.
- **Podcasts (recordings).** The audio or video is one person's recording and is not co-edited. The **title, subtitle and description** are short text and could use the same room, but the value is small. **Recommendation: articles only in v1**; podcasts reuse the same machinery later if teachers ask for it.
- **Quick posts and comments:** not co-edited.

## 7. What each party learns

| | Learns |
| --- | --- |
| **lime's server** | That these accounts exchange encrypted messages (as it already sees for any chat): **who** talks to whom, **sizes** (a few hundred bytes for a typing batch, a few KB for a snapshot), and **times**, including the **typing cadence**. Presence is flagged ephemeral and expires after 60 seconds. It stores draft file blobs as ciphertext for 30 days: their sizes and owners. It does not learn the content, that it is a draft rather than a chat, the title, or who is the writer. |
| **Co-authors** | The whole draft, its history (Automerge keeps it) and who changed what if authorship colours are on; the files. After removal they keep what they had. |
| **Subscribers** | Only **published versions**, exactly as today. They never see a draft, a co-author's unpublished words or presence. |
| **Apple** | Nothing new (notifications for the room's messages are silent and generic, or off: drafts do not notify). |

## 8. Limits for v1, Android parity, and the build split

**Limits (v1):**
- **5 authors** per draft (the writer plus up to 4 accepted co-authors: the same number as the credit cap).
- **Document: the 30,000-byte Markdown cap applies at publish**; the editor warns at 80 %. The Automerge replica itself is capped at **2 MB** (compacted); beyond that, "This draft is too large to edit together".
- **25 files** per draft, each up to the jam file limit (24 MiB).
- **Typing batches at most every 1.5 s, presence at most 1 per second** (§3).
- **Articles only** (§6). **No suggestions or comments on drafts** (a later brief). **No authorship colours in the first build.**

**Android parity (core-first).** Everything above except the editor is LimeCore: the CRDT wrapper, the markdown conversion, the room ops, rotation, snapshots, file records, presence. UniFFI gives Swift and Kotlin the same narrow functions (`draft_open`, `draft_apply_local_delta`, `draft_take_remote_deltas`, `draft_publish_markdown`, `draft_presence`, ...). Only the text-view binding (the part that turns edits into deltas and draws remote carets) is written per platform.

**The build split (estimates in working days; for plot):**

| | Brief | Size |
| --- | --- | --- |
| 233a | **Core: the document.** The Automerge wrapper, the block/mark model, conversion to and from the Markdown subset and the file list, convergence tests (property tests: random concurrent edits on 2 to 5 replicas always converge; a round trip equals the original Markdown) | L, 5 d |
| 233b | **Core: the draft room.** The `dr:` conversation kind, change/snapshot/heads/actor ops, join with snapshot, removal with rotation, offline merge, compaction, fault tests in the style of 232/232b | L, 6 d |
| 233c | **Server and core: presence and files.** The `ephemeral` flag on `send` (60 s expiry) and the `draft` blob class (30-day sliding expiry), presence ops with the rate rules, file records and background download | M, 3 d |
| 233d | **iOS: the editor binding.** Edits to deltas and back, remote carets and selections, "Jean is typing", local undo, placeholders for files arriving | XL, 8 d |
| 233e | **iOS: the flow.** "Draft with…" from the co-author request, the Ready button, Publish and Update from a draft, "n changes since published", leaving a draft | M, 4 d |
| 233f | **Hardening.** Three phones, bad networks, kills mid-sync, a 200-change offline merge, the size caps | M, 3 d |
| | **Total** | **about 29 working days** (233a to 233c can start before the editor design is final; 233d is the long pole) |

**Dependencies:** 232/232b (done), 188f/195b (the co-author flow, done), 231b's requests for any missing keys (done). The org case (§6) waits for 193d.

## 9. Decisions for the user

1. **Automerge** (recommended) or Yrs?
2. **Only the writer publishes** (recommended), with a "Ready" button for co-authors, or may any author publish?
3. **Articles only in v1**, podcasts and org posts later?
4. **5 authors** per draft?
5. Is the **about 29 days** acceptable before TestFlight 1, or should a smaller first cut ship (for example: two authors, no presence, no files, then add them)? A reasonable first cut is **233a + 233b + 233d without carets, two authors, text only**: about 17 days.
