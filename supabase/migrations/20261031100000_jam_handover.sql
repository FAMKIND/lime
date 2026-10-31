-- LIME-275: a band's publishing can be handed to another owner. The current writer OFFERS (one offer per jam); the new writer ACCEPTS with their own session, so nobody
-- has a band pushed on them. Accepting changes the page's writer, and moves the ownership of the band's post ciphertext (blobs of class `jam`) with it, so the old writer's
-- later account deletion or quota no longer touches the band, and ending the band works for the new writer. Nothing here is readable by an app user: the function
-- `jam-page` is the only caller (service role).
create table public.jam_handovers (
  jam_id      uuid primary key references public.jams (jam_id) on delete cascade,
  from_writer uuid not null,
  to_writer   uuid not null references auth.users (id) on delete cascade,
  offered_at  timestamptz not null default now(),
  check (from_writer <> to_writer)
);
create index jam_handovers_by_new_writer on public.jam_handovers (to_writer);
alter table public.jam_handovers enable row level security;
revoke all on public.jam_handovers from public, anon, authenticated;
grant select, insert, update, delete on public.jam_handovers to service_role;

-- Atomic: the writer changes, the blobs follow, the offer goes. False when there is no such offer for `p_to`, or the jam ended, was taken down, or changed hands meanwhile.
create or replace function public.jam_handover_accept(p_jam uuid, p_to uuid) returns boolean
language plpgsql security definer set search_path = public as $$
declare
  o record;
begin
  select * into o from public.jam_handovers where jam_id = p_jam and to_writer = p_to for update;
  if not found then
    return false;
  end if;
  -- created_at moves to now: the band must not become the new writer's OLDEST jam, which is the one that counts as their own profile space (LIME-254b, LIME-281).
  update public.jams set writer_id = p_to, created_at = now() where jam_id = p_jam and writer_id = o.from_writer and ended_at is null and taken_down_at is null;
  if not found then
    delete from public.jam_handovers where jam_id = p_jam;
    return false;
  end if;
  update public.blobs set owner = p_to where jam_id = p_jam and class = 'jam' and owner = o.from_writer;
  delete from public.jam_handovers where jam_id = p_jam;
  return true;
end;
$$;
revoke all on function public.jam_handover_accept(uuid, uuid) from public, anon, authenticated;
grant execute on function public.jam_handover_accept(uuid, uuid) to service_role;
