-- LIME-284c2: the launch list behind limemessenger.com's "Notify me". Double opt-in (a confirm email), one optional "I teach in" answer, one-click leave.
-- It holds exactly what the page asked for and nothing about the visitor: no address, no user agent, no referrer (the rate limit counts a keyed hash, never an address).
-- Only the Edge functions `waitlist-*` (the service role) can read or write it.
--
-- To count signups (staging: `supabase db query --linked "<query>"`, or `supabase/waitlist-count.sh`):
--   select list, count(*) filter (where confirmed_at is not null) as confirmed, count(*) filter (where confirmed_at is null) as waiting_to_confirm from public.waitlist group by list order by list;
--   select coalesce(teaches, '(no answer)') as teaches, count(*) from public.waitlist where list = 'launch' and confirmed_at is not null group by 1 order by 2 desc;
create table public.waitlist (
  email        text        not null check (email = lower(email) and length(email) between 3 and 254),
  list         text        not null check (list in ('launch', 'android')),
  teaches      text        check (teaches in ('k12', 'higher_ed', 'studio_community', 'other')),
  created_at   timestamptz not null default now(),
  confirmed_at timestamptz,
  token        text        not null unique,   -- random: it confirms, records the tap and leaves; it is the only way back to a row
  primary key (email, list)
);
alter table public.waitlist enable row level security;
revoke all on public.waitlist from public, anon, authenticated;
grant select, insert, update, delete on public.waitlist to service_role;

-- An address nobody confirmed is deleted after 7 days (daily, like the 30-day mailbox expiry).
create or replace function public.sweep_waitlist() returns integer
language plpgsql security definer set search_path = public as $$
declare
  gone integer;
begin
  delete from public.waitlist where confirmed_at is null and created_at < now() - interval '7 days';
  get diagnostics gone = row_count;
  return gone;
end;
$$;
revoke all on function public.sweep_waitlist() from public, anon, authenticated;
grant execute on function public.sweep_waitlist() to service_role;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    if exists (select 1 from cron.job where jobname = 'lime-waitlist-sweep') then
      perform cron.unschedule('lime-waitlist-sweep');
    end if;
    perform cron.schedule('lime-waitlist-sweep', '41 3 * * *', 'select public.sweep_waitlist()');
  else
    raise notice 'pg_cron is not enabled here: schedule select public.sweep_waitlist() daily another way';
  end if;
end;
$$;
