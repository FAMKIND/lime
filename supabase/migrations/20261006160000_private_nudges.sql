-- LIME-95: the per-device Realtime "new items" nudge becomes a PRIVATE channel, and a client may
-- subscribe only to the channel of a device that is its own (and not revoked), and only from a
-- session that has passed both sign-in steps. The nudge carries no content either way; this stops
-- anyone with the public key and a device id from watching when that device receives mail.

create or replace function public.can_receive_device_nudges(p_topic text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
      from public.devices d
      join public.auth_proofs p on p.user_id = d.user_id
     where p_topic = 'device:' || d.device_id::text
       and d.user_id = auth.uid()
       and d.revoked_at is null
       and p.session_id = nullif(auth.jwt() ->> 'session_id', '')::uuid
       and p.password_ok and p.code_ok
  );
$$;

revoke all on function public.can_receive_device_nudges(text) from public, anon;
grant execute on function public.can_receive_device_nudges(text) to authenticated;

-- Receiving broadcasts on a topic needs a SELECT policy on realtime.messages.
drop policy if exists "a device's owner receives its nudges" on realtime.messages;
create policy "a device's owner receives its nudges"
  on realtime.messages for select to authenticated
  using ( realtime.messages.extension = 'broadcast' and public.can_receive_device_nudges((select realtime.topic())) );
