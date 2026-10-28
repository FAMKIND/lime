-- LIME-210a: open posts (docs/jam.md section 13). A post a writer chooses to make readable by everyone on lime: an explicit, per-post choice that makes
-- THAT post readable by the server (a subscribers-only post stays end-to-end encrypted and never comes here). One store for teachers and (later) lime's
-- own posts (`author_kind`). The writer's device signs the row; the signature and the device certificate are checked on publish and again by phones.

-- Server flags: `open_posts_enabled` stays OFF until the report path (LIME-191) and the student-privacy check (LIME-210d) are live; publishing is
-- refused while it is off. Only the service role can change it (supabase db / the dashboard), never an app.
create table public.server_flags (
  name    text primary key,
  enabled boolean not null default false,
  changed_at timestamptz not null default now()
);
insert into public.server_flags (name, enabled) values ('open_posts_enabled', false) on conflict do nothing;
alter table public.server_flags enable row level security;
revoke all on public.server_flags from public, anon, authenticated;
grant select, insert, update, delete on public.server_flags to service_role;

create sequence public.open_posts_seq;

create table public.open_posts (
  post_id      uuid primary key,
  author_kind  text not null check (author_kind in ('person', 'org')),
  author_id    uuid not null,
  jam_id       uuid not null,
  kind         text not null check (kind in ('quick', 'article', 'record')),
  title        text not null default '',
  subtitle     text not null default '',
  excerpt      text not null default '',
  topics       text[] not null default '{}',
  files        jsonb not null default '[]',      -- the public file ids this post uses
  series       jsonb,
  preview_of   uuid,                             -- the encrypted full post this open part is the Preview of (210b)
  has_rest     boolean not null default false,
  version      integer not null default 1,
  payload      text,                             -- the exact signed text (JSON); null for a tombstone
  signature    text,
  cert         jsonb,
  created_at   timestamptz not null default now(),
  edited_at    timestamptz,
  deleted_at   timestamptz,
  taken_down_at timestamptz,
  seq          bigint not null default nextval('public.open_posts_seq')
);
create unique index open_posts_by_seq on public.open_posts (seq);
create index open_posts_by_author on public.open_posts (author_id, created_at desc);
alter table public.open_posts enable row level security;
revoke all on public.open_posts from public, anon, authenticated;
grant select, insert, update, delete on public.open_posts to service_role;

-- The public file class: unencrypted, no expiry while the post exists, a plain cacheable URL, removed with the post.
create table public.open_files (
  id           uuid primary key,
  owner        uuid not null references auth.users (id) on delete cascade,
  post_id      uuid,
  size         integer not null check (size > 0),
  mime         text not null,
  created_at   timestamptz not null default now(),
  committed_at timestamptz
);
create index open_files_by_owner on public.open_files (owner);
create index open_files_by_post on public.open_files (post_id);
alter table public.open_files enable row level security;
revoke all on public.open_files from public, anon, authenticated;
grant select, insert, update, delete on public.open_files to service_role;

do $$
begin
  if to_regclass('storage.buckets') is not null then
    insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
    values ('open-files', 'open-files', true, 25165824, null)
    on conflict (id) do update set public = true, file_size_limit = excluded.file_size_limit;
  end if;
end $$;

create function public.nextval_open_posts() returns bigint language sql as $$ select nextval('public.open_posts_seq') $$;
revoke all on function public.nextval_open_posts() from public, anon, authenticated;
grant execute on function public.nextval_open_posts() to service_role;
