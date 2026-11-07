-- LIME-287a: sending the launch email and the Android email. `sent_at` records, per row, that its email for the list it is on went out, so a rerun never sends twice.
-- A launch row is deleted 30 days after its launch email (the daily sweep); an Android row is deleted by waitlist-send right after the Android email.
alter table public.waitlist add column sent_at timestamptz;
create index waitlist_unsent on public.waitlist (list, created_at) where confirmed_at is not null and sent_at is null;

create or replace function public.sweep_waitlist() returns integer
language plpgsql security definer set search_path = public as $$
declare
  gone integer;
  more integer;
begin
  delete from public.waitlist where confirmed_at is null and created_at < now() - interval '7 days';
  get diagnostics gone = row_count;
  delete from public.waitlist where list = 'launch' and sent_at is not null and sent_at < now() - interval '30 days';
  get diagnostics more = row_count;
  return gone + more;
end;
$$;
