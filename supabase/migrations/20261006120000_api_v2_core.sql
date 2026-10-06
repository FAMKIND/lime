-- Lime API v2 core (docs/api-v2.md): devices, keys, the sealed mailbox, delivery access, rate limits.
--
-- Only the Edge Functions touch these tables, with the service role. Every table has row-level
-- security on and NO policies, and anon / authenticated get no privileges at all. The staging
-- project was made with "Automatically expose new tables" OFF, so every privilege below is an
-- explicit GRANT to service_role; the same migration behaves the same on the local stack.
--
-- Deliberately absent (api-v2.md section 2): conversations, group names, membership, the senders of
-- sealed messages, message text, reactions. Not built yet: profiles, blobs, backups, calls.

create extension if not exists pg_cron with schema pg_catalog;

-- ---------------------------------------------------------------- keys and devices

create table public.master_keys (
  user_id    uuid primary key references auth.users (id) on delete cascade,
  public_key text not null,                     -- base64 Ed25519 public key
  created_at timestamptz not null default now()
);

create table public.devices (
  device_id        uuid primary key,
  user_id          uuid not null references auth.users (id) on delete cascade,
  identity_key     text not null,               -- base64 Curve25519 public key
  signing_key      text not null,               -- base64 Ed25519 public key
  master_signature text not null,               -- base64 signature by the user's master key
  created_at       timestamptz not null default now(),
  revoked_at       timestamptz
);
create index devices_by_user on public.devices (user_id);

create table public.one_time_keys (
  id         bigserial primary key,
  device_id  uuid not null references public.devices (device_id) on delete cascade,
  key_id     text not null,
  key        text not null,                     -- base64 Curve25519 public key
  created_at timestamptz not null default now(),
  claimed_at timestamptz,
  unique (device_id, key_id)
);
create index one_time_keys_unclaimed on public.one_time_keys (device_id, id) where claimed_at is null;

-- ---------------------------------------------------------------- the mailbox

-- One row per recipient device. Deleted when acknowledged; deleted after 30 days if not.
-- The sender is stored ONLY for an identified send (a stranger's first message); a sealed
-- send leaves no sender anywhere.
create table public.mailbox_items (
  cursor          bigserial primary key,
  to_device       uuid not null references public.devices (device_id) on delete cascade,
  ciphertext      bytea not null check (octet_length(ciphertext) <= 65536),
  ciphertext_hash bytea not null check (octet_length(ciphertext_hash) = 32),  -- SHA-256, for de-duplication
  size            integer not null,
  received_at     timestamptz not null default now(),
  identified      boolean not null default false,
  sender_user     uuid references auth.users (id) on delete set null,
  check (identified or sender_user is null),
  unique (to_device, ciphertext_hash)
);
create index mailbox_items_by_device on public.mailbox_items (to_device, cursor);
create index mailbox_items_by_age on public.mailbox_items (received_at);

-- ---------------------------------------------------------------- sealed access

-- SHA-256 of the user's current access key. Never the key (api-v2.md section 2, "delivery_keys").
create table public.delivery_access (
  user_id         uuid primary key references auth.users (id) on delete cascade,
  access_key_hash bytea not null check (octet_length(access_key_hash) = 32),
  updated_at      timestamptz not null default now()
);

-- ---------------------------------------------------------------- rate limits

create table public.rate_limits (
  bucket       text not null,
  window_start timestamptz not null,
  count        integer not null default 0,
  primary key (bucket, window_start)
);

-- ---------------------------------------------------------------- functions

-- Fixed-window limiter. Returns true when the bucket is still within `p_limit` after adding `p_cost`.
create function public.take_rate_limit(p_bucket text, p_cost integer, p_limit integer, p_window_seconds integer)
returns boolean
language plpgsql
set search_path = public
as $$
declare
  v_window timestamptz := to_timestamp(floor(extract(epoch from now()) / p_window_seconds) * p_window_seconds);
  v_count integer;
begin
  insert into public.rate_limits (bucket, window_start, count)
  values (p_bucket, v_window, p_cost)
  on conflict (bucket, window_start) do update set count = public.rate_limits.count + p_cost
  returning count into v_count;
  return v_count <= p_limit;
end;
$$;

create function public.remaining_one_time_keys(p_device uuid)
returns integer
language sql
stable
set search_path = public
as $$
  select count(*)::integer from public.one_time_keys where device_id = p_device and claimed_at is null;
$$;

-- Atomically claims one unclaimed one-time key per active device of a user (a key is claimed once).
create function public.claim_one_time_keys_for_user(p_user uuid)
returns table (device_id uuid, key_id text, key text)
language plpgsql
set search_path = public
as $$
declare
  d record;
  k record;
begin
  for d in
    select dv.device_id from public.devices dv where dv.user_id = p_user and dv.revoked_at is null order by dv.created_at
  loop
    update public.one_time_keys o
       set claimed_at = now()
     where o.id = (
       select o2.id from public.one_time_keys o2
        where o2.device_id = d.device_id and o2.claimed_at is null
        order by o2.id
        limit 1
        for update skip locked)
    returning o.key_id, o.key into k;
    device_id := d.device_id;
    key_id := k.key_id;
    key := k.key;
    return next;
    k := null;
  end loop;
end;
$$;

-- The 30-day expiry (and old rate-limit windows). Returns how many mailbox items it removed.
create function public.expire_mailbox_items(p_days integer default 30)
returns bigint
language plpgsql
set search_path = public
as $$
declare
  v_removed bigint;
begin
  delete from public.mailbox_items where received_at < now() - make_interval(days => p_days);
  get diagnostics v_removed = row_count;
  delete from public.rate_limits where window_start < now() - interval '1 day';
  return v_removed;
end;
$$;

-- ---------------------------------------------------------------- privileges: service_role only

alter table public.master_keys     enable row level security;
alter table public.devices         enable row level security;
alter table public.one_time_keys   enable row level security;
alter table public.mailbox_items   enable row level security;
alter table public.delivery_access enable row level security;
alter table public.rate_limits     enable row level security;
-- (No policies: with RLS on and none defined, nothing is visible to a role that is subject to RLS.)

revoke all on public.master_keys, public.devices, public.one_time_keys, public.mailbox_items,
              public.delivery_access, public.rate_limits
  from public, anon, authenticated;
revoke all on sequence public.one_time_keys_id_seq, public.mailbox_items_cursor_seq
  from public, anon, authenticated;
revoke all on function public.take_rate_limit(text, integer, integer, integer),
                       public.remaining_one_time_keys(uuid),
                       public.claim_one_time_keys_for_user(uuid),
                       public.expire_mailbox_items(integer)
  from public, anon, authenticated;

grant select, insert, update, delete on public.master_keys, public.devices, public.one_time_keys,
      public.mailbox_items, public.delivery_access, public.rate_limits to service_role;
grant usage, select on sequence public.one_time_keys_id_seq, public.mailbox_items_cursor_seq to service_role;
grant execute on function public.take_rate_limit(text, integer, integer, integer),
                          public.remaining_one_time_keys(uuid),
                          public.claim_one_time_keys_for_user(uuid),
                          public.expire_mailbox_items(integer)
  to service_role;

-- ---------------------------------------------------------------- the 30-day expiry job (daily)

do $$
begin
  if exists (select 1 from cron.job where jobname = 'lime-expire-mailbox') then
    perform cron.unschedule('lime-expire-mailbox');
  end if;
  perform cron.schedule('lime-expire-mailbox', '17 3 * * *', 'select public.expire_mailbox_items(30)');
end;
$$;
