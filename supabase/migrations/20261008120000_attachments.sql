-- LIME-98c: encrypted attachments (photos, files; voice and video next) on top of the LIME-98b blob store.
--
-- An attachment is encrypted on the device in chunks (AES-256-GCM, a random key per file that travels
-- only inside the encrypted message) and uploaded chunk by chunk through short-lived signed URLs into
-- the private `blobs` bucket under `a/<id>/<n>`. The server sees ciphertext sizes and timing, nothing
-- else. It is deleted once every recipient has fetched it (the sender declares how many recipients
-- there are), or after 30 days, whichever is first, by a sweep that runs every 15 minutes.

create table public.attachments (
  id           uuid primary key,
  owner        uuid not null references auth.users (id) on delete cascade,
  size         bigint not null check (size > 0),              -- total ciphertext bytes
  chunks       integer not null check (chunks between 1 and 60),
  recipients   integer not null check (recipients between 1 and 100),
  created_at   timestamptz not null default now(),
  committed_at timestamptz,
  expires_at   timestamptz not null default (now() + interval '30 days')
);
create index attachments_by_owner on public.attachments (owner);
create index attachments_by_expiry on public.attachments (expires_at);

-- Who has fetched an attachment (one row per person), so it can be deleted after the last recipient.
create table public.attachment_fetches (
  attachment_id uuid not null references public.attachments (id) on delete cascade,
  user_id       uuid not null,
  fetched_at    timestamptz not null default now(),
  primary key (attachment_id, user_id)
);

alter table public.attachments enable row level security;
alter table public.attachment_fetches enable row level security;
revoke all on public.attachments, public.attachment_fetches from public, anon, authenticated;
grant select, insert, update, delete on public.attachments, public.attachment_fetches to service_role;

-- ---------------------------------------------------------------- the sweep (every 15 minutes)
-- pg_cron calls `blob-sweep` (an Edge Function that deletes the Storage objects, which SQL must not do) through
-- pg_net. Where it is and the secret it presents live in `sweep_target`, written once per environment by
-- `supabase/schedule-sweep.sh` (never by a migration, because the URL and the secret differ per project).

create table public.sweep_target (
  id     integer primary key check (id = 1),
  url    text not null,
  secret text not null
);
alter table public.sweep_target enable row level security;
revoke all on public.sweep_target from public, anon, authenticated;
grant select, insert, update, delete on public.sweep_target to service_role;

do $$
begin
  create extension if not exists pg_net with schema extensions;
  create extension if not exists pg_cron;
exception when others then
  raise notice 'pg_cron / pg_net could not be enabled here (%): the blob sweep must be scheduled another way', sqlerrm;
end $$;

create or replace function public.run_blob_sweep() returns void
language plpgsql security definer set search_path = public, extensions
as $$
declare
  target record;
begin
  select * into target from public.sweep_target where id = 1;
  if not found then
    return;
  end if;
  perform net.http_post(
    url := target.url,
    headers := jsonb_build_object('content-type', 'application/json', 'x-sweep-secret', target.secret),
    body := '{}'::jsonb
  );
end $$;
revoke all on function public.run_blob_sweep() from public, anon, authenticated;
grant execute on function public.run_blob_sweep() to service_role;

do $$
begin
  if to_regnamespace('cron') is not null then
    perform cron.schedule('lime-blob-sweep', '*/15 * * * *', 'select public.run_blob_sweep()');
  end if;
end $$;
