# Organizations and channels: lime out to the community (design, LIME-193)

**Status: a design for you and plot to choose from. No app or server code.** Written against the code as of `a5cf20a`+; every claim names the file it comes from. The answers to the brief's (a) to (e) are sections 1 to 5; the tables of **what each party learns** are section 6; the limits and the split into build briefs are sections 7 and 8; section 9 lists what in the brief's decisions I would push back on.

## 0. What is already decided (the user, 2026-10-22)

- **O1.** lime's official posts are **open and signed by lime** (stored readable, signed with a key pinned in the app, reaching every teacher at any scale). **Teachers' jams stay end-to-end encrypted.**
- **O2.** New accounts follow lime automatically. **Mute yes, leave no**: muting hides lime's posts from the feed (still on lime's profile); **important notices** still arrive.
- **O3.** Organizations in v1: **lime and schools/groups**: several writers posting as one org.
- **O4.** Channels in v1: announcement "group chats" like WhatsApp Channels, **in link**; admins post; **reactions, comments, replies are each a setting**; lime's channel reaches everyone.
- **(d) ⚑** A channel is **a group in the Messages list like any other** (same row, same chat screen), **no "Channels" section**; for lime's: **no Leave, but Hide** (it leaves the list; a Settings row brings it back; important notices still surface).

## 1. (a) Org identity: what an organization is and how a writer proves "I post as this org"

**What exists today.** A person is an account (`auth.users`, a `profiles` row: `supabase/migrations/20261006140000_accounts_and_two_step.sql`) with a **master key** (Ed25519, `core/src/keys.rs` `AccountState.master`) that signs each of their **devices'** keys (`cert()`: a `SenderCert { device_id, master_signature, identity_key, signing_key, master_key }`). Receivers **pin** the master key per user (`pin_master_key`, `core/src/client.rs` ~1081) and verify a sender by that chain: device key → master key → pinned. A group is a conversation with a signed state log (`core/src/protocol/group.rs`: roles `Owner`/`Admin`/member, `MAX_MEMBERS = 100`). A jam has one writer (`docs/jam.md` §2, `writers: [user]`).

**The options.**

