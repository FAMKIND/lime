#!/bin/sh
# Points the 15-minute blob sweep (pg_cron -> pg_net -> the blob-sweep Edge Function, LIME-98c) at an environment and
# gives it a fresh secret. Run once per environment (and again to rotate the secret):
#
#   ./supabase/schedule-sweep.sh           the LOCAL stack
#   ./supabase/schedule-sweep.sh staging   the linked STAGING project (needs `supabase login` and ~/.lime/staging.env)
#
# The secret is generated here, written only into the database's `sweep_target` table, and never printed.
set -e
cd "$(dirname "$0")/.."
SECRET="$(openssl rand -hex 24)"
if [ "$1" = "staging" ]; then
  ENV_FILE="$HOME/.lime/staging.env"
  [ -f "$ENV_FILE" ] || { echo "Missing $ENV_FILE." >&2; exit 1; }
  set -a; . "$ENV_FILE"; set +a
  URL="https://$SUPABASE_PROJECT_REF.supabase.co/functions/v1/blob-sweep"
  supabase link --project-ref "$SUPABASE_PROJECT_REF" >/dev/null
  supabase db query --linked "insert into public.sweep_target (id, url, secret) values (1, '$URL', '$SECRET') on conflict (id) do update set url = excluded.url, secret = excluded.secret; select count(*) as jobs from cron.job where jobname = 'lime-blob-sweep';"
else
  # Inside Docker the database reaches the Edge runtime through Kong.
  URL="http://supabase_kong_lime:8000/functions/v1/blob-sweep"
  docker exec supabase_db_lime psql -U postgres -v ON_ERROR_STOP=1 -c "insert into public.sweep_target (id, url, secret) values (1, '$URL', '$SECRET') on conflict (id) do update set url = excluded.url, secret = excluded.secret;" -c "select count(*) as jobs from cron.job where jobname = 'lime-blob-sweep';"
fi
echo "The sweep now runs every 15 minutes against $URL."
