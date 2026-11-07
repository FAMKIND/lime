#!/bin/sh
# Counts the launch list on STAGING (LIME-284c2): confirmed and waiting signups per list, and the "I teach in" split. Read-only: it prints counts, never an address.
#   ./supabase/waitlist-count.sh           (needs `supabase login` and ~/.lime/staging.env)
set -e
cd "$(dirname "$0")/.."
ENV_FILE="$HOME/.lime/staging.env"
[ -f "$ENV_FILE" ] || { echo "Missing $ENV_FILE." >&2; exit 1; }
set -a; . "$ENV_FILE"; set +a
supabase link --project-ref "$SUPABASE_PROJECT_REF" >/dev/null
supabase db query --linked "select list, count(*) filter (where confirmed_at is not null) as confirmed, count(*) filter (where confirmed_at is null) as waiting_to_confirm, count(*) filter (where sent_at is not null) as email_sent from public.waitlist group by list order by list;"
supabase db query --linked "select coalesce(teaches, '(no answer)') as teaches, count(*) from public.waitlist where list = 'launch' and confirmed_at is not null group by 1 order by 2 desc;"