| | A1. An org is an account | A2. An org is a group with an org flag | **A3. An org is a keypair with a public page, and writers hold certificates from it (recommended)** |
|---|---|---|---|
| Idea | The org signs in like a person (own `auth.users` row, own devices) | Reuse `grp:` state: owners/admins are the writers | An org has an **org key** (Ed25519, like a user's master key) and a page (`orgs` table, like `jams`: `20261021000000_jam_server.sql`). A writer proves "I post as this org" with an **org certificate** |
| Writers | They would have to share the org account's devices (passwords, device keys): bad | Roster is capped at 100 and visible to every member (`group.history` replays it) | Each writer keeps **their own account and devices**; nothing is shared |
| Revocation | Change the password and re-key | Remove from the group | Revoke the certificate (below) |
| Verdict | Rejected: a shared login is the opposite of a signed chain | Right for a *channel's audience* (section 4), wrong for *who may speak for an org* | Chosen |

**The org certificate.** `OrgCert { org_id, writer_user, writer_master_key, role: owner|writer, serial, not_before, not_after }`, signed by the org key. A post (or channel message) made as the org carries `as_org: { org_id, cert }` next to the writer's normal device signature. A reader checks: the device cert chains to the writer's pinned master key (**already done today**), the org cert names that same master key, it is inside its validity window, its serial is not revoked, and the org key is the one pinned for `org_id` (lime: compiled in, section 2; others: pinned on first sight from the org page and shown when it changes, like a contact's key change). **Revocation** is a signed `org.revoke { serial }` in the org's public log (a small append-only list served with the page, so it needs no server trust), plus short certificates (30 days) that an admin device **re-issues automatically**, so a lost writer or a removed teacher stops being able to speak for the org within a month even if nobody revokes.

**Where the org key lives.**

| Custody | How | Trade-offs |
|---|---|---|
| **K1. Staff devices** | The org key's private half is held, encrypted, on 2 to 3 owner devices (shared with each other over Olm, as the group session keys are) | Simple; a stolen unlocked owner phone can sign anything until revoked. Fine for a school |
| **K2. Offline root plus delegates (recommended for lime)** | The **root key** is generated once in a small ceremony (two staff, an offline machine or hardware key) and **only signs short-lived delegate certificates**; day to day, staff devices hold a *delegate* key the root certified for 30 days and re-certified at a monthly ritual | The pinned key in the app never changes and is almost never online; a leak of a staff device costs a month at most and is revocable. More ceremony. Needed once; documented in the release checklist |
| K3. Server holds it | The server signs for lime | Rejected: it makes "signed by lime" mean "the server said so", the one party this design must not have to trust |

**Recommendation (a):** A3 with **K2 for lime** and **K1 for schools and groups**. An org is *not* an account: it is `orgs` (id, name, about, public key, `verified`, created), its members are ordinary accounts that hold certificates. Roles are owner (can issue certificates and change the page) and writer (can post as the org); "member/reader" is just a subscriber, as in jams.

## 2. (b) lime's official channel/jam: open and signed

**Where open posts live.** A new table `org_posts` (`post_id`, `org_id`, `kind`, `title`, `subtitle`, `markdown`, `attachments[]` as public blob ids, `important bool`, `created`, `signature`, `signer_cert`) readable by any signed-in user (the same trust class as `jams`/`profiles`), plus a **public blob class** beside the existing ones (the attachment bucket's classes are in `supabase/functions/_shared/attachments.ts`; the jam class is the one with no expiry): files of open posts are stored **unencrypted** and fetched by a plain cacheable URL. Nothing is stored encrypted that lime wants everyone to read; **the point of O1 is that it needs no per-reader work**.

**How phones verify.** lime's **root public key is compiled into the app** (as the sealed-sender and relay constants are). A post is accepted only if its signature verifies under a delegate cert that chains to that root (section 1, K2). **Rotation:** the root signs a **successor** key and the app accepts "next root" statements signed by the current one, so a rotation needs no app update; if the root is ever lost or stolen, an app update ships a new pinned key (the honest worst case). A forged post from the server fails verification and is dropped, and the failure is shown nowhere (an attacker must not get a way to spam a banner).

**Auto-follow on signup: no server work.** Because every phone reads the open store, **"following lime" is the default state of the app**, not a subscription row. There is no fan-out, no per-device send, no key to hand out. **Mute is local** (a setting on the phone: lime's posts disappear from the feed and from the lime group's list; still on lime's profile). **Leave does not exist** (O2). **Hide** (section 4) is also local.

**Important notices.** A post flag `important` that **ignores mute** and may be set **only for policy and security** (a categorised flag: `policy`, `security`; the app rejects any other value, and lime's signing delegate for "important" is a separate, rarely used certificate so a compromised marketing delegate cannot push one). It surfaces as a banner and a notification through the existing notify path (`supabase/functions/_shared/notify.ts`; no new device metadata: the server already holds every device's push token for messages).

**Scale.** Reads are `GET /org-feed?org=lime&since=<cursor>`: cacheable, ETag'd, polled when the app opens and on a silent push for a new post. **Any number of readers, no per-device fan-out** (contrast jams: `docs/jam.md` §4, 1,000 subscribers and a send queue). The cost is bandwidth for posts and public blobs, served from the edge.

**What the server learns.** lime's posts are **public by design** (it stores them readable and signed). **Reading them reveals nothing**: every account reads them, so a fetch carries no information beyond "this account is running the app" (which a sync already tells it). It learns nothing about mute or hide (local). It *can* see who opens a given public blob; that is the same as anyone opening any public web page, and lime's own posts are not secret.

**The exception to `docs/jam.md` J1, stated plainly.** jam.md §7 chose "page public, **all posts encrypted**" for teachers' jams. lime's official content is the one deliberate exception, for a reason that is specific to lime (it is the platform's own announcement channel, and its authenticity matters more than its secrecy). No teacher's content is ever stored readable.

## 3. (c) Encrypted shared jams for schools and groups: several writers

**What a jam has today.** One writer: one Megolm session per tier on the writer's phone (`core/src/client/jam.rs`), a **subscriber set held only on the writer's phone** (`jam_subscribers`), post blobs fetched without a session (`jam-blob-get`), comments routed through the writer (`docs/jam.md` §5 E2), rotation on removal, a limit of 1,000 subscribers.

**The two ways to add writers.**

| | **W1. One shared org session** | **W2. A session per writer device (recommended)** |
|---|---|---|
| Idea | All writers hold the same outbound Megolm session (shared over Olm among writers) | Each writer device has its **own** outbound session per tier, shared with the subscribers, exactly as a jam writer does today, and each is announced inside the org's state |
| Megolm rule | Two devices must **not** send with one session's ratchet (they would reuse indices): needs a coordinated counter or a lock | Natural: a session has one sender |
| Subscriber's view | One session per tier | A few sessions per tier (one per active writer device); `jam.welcome` carries each |
| Rotation on removal | Rotate one session | Every writer device rotates its own (one op each) |
| Verdict | Fragile | Reuses the jam v1 sending code unchanged, per writer |

**The subscriber set without the server learning it.** Today only the writer's phone has it. For several writers it has to be shared among them. **Recommendation: a small encrypted "writers' group"** (the existing group machinery, `core/src/protocol/group.rs` and `client/groups.rs`, capped to ~20 writers, which is within `MAX_MEMBERS`) carries `org.subscribers` ops (add, remove, tier) among the writers only. A reader's `jam.subscribe` is sent (Olm, as today) to **all owner devices**; the first to receive it answers with the welcome and publishes the new row into the writers' group; duplicates are dropped by op id. The server sees the same kind of sends it already sees; it never holds the roster.

**Comments.** E2 (`docs/jam.md` §5) says the comment goes to "the writer", who republishes it. With several writers it goes to **the post's author-writer**, or to the org's **moderators** (writers with a flag) when the author is away; the republishing is signed as before. **Removal and rotation:** any owner removes a subscriber; the writers' group distributes the removal; each writer device rotates its own session, so the removed person reads nothing new from any of them. **Limit:** the 1,000-subscriber cap stays (the send queue, not the model, is the bound); an org that needs more is the case for lime-style open posts or for a later server fan-out.

## 4. (d) Channels are groups in link; one model, two views

**What the user asked.** "Channels should just be a group … look like any other group; although they can't leave it, they should be able to hide it some way (maybe in Settings)." So a channel is **a row in Messages and an ordinary chat screen**, with **admin-only posting** and the three settings: **reactions, comments, replies**.

**Two kinds, same look.**

1. **lime's channel** (open, signed; everyone). It cannot be a real group (a group of everyone is impossible: 100 members, a roster on every phone). It is a **client-synthesised conversation**: the Messages list gets a row, "lime", whose messages are the **short posts** of lime's open feed (section 2), drawn as chat bubbles by the same chat screen. No membership, no roster, no group state. **No Leave.** **Hide:** the row leaves the list; **Settings → Chats → Hidden chats** brings it back; important notices surface regardless (a hidden chat does not hide them). **Settings:** lime chooses per post or for the channel: reactions on/off, comments on/off, replies on/off. **Reactions** on an open post: counted server-side as a public number (a reaction is a plain signed op to the open store, so a count is natural); **comments**: public threads under the post (moderated by lime; this is the one place the server stores readable teacher text, so it needs the Report path first: LIME-191); **replies**: a private reply to lime opens a normal 1:1 chat with lime's support account.
2. **A school's or a group's channel** (encrypted, members). A **real group** (`grp:`) with an **announce flag**: a group-state setting `{ posting: "admins", reactions, comments, replies }` carried in the signed state log (`protocol/group.rs` gains a `Settings` event beside `Role`/`NewOwner`), enforced by receivers (a message from a non-admin to an announce group is shown nowhere, as a forged op is today). Members' **reactions** use the existing reactions (`reactions` table), **comments** are threads under a post (the existing `thread_root`), **replies** are a private 1:1 to the admin. Up to 100 members (`MAX_MEMBERS`); larger audiences move to the publication model below.

**Is a channel the same data model as a jam?** **Recommendation: yes, one "org publication" model with two views, but not in v1's storage.** A *publication* is posts by an org (open for lime, encrypted for schools); **link shows its short posts as chat bubbles, jam shows its articles and recordings as cards**, the same post in both when its kind allows. In v1 the two kinds above are built on what exists (an open feed; a group with a flag) so nothing waits for a rewrite; the shared model is the target the later "channel with 1,000 members" will use (the jam machinery of section 3 under the channel's chat view). The cost of unifying now would be tying announcement channels to blob fetch latency and the 1,000 cap before they are needed.

## 5. (e) Moderation and safety

- **Who can create an org.** lime's is created by lime (the ceremony, section 1). **Schools, districts and subject groups: any signed-in teacher can *request* one; it is created unverified and works for a small audience (a group channel of up to 100, an encrypted jam), but only a *verified* org appears in directory search and shows the badge.** Verification is a manual review by lime (a school domain email, a staff page, or a letter), recorded as `orgs.verified`; a verified org's badge is a check mark by its name wherever it appears (the references' pattern), **and the badge is an app-side rendering of a server flag, so lime must never be able to verify an org it did not review: the flag change is a signed op in the org's public log** and shows in `docs/audit-scope.md`'s list.
- **Impersonation.** Name rules at creation: reserved words (`lime`, `lime support`, `admin`, `official`), a similar-name check against verified orgs, and the badge as the user's cue; the org certificate chain is what the app trusts, never the display name.
- **Report (LIME-191).** Every org post and channel message gets the report path the jam design already assumes (`docs/jam.md` §6: the reporter's phone forwards what it can read). For an org the platform's powers are: take the org page down, withdraw its certificates from the directory, ban the account of a writer, and **(only for lime's own open store) remove a post**. It cannot reach into members' phones.
- **Muting an org.** Local, for any org the teacher follows; "mute" never applies to `important` posts from lime (section 2) and never to a school's `important` flag, which a school does **not** get (only lime's policy/security notices are exempt from mute).

## 6. What each party learns

**lime's open channel (O1).**

| Party | Learns |
|---|---|
| **The server** | The posts and files in full (it stores them readable by design); the reaction counts and public comments; who fetches the feed (every account, so no signal); important-notice delivery goes through the push path it already runs. **Nothing about mute or hide** (local). |
| **A reader's phone** | The posts, verified against lime's pinned root; nothing about other readers. |
| **lime (staff)** | Public numbers only (reaction counts, comments); never who has muted or hidden. |
| **Anyone else** | A signed-in account (or, if lime chooses to expose it, anyone) can read the posts: they are public. |

**An org's encrypted jam or channel (schools, groups).**

| Party | Learns |
|---|---|
| **The server** | The org page (public by design: name, about, topics, subscriber count, `verified`), blob sizes/times/addresses as for any jam (`docs/jam.md` §8), the recipient sets of notices; **never** post, comment or reaction content, titles, or the roster. |
| **The writers** | The posts they and the other writers made, the subscriber set (shared inside the writers' group), comments and reactions. |
| **Subscribers / members** | The posts and, for a group channel, the member list as a group shows it today; not the writers' devices beyond their certificates. |
| **A removed person** | What they already had. |

## 7. v1 limits

lime's channel: unlimited readers, short posts and articles, files up to the public blob limit (to set; start at the jam's 24 MiB), one open feed. An org's encrypted jam: **1,000 subscribers, ~20 writers**. A school's channel group: **100 members**. Certificates are 30-day and automatic. Verification is manual. No payments, no cross-org posting, no org-to-org follow. **Not v1:** lifting the 100-member cap for channels (section 4's publication model), org analytics, scheduled posts.

## 8. Proposed split into build briefs (for plot to draft)

1. **193a Org identity (core):** `orgs` table and page function; org keypair, `OrgCert`, issue/verify/revoke; pinned lime root in the app; the ceremony document. Tests: chain, expiry, revocation.
2. **193b lime's open feed:** `org_posts` and the public blob class; the signed-post format and verification; the app's open-feed reader; **auto-follow (default), mute, hide**, important notices (+ push); lime's synthesised "lime" row in Messages with no Leave and Settings → Chats → Hidden chats.
3. **193c Channel settings in groups:** the announce flag and `Settings` event in `protocol/group.rs`; admin-only posting enforced by receivers; the reactions/comments/replies settings and their UI in group details.
4. **193d Shared encrypted jams:** writers' group, per-writer sessions, the subscribe route to owners, comments to moderators, rotation; the page shows the org.
5. **193e Org creation, verification and badge:** request flow, the review tool, the signed `verified` op, name rules, impersonation checks, Report hookup (with LIME-191).
6. **193f lime on lime:** the first lime posts (welcome, tutorials, tips), the "all teachers" default for new accounts, support account for replies.

## 9. Where this pushes back on the brief (also in the TEND record)

- **O1's "reaches every teacher at any scale" and "reading reveals nothing"** hold for reading, but **lime's open comments and reactions are the first server-readable teacher text**: they need LIME-191 (Report) *before* they are switched on, so v1 of the open channel should ship **posts only**, with reactions/comments/replies settings present but off.
- **O2's "important notices still arrive" with "mute yes"** needs a **hard policy** (policy and security only, a separate certificate) or the exception becomes a marketing channel; section 2 proposes that.
- **O3 "several writers in v1" and "1,000 subscribers"**: with several writers the **subscribe route** (to all owners) and the writers' group are new moving parts; **193d is the riskiest brief**: consider shipping lime's open feed and group channels first, and shared jams after.
- **(d)'s "same model as a jam"** is the target; building it first would delay lime's own channel for little gain (section 4).
