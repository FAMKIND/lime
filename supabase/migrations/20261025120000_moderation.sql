-- LIME-191: reports, a moderation queue, and takedowns.
-- A report is sealed on the reporter's phone to the server's MODERATION key (only `moderation-open` can open it). The row keeps what the queue needs in
-- the clear (the reason, the kind of subject, urgency, status); the included item, the note and the subject's ids are inside the sealed payload.
-- Nobody reads these tables from a client: RLS is on with no policy; only the functions (service role) touch them.
create table public.moderation_reports (
  id          uuid primary key default gen_random_uuid(),
  reporter    uuid not null references auth.users (id) on delete cascade,
  kind        text not null check (kind in ('message', 'person', 'group', 'jam_post', 'comment', 'jam', 'org', 'profile_item')),
  reason      text not null check (reason in ('harassment', 'spam', 'impersonation', 'inappropriate', 'child_safety', 'hate_violence', 'other')),
  urgent      boolean not null default false,
  sealed      bytea not null,
  status      text not null default 'open' check (status in ('open', 'actioned', 'dismissed')),
  created_at  timestamptz not null default now(),
  resolved_at timestamptz,
  resolved_by uuid references auth.users (id) on delete set null
);
create index moderation_reports_queue on public.moderation_reports (status, urgent desc, created_at);
create index moderation_reports_by_reporter on public.moderation_reports (reporter, created_at);
alter table public.moderation_reports enable row level security;

create table public.moderators (
  user_id    uuid primary key references auth.users (id) on delete cascade,
  created_at timestamptz not null default now()
);
alter table public.moderators enable row level security;

-- Every action a moderator takes: who, when, what, on what (the log is kept as long as the reports are).
create table public.moderation_actions (
  id         uuid primary key default gen_random_uuid(),
  report_id  uuid references public.moderation_reports (id) on delete set null,
  moderator  uuid references auth.users (id) on delete set null,
  action     text not null,
  target     text not null default '',
  note       text not null default '',
  created_at timestamptz not null default now()
);
create index moderation_actions_by_report on public.moderation_actions (report_id);
alter table public.moderation_actions enable row level security;

-- Takedowns the server can do.
alter table public.blobs add column hidden_at timestamptz;                 -- a hidden jam post: jam-blob-get refuses it
alter table public.jams add column taken_down_at timestamptz;              -- a page taken down: jam-page answers 410

create table public.account_suspensions (
  user_id    uuid primary key references auth.users (id) on delete cascade,
  reason     text not null default '',
  created_at timestamptz not null default now(),
  created_by uuid references auth.users (id) on delete set null
);
alter table public.account_suspensions enable row level security;

-- Reports are kept 180 days after they are resolved, then deleted (with their actions).
create or replace function public.sweep_moderation() returns integer language plpgsql security definer set search_path = public as $$
declare removed integer;
begin
  delete from public.moderation_actions where report_id in (select id from public.moderation_reports where resolved_at < now() - interval '180 days');
  delete from public.moderation_reports where resolved_at < now() - interval '180 days';
  get diagnostics removed = row_count;
  return removed;
end $$;
revoke all on function public.sweep_moderation() from public, anon, authenticated;

revoke all on public.moderation_reports, public.moderators, public.moderation_actions, public.account_suspensions from public, anon, authenticated;
grant select, insert, update, delete on public.moderation_reports, public.moderators, public.moderation_actions, public.account_suspensions to service_role;
grant execute on function public.sweep_moderation() to service_role;
