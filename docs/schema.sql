-- Lime data model — Draft. Aligns with seed-data/seed.ts.
--
-- Target: Supabase (Postgres). Ids are `text`, not `uuid` — the seed data
-- uses readable ids ("teacher-002", "conv-011", "msg-115"); new rows created
-- by the app use `text` columns holding `crypto.randomUUID()` strings, so
-- the column type never has to change when real data starts arriving
-- alongside seed data.
--
-- This file is the schema half of the contract described in
-- docs/data-model.md. Read that file first — this one is the DDL, not the
-- reasoning.

-- ── profiles ────────────────────────────────────────────────
-- One row per user. Seeded from seed-data/teachers.json; a real signup
-- creates one via Supabase auth's own trigger (not written here — this
-- schema only covers the app's own tables).
create table profiles (
  id             text primary key,
  -- LIME-24a-fix: the seam to a real login. `auth.uid()` (Supabase auth's
  -- own user id) is a uuid, and never equal to this table's readable text
  -- ids — comparing them directly in a policy would just never match.
  -- Nullable: a seed profile has no linked auth user until someone
  -- actually logs in as that person (see `current_profile_id()` below and
  -- the auth seam in data-model.md for how that linking happens).
  auth_user_id   uuid unique references auth.users(id),
  display_name   text not null,
  email          text not null unique,
  role           text,
  pronouns       text,
  school         text,
  grade_levels   text[],
  subjects       text[],
  bio            text,
  timezone       text,
  -- LIME-31. No seed teacher has one (the seed JSON never included a
  -- phone field) — every seeded row normalizes to null, matching "no
  -- column yet" from LIME-30's own read-only pass.
  phone          text,
  status         text not null default 'offline' check (status in ('online', 'offline', 'busy')),
  avatar_url     text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

-- ── user_settings (LIME-45) ─────────────────────────────────
-- One row per user, created lazily (first write) rather than alongside
-- every profile — most users never set a default background, so most
-- never get a row. A separate table rather than more columns on profiles
-- itself: this is preference state, not identity, and the split mirrors
-- conversation_members.background below (same shape, different scope).
create table user_settings (
  user_id            text primary key references profiles(id) on delete cascade,
  -- Same shape as conversation_members.background. Applies to every
  -- conversation that has no override of its own (kind:'default' or
  -- absent there falls back to this).
  default_background jsonb,
  updated_at         timestamptz not null default now()
);

-- ── conversations ───────────────────────────────────────────
-- Shared state only — anything that's true for every member (name,
-- description, whether it's deleted). Per-member state (starred, archived,
-- last read) lives on conversation_members below, never here, so starring
-- a chat never stars it for anyone else (production-ready principle 2).
create table conversations (
  id           text primary key,
  type         text not null check (type in ('direct', 'group', 'community')),
  name         text,
  description  text,
  created_by   text references profiles(id),
  -- Soft delete (owner only, per the RLS notes below) — a deleted
  -- conversation is hidden from listConversations, not gone from the table.
  deleted_at   timestamptz,
  -- LIME-24a-fix: makes a DM between two people unique. The store computes
  -- this — never the UI directly — as the two member ids, sorted, joined
  -- with ':' (e.g. "teacher-001:teacher-002"). null for group/community
  -- rows, which have no such uniqueness rule. `createConversation`'s
  -- promise to "return the existing DM" depends on this: it looks up
  -- `dm_key` before creating a new row, rather than trusting nothing
  -- stops a duplicate from existing.
  dm_key       text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create unique index conversations_dm_key_idx on conversations (dm_key) where dm_key is not null;

-- NOT modeled here, flagged rather than silently added: today's
-- seed-data/conversations.json gives `community`-type rows two extra
-- fields, `avatar_color` (a hex string) and `member_count` (a plain
-- number, e.g. 847). Neither fits this schema as written:
--   - `avatar_color` is presentational, not modeled by any other
--     conversation type.
--   - `member_count` directly contradicts production-ready principle 2:
--     a community's real member count is `count(*)` on
--     `conversation_members`, not a stored duplicate. The seed's numbers
--     (62 to 4521) are display-mockup placeholders — none of the 9 seed
--     communities actually lists that many participant ids.
-- Communities are still a static mockup in the app today (LIME-28 in the
-- drafted lifecycle makes them live) — resolve this when that brief scopes
-- what a community page actually needs, rather than guessing now.

-- ── conversation_members ────────────────────────────────────
-- Per-user membership AND per-user state (production-ready principle 2:
-- starred/archived/last-read belong to the membership, not the
-- conversation). Composite primary key — one row per (conversation, user).
create table conversation_members (
  conversation_id  text not null references conversations(id) on delete cascade,
  user_id          text not null references profiles(id) on delete cascade,
  role             text not null default 'member' check (role in ('owner', 'member')),
  starred          boolean not null default false,
  archived_at      timestamptz,
  -- "Delete for me" (LIME-34) — your own copy's clear point. Messages at
  -- or before this hide from your reads only; the conversation and the
  -- other member(s)' own rows are untouched. A message after this point
  -- (from anyone) makes the conversation visible to you again, with only
  -- what's after cleared_at showing.
  cleared_at       timestamptz,
  last_read_at     timestamptz,
  joined_at        timestamptz not null default now(),
  -- LIME-45: this member's own background for this one conversation —
  -- { kind: 'default' | 'color' | 'pattern' | 'photo', color, patternId,
  -- path, avgColor }. Absent or kind:'default' means "no override, use
  -- user_settings.default_background instead" (see below) — the same
  -- shape either way, so the UI never branches on which table a value
  -- came from, only on which one exists.
  background       jsonb,
  primary key (conversation_id, user_id)
);

-- ── messages ─────────────────────────────────────────────────
create table messages (
  id               text primary key,
  conversation_id  text not null references conversations(id) on delete cascade,
  sender_id        text not null references profiles(id),
  content          text,
  type             text not null check (type in ('text', 'voice', 'location', 'image', 'file')),
  -- LIME-38: an 'image'/'file' message's metadata is
  -- { name, size, mime, path } — path is opaque to every reader (never
  -- parsed, only ever handed to the adapter's own getAttachmentUrl) so
  -- the local adapter (IndexedDB, see local-adapter.js) and a real
  -- SupabaseAdapter (Storage, below) can use different path shapes
  -- without the UI ever knowing the difference.
  metadata         jsonb,
  -- A reply's parent. Deleting the parent takes its replies with it —
  -- there's no "reply to a deleted message" state to design for yet.
  reply_to         text references messages(id) on delete cascade,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

create index messages_conversation_id_created_at_idx on messages (conversation_id, created_at);
create index messages_reply_to_idx on messages (reply_to);

-- ── message_reactions ────────────────────────────────────────
-- Rows, not counts (production-ready principle 3) — a message's reaction
-- counts and "did I react" are both derived by querying this table, never
-- stored redundantly on the message itself.
create table message_reactions (
  message_id  text not null references messages(id) on delete cascade,
  user_id     text not null references profiles(id) on delete cascade,
  emoji       text not null,
  created_at  timestamptz not null default now(),
  primary key (message_id, user_id, emoji)
);

-- The reactor rule (LIME-24a-fix, replacing the earlier "dedupe the
-- senders" suggestion): a reaction's reactors are the conversation's
-- distinct members, in participant order, sliced to
-- `min(reaction.count, member_count)`. A reaction count can't exceed the
-- number of people who could actually react — deduping alone (the earlier
-- suggestion) doesn't enforce that ceiling, and seed-data/seed.ts's
-- current algorithm (filtering messages, mapping to sender_id, slicing
-- without deduping) can both produce duplicate reactor rows (violating
-- this table's primary key) and, separately, imply more reactors than a
-- conversation actually has members.
-- Confirmed against the real seed: conv-001's msg-006 carries a
-- `{emoji: "😍", count: 5}` reaction, but conv-001 is a 2-person DM — so
-- under this rule it becomes 😍×2 (both members), not 5. seed-data/seed.ts
-- is changed to this same rule in LIME-24b (the only change allowed there
-- in that brief); the local adapter uses it from the start.

-- ── message_attachments ──────────────────────────────────────
-- LIME-41 supersedes LIME-38's "one message per file, metadata.path on
-- the message itself" — any message (including one with real `content`,
-- which becomes that album's caption) can carry 0..n attachments here.
-- Old 'image'/'file' messages are left as-is, not migrated: they carry no
-- row in this table, and a reader synthesizes an equivalent single-row
-- result from their own metadata.path instead (see LimeStore.getAttachments
-- and the backward-compat mapping documented in docs/data-model.md).
create table message_attachments (
  id          text primary key,
  message_id  text not null references messages(id) on delete cascade,
  -- Opaque object key, same rule as messages.metadata.path (LIME-38
  -- above): never parsed, only ever handed to the adapter's own
  -- getAttachmentUrl.
  path        text not null,
  name        text,
  size        integer,
  mime        text,
  -- Recorded at upload time so the album grid can lay itself out (and
  -- reserve space) before the image itself has loaded, and so a reload
  -- never reflows the grid once it's already been laid out once.
  width       integer,
  height      integer,
  -- LIME-42: same reasoning as width/height above — recorded once at
  -- upload time (app.js's readAudioDuration decodes the file locally via
  -- a real <audio> element before it ever hits the wire) so the inline
  -- audio player's own duration label never has to wait for playback to
  -- start before showing a real number. Null for a non-audio attachment.
  duration_seconds  numeric,
  -- Display order within the message — the order the files were chosen
  -- in, not insertion order (today the same thing, but position is the
  -- documented contract).
  position    integer not null default 0,
  created_at  timestamptz not null default now()
);

create index message_attachments_message_id_position_idx on message_attachments (message_id, position);

-- ── link_previews (LIME-44) ───────────────────────────────────
-- A cache, keyed by the URL itself — not per-message, per-conversation,
-- or per-user: an unfurl of a given URL means the same thing regardless
-- of who linked it or where, so one row serves every message that ever
-- links that same URL, and re-fetching is only ever needed once
-- `fetched_at` is stale (a real TTL/refresh policy is a future brief's
-- concern, not written here). Populated by the unfurl(url) Edge
-- Function (fetch with a timeout and a size cap, parse Open Graph/
-- Twitter meta plus <title>/favicon/og:image/description/site_name,
-- block private IP ranges to prevent SSRF) — never by this app
-- directly; browsers can't fetch another site's metadata themselves
-- (CORS, and this app's own file:// origin during local dev has no
-- fetch access at all). The local adapter's own getLinkPreview(url)
-- never calls this Edge Function or any network endpoint — see
-- docs/data-model.md's own "Link previews" section for its fixture-map
-- and minimal-card fallback instead.
create table link_previews (
  url          text primary key,
  title        text,
  description  text,
  image_url    text,
  site_name    text,
  favicon_url  text,
  fetched_at   timestamptz not null default now()
);

-- ── Row-level security (draft, not yet enabled) ──────────────
-- Left as comments — RLS isn't turned on until Supabase actually backs
-- this app (the switch checklist in docs/data-model.md covers that step).
-- Written down now so 24b's local `can(action, conversation)` helper has
-- a real target to match, not just a guess.
--
-- LIME-24a-fix, two corrections to the first draft:
-- 1. Every policy below compares against `current_profile_id()`, never
--    `auth.uid()` directly — `auth.uid()` is a uuid and profiles.id is
--    readable text, so a direct comparison would simply never match.
-- 2. None of these policies query `conversation_members` from inside a
--    policy defined *on* `conversation_members` — Postgres RLS policies
--    re-invoke themselves when a policy's own query touches its own
--    table, which recurses infinitely. The `is_member`/`is_owner` helper
--    functions exist specifically to break that: `security definer` runs
--    them with the function owner's privileges, bypassing RLS for their
--    own internal lookup, so calling them from a policy is safe.
--
-- alter table profiles enable row level security;
-- alter table conversations enable row level security;
-- alter table conversation_members enable row level security;
-- alter table messages enable row level security;

-- ── Attachments (LIME-38, draft, not yet created) ────────────
-- Not a table — a Supabase Storage bucket, `attachments`, holding the
-- actual file bytes; messages.metadata.path (above) is the object key
-- within it: `<conversationId>/<messageId>/<filename>`. Storage buckets
-- get their own RLS-style policies (on storage.objects), not table RLS:
--
-- create policy "attachments_read" on storage.objects for select
--   using (bucket_id = 'attachments' and is_member((storage.foldername(name))[1]));
-- create policy "attachments_write" on storage.objects for insert
--   using (bucket_id = 'attachments' and is_member((storage.foldername(name))[1]));
--
-- (storage.foldername(name))[1] is the path's first segment —
-- conversationId — so both policies reduce to the same is_member() check
-- everything else here already uses. The local adapter has no equivalent
-- to enable: IndexedDB is private to this browser profile already.
-- alter table message_reactions enable row level security;
--
-- -- The current auth session's profile id, or null if unlinked. `stable`
-- -- (not `immutable`) since auth.uid() varies per request, not per call.
-- create or replace function current_profile_id()
-- returns text
-- language sql
-- stable
-- security definer
-- set search_path = public
-- as $$
--   select id from profiles where auth_user_id = auth.uid();
-- $$;
--
-- create or replace function is_member(conv_id text)
-- returns boolean
-- language sql
-- stable
-- security definer
-- set search_path = public
-- as $$
--   select exists (
--     select 1 from conversation_members
--     where conversation_id = conv_id and user_id = current_profile_id()
--   );
-- $$;
--
-- create or replace function is_owner(conv_id text)
-- returns boolean
-- language sql
-- stable
-- security definer
-- set search_path = public
-- as $$
--   select exists (
--     select 1 from conversation_members
--     where conversation_id = conv_id and user_id = current_profile_id() and role = 'owner'
--   );
-- $$;
--
-- -- ── profiles ───────────────────────────────────────────────
-- -- LIME-31: any authenticated user may read any profile (names,
-- -- avatars and titles throughout the app all resolve other people's
-- -- profiles, not just your own — the same reasoning as communities
-- -- being public-read). Only your own row can be updated, and only
-- -- through updateProfile's whitelisted fields (data-model.md) — email
-- -- and password are never written here at all, by design (see the
-- -- auth seam), so there's no policy gap to worry about for those.
-- create policy profiles_select_authenticated on profiles for select
--   to authenticated
--   using (true);
-- create policy profiles_update_self on profiles for update
--   using (id = current_profile_id());
--
-- -- ── conversations ──────────────────────────────────────────
-- -- Members read the conversations they belong to. `deleted_at is null`
-- -- here (and on the community policy below) is a deliberate choice, not
-- -- an oversight: it hides a soft-deleted conversation from being listed
-- -- or opened fresh, but existing members' access to its messages isn't
-- -- separately revoked below — soft delete is "leave my list", not
-- -- "retroactively lock everyone out", and nothing in the app today needs
-- -- the stronger version.
-- create policy conversations_select_member on conversations for select
--   using (is_member(id) and deleted_at is null);
--
-- -- Communities are readable by any authenticated user, whether or not
-- -- they've joined (joining is a separate conversation_members insert,
-- -- below) — the exact join-eligibility rule isn't decided until LIME-28.
-- create policy conversations_select_community on conversations for select
--   using (type = 'community' and deleted_at is null);
--
-- -- Creating a conversation: any authenticated user may insert one,
-- -- naming themselves as its creator. The matching conversation_members
-- -- row (making them the owner) is a separate insert, below.
-- create policy conversations_insert_creator on conversations for insert
--   with check (created_by = current_profile_id());
--
-- -- Only the owner renames or soft-deletes a conversation.
-- create policy conversations_update_owner on conversations for update
--   using (is_owner(id));
--
-- -- ── conversation_members ───────────────────────────────────
-- -- Members see who else is in their conversations.
-- create policy conversation_members_select_member on conversation_members for select
--   using (is_member(conversation_id));
--
-- -- Adding a member: the row's own creator (self-adding, e.g. joining a
-- -- community), the conversation's creator (populating the initial member
-- -- list right after creating it — is_member/is_owner would both still be
-- -- false at that instant, since this is the row that would make them
-- -- true), or an existing owner adding someone later.
-- create policy conversation_members_insert_creator on conversation_members for insert
--   with check (
--     user_id = current_profile_id()
--     or exists (
--       select 1 from conversations c
--       where c.id = conversation_members.conversation_id
--         and c.created_by = current_profile_id()
--     )
--     or is_owner(conversation_id)
--   );
--
-- -- Each user updates only their own membership row (star, archive, read,
-- -- and LIME-34's cleared_at — "delete for me" is just another column on
-- -- this same row, so it needs no policy of its own).
-- create policy conversation_members_update_self on conversation_members for update
--   using (user_id = current_profile_id());
--
-- -- ── messages ───────────────────────────────────────────────
-- -- LIME-34: this does NOT filter out a message the reader has "deleted
-- -- for me" (created_at <= their own cleared_at) — that hiding is a
-- -- store/UI-level read filter (LimeStore.listMessages), not RLS, since a
-- -- deleted-for-me message still needs to exist and be selectable for
-- -- everyone else in the conversation. A production RLS policy that also
-- -- enforced this at the database level would need its own per-row
-- -- subquery against the reader's conversation_members.cleared_at —
-- -- left as a note for whoever builds SupabaseAdapter, not written here,
-- -- since nothing today requires the guarantee to hold below the UI.
-- create policy messages_select_member on messages for select
--   using (is_member(conversation_id));
--
-- -- Community messages are readable by any authenticated user, matching
-- -- the community's own public-read select policy above — today only the
-- -- conversation row itself was public; without this, a non-member could
-- -- see that a community exists but not what's said in it.
-- create policy messages_select_community on messages for select
--   using (exists (
--     select 1 from conversations c
--     where c.id = messages.conversation_id and c.type = 'community' and c.deleted_at is null
--   ));
--
-- -- Members insert messages only into conversations they belong to, as
-- -- themselves — checking membership alone (LIME-24a-fix's own version)
-- -- would still let a member insert a message with someone ELSE's
-- -- sender_id (found in plot's re-review of that brief).
-- create policy messages_insert_member on messages for insert
--   with check (is_member(conversation_id) and sender_id = current_profile_id());
--
-- -- Not used by the app yet (there's no edit-message or delete-message UI
-- -- today), but the intent is decided now rather than left undefined:
-- -- you may only ever change or remove your own messages.
-- create policy messages_update_self on messages for update
--   using (sender_id = current_profile_id());
-- create policy messages_delete_self on messages for delete
--   using (sender_id = current_profile_id());
--
-- -- ── message_reactions ──────────────────────────────────────
-- create policy message_reactions_select_member on message_reactions for select
--   using (exists (
--     select 1 from messages m
--     where m.id = message_reactions.message_id and is_member(m.conversation_id)
--   ));
--
-- -- Insert/delete of your own rows only — and only into a conversation
-- -- you're actually a member of (matching the reactor rule above: you
-- -- can't react to something you can't see).
-- create policy message_reactions_insert_self on message_reactions for insert
--   with check (
--     user_id = current_profile_id()
--     and exists (
--       select 1 from messages m
--       where m.id = message_reactions.message_id and is_member(m.conversation_id)
--     )
--   );
-- create policy message_reactions_delete_self on message_reactions for delete
--   using (user_id = current_profile_id());
--
-- -- ── message_attachments ─────────────────────────────────────
-- -- Same shape as message_reactions_select_member above: readable by
-- -- anyone who can see the parent message.
-- create policy message_attachments_select_member on message_attachments for select
--   using (exists (
--     select 1 from messages m
--     where m.id = message_attachments.message_id and is_member(m.conversation_id)
--   ));
--
-- -- Inserted only alongside a message you're the sender of, in a
-- -- conversation you're a member of — mirrors messages_insert_member's own
-- -- sender_id check rather than trusting message_id membership alone.
-- create policy message_attachments_insert_self on message_attachments for insert
--   with check (exists (
--     select 1 from messages m
--     where m.id = message_attachments.message_id
--       and is_member(m.conversation_id)
--       and m.sender_id = current_profile_id()
--   ));
--
-- -- ── link_previews (LIME-44) ──────────────────────────────────
-- -- Not scoped to is_member at all — unlike every table above, a row
-- -- here isn't sensitive per-conversation data, just public metadata
-- -- about a URL (its own title/description/image), readable by anyone
-- -- signed in, regardless of which conversation (if any) first linked
-- -- it. Writes only ever come from the unfurl() Edge Function itself
-- -- (service-role, bypassing RLS entirely) — no insert/update policy for
-- -- ordinary authenticated users at all, since nothing in this app ever
-- -- writes a preview directly; the client only ever reads one.
-- alter table link_previews enable row level security;
-- create policy link_previews_select_authenticated on link_previews for select
--   using (auth.role() = 'authenticated');
--
-- -- ── user_settings (LIME-45) ──────────────────────────────────
-- -- Owner only, both ways — nobody else has any reason to read or write
-- -- another user's default background.
-- alter table user_settings enable row level security;
-- create policy user_settings_select_self on user_settings for select
--   using (user_id = current_profile_id());
-- create policy user_settings_upsert_self on user_settings for insert
--   with check (user_id = current_profile_id());
-- create policy user_settings_update_self on user_settings for update
--   using (user_id = current_profile_id());
