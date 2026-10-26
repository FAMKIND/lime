-- LIME-113: delete your account (App Store rule 5.1.1(v)).
-- `deleted_accounts` is the deletion log: a hash of the user id and the time, nothing else. `held_usernames` keeps a deleted account's username for
-- 30 days so nobody can take it to impersonate them; the email can sign up again at once. Everything else tied to the account goes with the auth user
-- (their rows cascade) or is deleted by `delete_account_rows` / the `account-delete` function (Storage objects, mailbox items they sent).
create table public.deleted_accounts (
  id_hash    text primary key,
  deleted_at timestamptz not null default now()
);
alter table public.deleted_accounts enable row level security;

create table public.held_usernames (
  username   text primary key,                 -- lower case
  held_until timestamptz not null
);
alter table public.held_usernames enable row level security;

-- The part of the deletion that is one transaction: hold the username, write the log row, delete what does not cascade.
create function public.delete_account_rows(p_user uuid, p_hash text) returns void
language plpgsql security definer set search_path = public as $$
begin
  insert into public.held_usernames (username, held_until)
    select lower(username), now() + interval '30 days' from public.profiles where user_id = p_user and username is not null
    on conflict (username) do update set held_until = excluded.held_until;
  insert into public.deleted_accounts (id_hash) values (p_hash) on conflict do nothing;
  delete from public.mailbox_items where sender_user = p_user;
  delete from public.code_challenges where challenge_key like '%:' || p_user::text;
  delete from public.rate_limits where bucket like '%' || p_user::text;
end $$;

create function public.sweep_held_usernames() returns integer
language plpgsql security definer set search_path = public as $$
declare removed integer;
begin
  delete from public.held_usernames where held_until < now();
  get diagnostics removed = row_count;
  return removed;
end $$;

revoke all on public.deleted_accounts, public.held_usernames from public, anon, authenticated;
grant select, insert, update, delete on public.deleted_accounts, public.held_usernames to service_role;
revoke all on function public.delete_account_rows(uuid, text), public.sweep_held_usernames() from public, anon, authenticated;
grant execute on function public.delete_account_rows(uuid, text), public.sweep_held_usernames() to service_role;
