-- users-lookup (LIME-93): the smallest slice of the directory. An exact, case-insensitive email
-- match, authenticated and rate-limited, returning the user id only. It never lists.
--
-- Same privilege model as the rest: only service_role (the Edge Function) may call it.

create function public.lookup_user_id_by_email(p_email text)
returns uuid
language sql
stable
security definer
set search_path = auth, public
as $$
  select id from auth.users where lower(email) = lower(p_email) limit 1;
$$;

revoke all on function public.lookup_user_id_by_email(text) from public, anon, authenticated;
grant execute on function public.lookup_user_id_by_email(text) to service_role;
