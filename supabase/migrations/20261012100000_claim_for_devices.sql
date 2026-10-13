-- LIME-120: a sender claims one-time keys only for the devices it has no Olm session with (it used to burn one for every
-- active device of the user on every claim). Same atomic, once-only claim as claim_one_time_keys_for_user, limited to the
-- devices asked for (and still only active ones).
create function public.claim_one_time_keys_for_devices(p_user uuid, p_devices uuid[])
returns table (device_id uuid, key_id text, key text)
language plpgsql
set search_path = public
as $$
declare
  d record;
  k record;
begin
  for d in
    select dv.device_id from public.devices dv
     where dv.user_id = p_user and dv.revoked_at is null and dv.device_id = any(p_devices)
     order by dv.created_at
  loop
    k := null;
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
  end loop;
end;
$$;

revoke all on function public.claim_one_time_keys_for_devices(uuid, uuid[]) from public, anon, authenticated;
grant execute on function public.claim_one_time_keys_for_devices(uuid, uuid[]) to service_role;
