-- LIME-342a: an account has at most 5 active devices, and a computer can be unlinked (revoked) by a device that holds the master key.
--   * `devices_limit`: a trigger on insert refuses a 6th ACTIVE device (revoked ones do not count); it takes a per-user advisory lock so two
--     registrations at the same moment cannot both pass. `devices-register` turns the error into 409 `too_many_devices`.
--   * `revoke_device(user, device)`: one atomic call, like `reset_account_keys` but for one device: its unfetched mail (and each identified item's
--     sender notice, so their message can show "Not delivered") and unused one-time keys go, and `revoked_at` is set. A revoked device can no longer
--     fetch, be listed or be sent to (every function already refuses a revoked device). Returns false when the device is not this user's or is already
--     revoked. No new column, no device name and no kind is stored: the server learns only which device was revoked.

create function public.devices_limit() returns trigger
language plpgsql
set search_path = public
as $$
begin
  perform pg_advisory_xact_lock(hashtext('devices:' || new.user_id::text));
  if (select count(*) from public.devices where user_id = new.user_id and revoked_at is null) >= 5 then
    raise exception 'too_many_devices' using errcode = 'P0001';
  end if;
  return new;
end;
$$;

create trigger devices_limit before insert on public.devices
  for each row execute function public.devices_limit();

create function public.revoke_device(p_user uuid, p_device uuid)
returns boolean
language plpgsql
set search_path = public
as $$
declare
  v_found integer;
begin
  perform 1 from public.devices where device_id = p_device and user_id = p_user and revoked_at is null for update;
  get diagnostics v_found = row_count;
  if v_found = 0 then
    return false;
  end if;
  insert into public.undelivered_notices (sender_user, ciphertext_hash)
    select sender_user, ciphertext_hash from public.mailbox_items
     where identified and sender_user is not null and to_device = p_device;
  delete from public.mailbox_items where to_device = p_device;
  delete from public.one_time_keys where device_id = p_device;
  update public.devices set revoked_at = now() where device_id = p_device;
  return true;
end;
$$;

revoke all on function public.revoke_device(uuid, uuid) from public, anon, authenticated;
grant execute on function public.revoke_device(uuid, uuid) to service_role;
