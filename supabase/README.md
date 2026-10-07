# Lime backend (Supabase): API v2 core

The first half of [`docs/api-v2.md`](../docs/api-v2.md), built on Supabase: the schema, device registration, the key directory, one-time keys, delivery-key (sealed) access, the fan-out `send`, mailbox fetch and acknowledge, and the 30-day expiry. The server is a blind mailbox: it stores no conversations, membership, group names, message text, or senders of sealed messages. The iOS app does not use it yet.

## What is here

- `migrations/`: the tables (`devices`, `master_keys`, `one_time_keys`, `mailbox_items`, `delivery_access`, `rate_limits`, and from LIME-94 `profiles`, `auth_proofs`, `code_challenges`), their functions, and the daily `pg_cron` expiry job. **Row-level security is on for every table with no policies, and `anon` and `authenticated` get no privileges at all.** Only the Edge Functions touch the tables, with the service role. Staging was created with "Automatically expose new tables" off and "Enable automatic RLS" on, so every privilege is an explicit `GRANT` to `service_role`, and the local stack is configured the same way (`auto_expose_new_tables = false` in `config.toml`).
- `functions/`: twenty Edge Functions (TypeScript on Deno). **Keys and the mailbox:** `devices-register`, `keys-upload`, `users-devices`, `keys-claim`, `delivery-access-set`, `send`, `mailbox-fetch`, `mailbox-ack`, and `users-lookup` (an exact, case-insensitive email match that returns the user id only; 30 a minute per user; it never lists). **Accounts (LIME-94):** `identify`, `signin-password`, `code-verify`, `code-resend`, `signup-start`, `signup-verify`, `signup-set-password`, `reset-start`, `reset-verify`, `profile-set`, `profile-get`. Every function needs a **verified** Supabase Auth session (a password and an emailed code, see below) **except** the sign-in steps themselves and the sealed path of `send`, which proves knowledge of the recipient's access key instead. Nothing logs ciphertext, keys, access keys, codes, passwords or tokens. Shared code is in `functions/_shared/`; the limits are configuration (`functions/_shared/config.ts`, set as function secrets).
- `tests/`: the Deno tests (`api_v2_test.ts`, against the local stack) and a staging smoke test.
- `test.sh`, `deploy-staging.sh`, `smoke-staging.sh`.

The decisions that fill the open items in `api-v2.md` section 11 are recorded there ("decided in LIME-92").

## Sign-up and sign-in (LIME-94)

A session can do nothing until it has passed **both** a password and an emailed code (6 digits; the functions and the app accept 6 to 8); the functions check both and keep a proof record per session (`docs/api-v2.md` section 11). The codes go out through Supabase Auth's email. Two things in the Auth settings matter:

- **The emails carry the code, not a link.** The templates are `supabase/templates/code.html` (used for "Confirm signup" and "Magic Link"); `config.toml` applies them locally. On the hosted project, paste its contents into Authentication, Emails, Templates for both. Also set the minimum password length to 10 and the minimum interval between emails to 30 seconds or less.
- **The built-in sender is for testing only:** it sends to the project's team members, **2 messages an hour** for the whole project. Real sign-ups need a custom SMTP sender (Resend's free tier works): add and verify the sending domain in Resend (it shows the DNS records), create a "sending access" API key, then enter it in Authentication, SMTP Settings (host `smtp.resend.com`, port 465, user `resend`, the key as the password) and raise the hourly email limit. Put the key only in the Supabase dashboard.

Locally, `supabase start` runs a mail catcher (Mailpit, port 54324) and the tests read the codes from it.

## Prerequisites

```bash
brew install supabase/tap/supabase deno colima docker
colima start        # Docker through Colima (open source); no Docker Desktop
```

`./supabase/test.sh` starts Colima and the local stack for you if they are not running.

## Test locally

```bash
./supabase/test.sh
```

Starts the local Supabase stack (`supabase start`, the first run pulls images), creates throwaway users through the local admin API, and runs the tests: register, upload keys and claim (a key is claimed once); sealed send with the right key and no token, a wrong key (`403`), an identified send recording the sender; fan-out to three devices; ack; de-duplication; the 64 KB limit; rate limits; row-level security and grants; the 30-day expiry and the cron job; a revoked device; the Realtime nudge. Stop the stack with `supabase stop`.

## Deploy to staging

Staging is the free project `lime-staging`. Put its reference and database password in `~/.lime/staging.env` (outside the repo, `chmod 600`):

```
SUPABASE_PROJECT_REF=...
SUPABASE_DB_PASSWORD=...
```

Then:

```bash
supabase login                    # once; opens your browser
./supabase/deploy-staging.sh      # links, pushes migrations, deploys functions, sets secrets
./supabase/smoke-staging.sh       # two throwaway users: sealed send, fetch, ack; then deletes them
```

The scripts never print the secrets. `deploy-staging.sh` writes the project URL and the **anon (publishable) key** to the gitignored `supabase/.staging.public.env` for the later iOS brief (those two values are meant to ship inside the app). **The service-role key never leaves Supabase**: `smoke-staging.sh` reads it into memory only, to create and delete the throwaway users, and never writes it down. Never commit anything under `~/.lime`.

## The free plan (as of 2026-10-06, supabase.com/pricing)

500 MB database, 50,000 monthly active users, 500,000 Edge Function invocations, 200 concurrent Realtime connections and 2 million Realtime messages a month, 2 active projects. **Free projects are paused after one week of inactivity**: the first request after a pause fails until the project is restored from the dashboard. Keep that in mind for staging, and a paid plan for production.


## Staging settings must match `config.toml`

`supabase config push` is never used, so the hosted Auth settings are set by hand in the dashboard. The code length (`otp_length`, **6**) and email confirmations (**on**) must match `config.toml`; a mismatch is what broke LIME-94's gate (staging sent 8-digit codes). `./supabase/check-staging-settings.sh` compares them read-only (the CLI token stays in memory) and `smoke-staging.sh` runs it first.

## Finding people, public profiles and the private nudge (LIME-95)

- `users-find { query }`: an exact username or email to the person's public profile fields (404 for nobody, for someone who hid from search, or for an account with no profile). 30 a minute per user.
- `profile-get { user_id }`: another person's public fields (a name only when they hid from search). 120 a minute per user (`LIME_RATE_PROFILE_PER_MIN`).
- The Realtime "new items" nudge is a **private** channel (`device:<id>`); a policy on `realtime.messages` (migration `20261006160000`) lets only the device's owner, on a fully signed-in session, join it. A client must set its access token before it joins.
- **After adding a new function directory, restart the local stack** (`supabase stop && supabase start`): the local Edge runtime only learns about a new function folder at start. `./supabase/test.sh` restarts the runtime, which is enough for edits to existing functions.

## Replacing an account's keys, and the notice email (LIME-95-fix)

A fully verified session that registers a device with a **different master key** replaces the account's keys (old devices revoked, their unfetched mail removed, senders told by hash through `undelivered-take`): see `docs/api-v2.md` section 11. This is temporary policy until the recovery key exists.

The account's owner is emailed ("A new phone signed in and replaced your Lime keys. If this wasn't you, reset your password."). It needs a Resend key as a **function secret**, which only you can set (I never read your Resend key):

```
supabase secrets set LIME_NOTIFY_RESEND_API_KEY=re_xxxxxxxx --project-ref <ref>
# optional: supabase secrets set LIME_NOTIFY_FROM="Lime <no-reply@send.limechat.org>" --project-ref <ref>
```

The sending domain must be verified in Resend (it already is for the sign-in codes). Until the secret is set, no email is sent and nothing fails.
