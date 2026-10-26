-- LIME-113c: the safer order. `account-delete` only marks the account "deleting" (sign-in and every session call refused) and hands the phone a
-- one-time token; the phone sends its quiet notices; `account-delete-confirm` then deletes. If no confirm comes, the sweep finishes the deletion
-- 10 minutes after the phone reported its notices were sent, or 24 hours after the start either way.
create table public.account_deletions (
  user_id         uuid primary key references auth.users (id) on delete cascade,
  token_hash      text not null,
  started_at      timestamptz not null default now(),
  notices_sent_at timestamptz
);
alter table public.account_deletions enable row level security;
revoke all on public.account_deletions from public, anon, authenticated;
grant select, insert, update, delete on public.account_deletions to service_role;

create function public.deleting_accounts_due() returns table (user_id uuid)
language sql security definer set search_path = public as $$
  select user_id from public.account_deletions
  where (notices_sent_at is not null and notices_sent_at < now() - interval '10 minutes') or started_at < now() - interval '24 hours';
$$;
revoke all on function public.deleting_accounts_due() from public, anon, authenticated;
grant execute on function public.deleting_accounts_due() to service_role;
