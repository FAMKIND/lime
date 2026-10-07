-- LIME-95-fix: a signed-in account whose phone has new keys (a fresh install, or a sign-out that
-- wiped the old ones) could never register that phone: the account's master key was fixed by its
-- first registration, so every later phone was refused and the account could not message. A fully
-- verified session (password AND emailed code) may now REPLACE the account's keys:
--   * every existing device of the account is revoked (it can no longer fetch, be listed or be sent to);
--   * their unfetched mail and unused one-time keys are deleted (nobody holds the keys to read them);
--   * the master key is replaced;
--   * for each deleted IDENTIFIED item the sender is told, by the hash of the ciphertext they sent
--     (they know it; the server learns nothing new), so their message can show "Not delivered".
--     A sealed item has no known sender, so its sender cannot be told.
-- Contacts who remembered the old master key see "security key changed" and must accept it
-- (docs/api-v2.md section 11, LIME-95-fix). One atomic call; service role only, like every function here.

alter table public.master_keys add column reset_at timestamptz;

-- Senders waiting to hear that something they sent was never delivered: the hash of the outer
-- ciphertext (the same hash the mailbox de-duplicates by), nothing else.
create table public.undelivered_notices (
  id              bigserial primary key,
  sender_user     uuid not null references auth.users (id) on delete cascade,
  ciphertext_hash bytea not null check (octet_length(ciphertext_hash) = 32),
  created_at      timestamptz not null default now()
);
create index undelivered_notices_by_sender on public.undelivered_notices (sender_user);
alter table public.undelivered_notices enable row level security;
revoke all on public.undelivered_notices from public, anon, authenticated;
grant select, insert, update, delete on public.undelivered_notices to service_role;
grant usage, select on sequence public.undelivered_notices_id_seq to service_role;

create function public.reset_account_keys(p_user uuid, p_master text)
returns integer
language plpgsql
set search_path = public
as $$
declare
  v_revoked integer;
begin
  insert into public.undelivered_notices (sender_user, ciphertext_hash)
    select sender_user, ciphertext_hash from public.mailbox_items
     where identified and sender_user is not null
       and to_device in (select device_id from public.devices where user_id = p_user);
  delete from public.mailbox_items
   where to_device in (select device_id from public.devices where user_id = p_user);
  delete from public.one_time_keys
   where device_id in (select device_id from public.devices where user_id = p_user);
  update public.devices set revoked_at = now() where user_id = p_user and revoked_at is null;
  get diagnostics v_revoked = row_count;
  update public.master_keys set public_key = p_master, reset_at = now() where user_id = p_user;
  return v_revoked;
end;
$$;

-- The caller's notices, handed over once (deleted as they are returned).
create function public.take_undelivered(p_user uuid, p_limit integer default 500)
returns setof bytea
language sql
set search_path = public
as $$
  with taken as (
    select id from public.undelivered_notices where sender_user = p_user order by id limit p_limit for update skip locked
  )
  delete from public.undelivered_notices n using taken where n.id = taken.id returning n.ciphertext_hash;
$$;

-- An item that expires unfetched (30 days) is also "not delivered" to an identified sender.
create or replace function public.expire_mailbox_items(p_days integer default 30)
returns bigint
language plpgsql
set search_path = public
as $$
declare
  v_removed bigint;
begin
  insert into public.undelivered_notices (sender_user, ciphertext_hash)
    select sender_user, ciphertext_hash from public.mailbox_items
     where received_at < now() - make_interval(days => p_days) and identified and sender_user is not null;
  delete from public.mailbox_items where received_at < now() - make_interval(days => p_days);
  get diagnostics v_removed = row_count;
  delete from public.rate_limits where window_start < now() - interval '1 day';
  delete from public.code_challenges where sent_at < now() - interval '1 day';
  delete from public.undelivered_notices where created_at < now() - make_interval(days => p_days);
  return v_removed;
end;
$$;

revoke all on function public.reset_account_keys(uuid, text), public.take_undelivered(uuid, integer)
  from public, anon, authenticated;
grant execute on function public.reset_account_keys(uuid, text), public.take_undelivered(uuid, integer) to service_role;
