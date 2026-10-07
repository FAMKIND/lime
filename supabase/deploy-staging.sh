#!/bin/sh
# Deploys the schema and the Edge Functions to the STAGING project (lime-staging).
#
# Reads ~/.lime/staging.env (outside the repo, chmod 600) for SUPABASE_PROJECT_REF and
# SUPABASE_DB_PASSWORD. It never prints them, and it never writes the service-role key anywhere:
# that key stays inside Supabase. Needs `supabase login` once (it opens your browser).
set -e
cd "$(dirname "$0")/.."

ENV_FILE="$HOME/.lime/staging.env"
[ -f "$ENV_FILE" ] || { echo "Missing $ENV_FILE (SUPABASE_PROJECT_REF and SUPABASE_DB_PASSWORD). See supabase/README.md." >&2; exit 1; }
set -a
# shellcheck disable=SC1090
. "$ENV_FILE"
set +a
[ -n "$SUPABASE_PROJECT_REF" ] && [ -n "$SUPABASE_DB_PASSWORD" ] || { echo "$ENV_FILE must set SUPABASE_PROJECT_REF and SUPABASE_DB_PASSWORD." >&2; exit 1; }
supabase projects list >/dev/null 2>&1 || { echo "Not logged in. Run: supabase login" >&2; exit 1; }

echo "Linking the staging project..."
supabase link --project-ref "$SUPABASE_PROJECT_REF" >/dev/null

echo "Pushing migrations..."
supabase db push --linked --yes

echo "Deploying functions..."
supabase functions deploy --project-ref "$SUPABASE_PROJECT_REF" --use-api

echo "Setting function secrets (the limits; the defaults decided in LIME-92)..."
supabase secrets set --project-ref "$SUPABASE_PROJECT_REF" \
  LIME_RATE_SEND_PER_MIN=120 LIME_RATE_CLAIM_PER_MIN=60 LIME_RATE_REGISTER_PER_HOUR=10 \
  LIME_MAX_ITEM_BYTES=65536 LIME_RATE_LOOKUP_PER_MIN=30 LIME_RATE_PROFILE_PER_MIN=120 \
  LIME_RATE_IDENTIFY_PER_MIN=30 LIME_RATE_SIGNIN_PER_10MIN=10 LIME_RATE_EMAIL_PER_HOUR=10 >/dev/null

# The URL and the anon (publishable) key are meant to ship inside the app, so they may be written
# to a gitignored file for the later iOS brief. The service-role key is never read here.
PUBLIC_ENV="supabase/.staging.public.env"
ANON_KEY="$(supabase projects api-keys --project-ref "$SUPABASE_PROJECT_REF" -o json 2>/dev/null |
  python3 -c 'import sys, json
keys = json.load(sys.stdin)
pick = [k for k in keys if k.get("name") == "anon" or k.get("type") == "publishable"]
print(pick[0]["api_key"] if pick else "")')"
[ -n "$ANON_KEY" ] || { echo "Could not read the anon key." >&2; exit 1; }
umask 077
{
  echo "SUPABASE_URL=https://$SUPABASE_PROJECT_REF.supabase.co"
  echo "SUPABASE_ANON_KEY=$ANON_KEY"
} > "$PUBLIC_ENV"
echo "Deployed. Wrote $PUBLIC_ENV (public values only, gitignored)."
