# Lime backend (Supabase): API v2 core

The first half of [`docs/api-v2.md`](../docs/api-v2.md), built on Supabase: the schema, device registration, the key directory, one-time keys, delivery-key (sealed) access, the fan-out `send`, mailbox fetch and acknowledge, and the 30-day expiry. The server is a blind mailbox: it stores no conversations, membership, group names, message text, or senders of sealed messages. The iOS app does not use it yet.

## What is here

- `migrations/`: the tables (`devices`, `master_keys`, `one_time_keys`, `mailbox_items`, `delivery_access`, `rate_limits`), their functions, and the daily `pg_cron` expiry job. **Row-level security is on for every table with no policies, and `anon` and `authenticated` get no privileges at all.** Only the Edge Functions touch the tables, with the service role. Staging was created with "Automatically expose new tables" off and "Enable automatic RLS" on, so every privilege is an explicit `GRANT` to `service_role`, and the local stack is configured the same way (`auto_expose_new_tables = false` in `config.toml`).
- `functions/`: eight Edge Functions (TypeScript on Deno): `devices-register`, `keys-upload`, `users-devices`, `keys-claim`, `delivery-access-set`, `send`, `mailbox-fetch`, `mailbox-ack`. Every one needs a Supabase Auth user token **except the sealed path of `send`**, which proves knowledge of the recipient's access key instead. Nothing logs ciphertext, keys, access keys or tokens. Shared code is in `functions/_shared/`; the limits are configuration (`functions/_shared/config.ts`, set as function secrets).
- `tests/`: the Deno tests (`api_v2_test.ts`, against the local stack) and a staging smoke test.
- `test.sh`, `deploy-staging.sh`, `smoke-staging.sh`.

The decisions that fill the open items in `api-v2.md` section 11 are recorded there ("decided in LIME-92").

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
