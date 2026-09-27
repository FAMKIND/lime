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
  id            text primary key,
  display_name  text not null,
  email         text not null unique,
  role          text,
  pronouns      text,
  school        text,
  grade_levels  text[],
  subjects      text[],
  bio           text,
  timezone      text,
  status        text not null default 'offline' check (status in ('online', 'offline', 'busy')),
  avatar_url    text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
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
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

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
  last_read_at     timestamptz,
  joined_at        timestamptz not null default now(),
  primary key (conversation_id, user_id)
);

-- ── messages ─────────────────────────────────────────────────
create table messages (
  id               text primary key,
  conversation_id  text not null references conversations(id) on delete cascade,
  sender_id        text not null references profiles(id),
  content          text,
  type             text not null check (type in ('text', 'voice', 'location', 'image')),
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

-- FLAGGED — inconsistent with seed-data/seed.ts as it exists today:
-- seed.ts's reactor selection (`messages.filter(m => m.conversation_id
-- === msg.conversation_id).map(m => m.sender_id).slice(0, reaction.count)`)
-- does not deduplicate sender_id before slicing. Confirmed against the
-- real seed: conv-001's msg-006 carries a `{emoji: "😍", count: 5}`
-- reaction, and the first 5 messages in conv-001 (file order) are sent by
-- teacher-002, teacher-001, teacher-002, teacher-001, teacher-002 — only 2
-- distinct senders. Run as written, seed.ts would attempt to insert
-- (msg-006, teacher-002, "😍") three times and (msg-006, teacher-001,
-- "😍") twice, violating this table's own primary key. Whoever runs a real
-- seed against this schema needs to dedupe reactors before slicing, e.g.
-- `[...new Set(reactors)].slice(0, reaction.count)` — not fixed here
-- (seed-data/seed.ts is out of this brief's scope), but LIME-24b's local
-- adapter, which production-ready principle 4 requires to use "seed.ts's
-- exact reactor algorithm, so local and database seeds match," needs to
-- apply that same dedupe rather than reproducing the bug locally too.

-- ── Row-level security (draft, not yet enabled) ──────────────
-- Left as comments — RLS isn't turned on until Supabase actually backs
-- this app (the switch checklist in docs/data-model.md covers that step).
-- Written down now so 24b's local `can(action, conversation)` helper has
-- a real target to match, not just a guess.
--
-- alter table conversations enable row level security;
-- alter table conversation_members enable row level security;
-- alter table messages enable row level security;
-- alter table message_reactions enable row level security;
--
-- -- Members read the conversations and messages they belong to.
-- create policy conversations_select_member on conversations for select
--   using (exists (
--     select 1 from conversation_members m
--     where m.conversation_id = conversations.id and m.user_id = auth.uid()
--   ));
-- create policy messages_select_member on messages for select
--   using (exists (
--     select 1 from conversation_members m
--     where m.conversation_id = messages.conversation_id and m.user_id = auth.uid()
--   ));
--
-- -- Members insert messages only into conversations they belong to.
-- create policy messages_insert_member on messages for insert
--   with check (exists (
--     select 1 from conversation_members m
--     where m.conversation_id = messages.conversation_id and m.user_id = auth.uid()
--   ));
--
-- -- Only the owner renames or soft-deletes a conversation.
-- create policy conversations_update_owner on conversations for update
--   using (exists (
--     select 1 from conversation_members m
--     where m.conversation_id = conversations.id and m.user_id = auth.uid() and m.role = 'owner'
--   ));
--
-- -- Each user updates only their own membership row (star, archive, read).
-- create policy conversation_members_update_self on conversation_members for update
--   using (user_id = auth.uid());
--
-- -- Communities are readable by any authenticated user, and joinable
-- -- (an insert into conversation_members for oneself, once communities go
-- -- live in LIME-28 — the exact join-eligibility rule isn't decided yet).
-- create policy conversations_select_community on conversations for select
--   using (type = 'community');
