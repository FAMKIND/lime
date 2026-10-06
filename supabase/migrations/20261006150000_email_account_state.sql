-- LIME-94-fix: asking for a sign-up code twice (the code screen's "Resend") must work. The first
-- request makes an unconfirmed Auth user, so "does this email have an account?" has to tell an
-- unconfirmed address (still new: it never proved the email) from a confirmed one.
-- Service role only, like every function here.

create function public.email_account_state(p_email text)
returns text
language sql
stable
security definer
set search_path = auth, public
as $$
  select coalesce(
    (select case when u.email_confirmed_at is null then 'unconfirmed' else 'confirmed' end
       from auth.users u where lower(u.email) = lower(p_email) limit 1),
    'none');
$$;

revoke all on function public.email_account_state(text) from public, anon, authenticated;
grant execute on function public.email_account_state(text) to service_role;
