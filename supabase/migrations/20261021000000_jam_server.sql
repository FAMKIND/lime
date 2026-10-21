-- LIME-187: the server side of jam (docs/jam.md).
--
-- 1. Jam posts are stored once as CIPHERTEXT blobs (AES-256-GCM, the key is in the end-to-end encrypted post notice and never reaches the
--    server), kept for the life of the jam, and downloaded by their unguessable id WITHOUT a session (`jam-blob-get`), so a download carries an
--    IP address and no account. They live in the same private `blobs` bucket and table, in a new retention class `jam` (no expiry: `blob-sweep`
--    only removes rows that have an `expires_at`). A per-writer quota applies to the class on its own.
-- 2. `jams` is a jam's public page (title, about, topics, post count). It is the only readable-by-the-server part of a jam; posts are not.

alter table public.blobs
  add column class  text not null default 'blob' check (class in ('blob', 'jam')),
  add column jam_id uuid;
create index blobs_by_jam on public.blobs (jam_id) where jam_id is not null;
alter table public.blobs add constraint blobs_jam_class check ((class = 'jam') = (jam_id is not null));
alter table public.blobs add constraint blobs_jam_never_expires check (class <> 'jam' or expires_at is null);

create table public.jams (
  jam_id     uuid primary key,
  writer_id  uuid not null references auth.users (id) on delete cascade,
  title      text not null check (char_length(title) between 1 and 60),
  about      text not null default '' check (char_length(about) <= 500),
  topics     text[] not null default '{}' check (cardinality(topics) <= 8),
  post_count integer not null default 0 check (post_count >= 0),
  created_at timestamptz not null default now(),
  ended_at   timestamptz
);
create index jams_by_writer on public.jams (writer_id);

alter table public.jams enable row level security;
-- Readable by any signed-in user (like `profiles`); writable by the writer only. The app reaches the table through the `jam-page` function.
create policy jams_read on public.jams for select to authenticated using (true);
create policy jams_write_own on public.jams for insert to authenticated with check (writer_id = auth.uid());
create policy jams_update_own on public.jams for update to authenticated using (writer_id = auth.uid()) with check (writer_id = auth.uid());
create policy jams_delete_own on public.jams for delete to authenticated using (writer_id = auth.uid());
revoke all on public.jams from public, anon;
grant select, insert, update, delete on public.jams to authenticated;
grant select, insert, update, delete on public.jams to service_role;

-- The bytes and count a user holds in one retention class (PostgREST would cut a plain select at 1,000 rows).
create function public.blob_usage(p_owner uuid, p_class text, p_except uuid)
returns table (bytes bigint, items bigint)
language sql stable security definer set search_path = public as $$
  select coalesce(sum(size), 0)::bigint, count(*)::bigint from public.blobs where owner = p_owner and class = p_class and id <> p_except;
$$;
revoke all on function public.blob_usage(uuid, text, uuid) from public, anon, authenticated;
grant execute on function public.blob_usage(uuid, text, uuid) to service_role;
