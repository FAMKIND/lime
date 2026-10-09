-- LIME-98b: the blob store (api-v2.md section 6, "Blobs") and profile photos.
--
-- Two PRIVATE Storage buckets, reached only through Edge Functions (service_role) that hand out
-- short-lived signed URLs; there are no storage policies, so the anon and authenticated roles can read
-- and write nothing directly.
--   public-avatars  plaintext profile photos (JPEG, 1 MiB), readable by any signed-in user through
--                   `avatar` (never anonymously). The server, and signed-in users, can see these.
--   blobs           CIPHERTEXT only (AES-256-GCM, the key never reaches the server). Also the store
--                   for chat attachments later. A contacts-only profile photo lives here.

alter table public.profiles
  add column photo_visibility text not null default 'everyone' check (photo_visibility in ('everyone', 'contacts')),
  -- Set while a public photo exists (milliseconds since the epoch of the last change), else null.
  add column avatar_version   bigint;

-- The row behind each ciphertext blob: who uploaded it (for the quota), how big it is and when it
-- expires. The id is chosen by the client (for a contacts-only photo it is derived from a key the
-- server never sees, so nobody can look it up without that key).
create table public.blobs (
  id           uuid primary key,
  owner        uuid not null references auth.users (id) on delete cascade,
  size         integer not null check (size > 0),
  created_at   timestamptz not null default now(),
  committed_at timestamptz,        -- set once the upload was verified; only then can it be downloaded
  expires_at   timestamptz         -- null: kept until its owner removes it (profile photos)
);
create index blobs_by_owner on public.blobs (owner);
create index blobs_by_expiry on public.blobs (expires_at) where expires_at is not null;

alter table public.blobs enable row level security;
revoke all on public.blobs from public, anon, authenticated;
grant select, insert, update, delete on public.blobs to service_role;

-- The buckets (Supabase Storage). Guarded so a database without the storage schema still migrates.
do $$
begin
  if to_regclass('storage.buckets') is not null then
    insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
    values
      ('public-avatars', 'public-avatars', false, 1048576, array['image/jpeg']),
      ('blobs', 'blobs', false, 26214400, null)
    on conflict (id) do update
      set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;
  end if;
end $$;
