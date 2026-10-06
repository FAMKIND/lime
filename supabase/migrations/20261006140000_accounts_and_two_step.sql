-- LIME-94: profiles, and the two-step sign-in (a password AND an emailed code) that a session must
-- pass before it can do anything (docs/api-v2.md section 11).
--
-- Supabase Auth cannot require both a password and an email code on one session (its email code is
-- a sign-in method of its own, not an MFA factor). So the Edge Functions keep a small proof record
-- per Auth session: `password_ok` is set when the function itself checked the password (or set one
-- the person just proved their email for), `code_ok` when the function itself checked the emailed
-- code. A session is **verified** only when both are true, and every function except the sign-in
-- ones requires a verified session. A password-only session and a code-only session can do nothing.
--
-- Same privilege model as before: RLS on, no policies, service_role only.

create table public.profiles (
  user_id          uuid primary key references auth.users (id) on delete cascade,
  display_name     text not null check (char_length(display_name) between 1 and 60),
  username         text,
  school           text check (school is null or char_length(school) <= 120),
  hide_from_search boolean not null default false,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
-- Unique ignoring case; the format rules are the web app's, checked in the Edge Function.
create unique index profiles_username_key on public.profiles (lower(username)) where username is not null;

create table public.auth_proofs (
  session_id  uuid primary key,                -- the Auth session (the JWT's session_id claim)
  user_id     uuid not null references auth.users (id) on delete cascade,
  password_ok boolean not null default false,
  code_ok     boolean not null default false,
  created_at  timestamptz not null default now(),
  verified_at timestamptz
);
create index auth_proofs_by_user on public.auth_proofs (user_id);

-- One row per code that was emailed: how many wrong tries it has had, and when it was sent.
-- challenge_key is 'session:<id>' for a sign-in or 'email:<sha256 of the address>' otherwise.
create table public.code_challenges (
  challenge_key text primary key,
  kind          text not null,
  attempts      integer not null default 0,
  sent_at       timestamptz not null default now()
);

-- A new code was sent: start counting wrong tries again.
create function public.start_code_challenge(p_key text, p_kind text)
returns void
language sql
set search_path = public
as $$
  insert into public.code_challenges (challenge_key, kind, attempts, sent_at)
  values (p_key, p_kind, 0, now())
  on conflict (challenge_key) do update set kind = p_kind, attempts = 0, sent_at = now();
$$;

-- Counts one try. Returns the number of tries used including this one, or max + 1 when the code is
-- already locked (so the caller can refuse without checking the code).
create function public.take_code_attempt(p_key text, p_max integer)
returns integer
language plpgsql
set search_path = public
as $$
declare
  v_attempts integer;
begin
  update public.code_challenges set attempts = attempts + 1
   where challenge_key = p_key and attempts <= p_max
  returning attempts into v_attempts;
  if v_attempts is null then
    return p_max + 1;      -- no such challenge, or already past the limit
  end if;
  return v_attempts;
end;
$$;

-- A username to the account that owns it (exact, ignoring case). Never lists.
create function public.resolve_username(p_username text)
returns table (user_id uuid, email text)
language sql
stable
security definer
set search_path = auth, public
as $$
  select p.user_id, u.email::text
    from public.profiles p join auth.users u on u.id = p.user_id
   where lower(p.username) = lower(p_username)
   limit 1;
$$;

-- ---------------------------------------------------------------- privileges: service_role only

alter table public.profiles        enable row level security;
alter table public.auth_proofs     enable row level security;
alter table public.code_challenges enable row level security;

revoke all on public.profiles, public.auth_proofs, public.code_challenges from public, anon, authenticated;
revoke all on function public.start_code_challenge(text, text), public.take_code_attempt(text, integer),
                       public.resolve_username(text)
  from public, anon, authenticated;

grant select, insert, update, delete on public.profiles, public.auth_proofs, public.code_challenges to service_role;
grant execute on function public.start_code_challenge(text, text), public.take_code_attempt(text, integer),
                          public.resolve_username(text)
  to service_role;

-- Old proof records and spent challenges are housekeeping (the same daily job as the mailbox expiry).
create or replace function public.expire_mailbox_items(p_days integer default 30)
returns bigint
language plpgsql
set search_path = public
as $$
declare
  v_removed bigint;
begin
  delete from public.mailbox_items where received_at < now() - make_interval(days => p_days);
  get diagnostics v_removed = row_count;
  delete from public.rate_limits where window_start < now() - interval '1 day';
  delete from public.code_challenges where sent_at < now() - interval '1 day';
  return v_removed;
end;
$$;
