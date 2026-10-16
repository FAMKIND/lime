#!/bin/sh
# Read-only check (LIME-153): staging's MESH_ROUTING_SECRET_KEY must exist and must NOT be the local test key.
#
# The local stack's mesh key is public (it is in the repo, for tests). A deploy once replaced staging's real key with it; every mesh upload then
# failed. This reads only the DIGEST that `supabase secrets list` shows (never the secret), and prints at most its first 16 characters.
#
#   ./supabase/check-staging-mesh-key.sh       exits 0 when staging holds some other key; non-zero when it holds the local one or none
#
# Needs ~/.lime/staging.env (SUPABASE_PROJECT_REF) and `supabase login`, like deploy-staging.sh. deploy-staging.sh runs this at its end.
set -e
cd "$(dirname "$0")/.."

ENV_FILE="$HOME/.lime/staging.env"
[ -f "$ENV_FILE" ] || { echo "Missing $ENV_FILE (SUPABASE_PROJECT_REF). See supabase/README.md." >&2; exit 1; }
set -a
# shellcheck disable=SC1090
. "$ENV_FILE"
set +a
[ -n "$SUPABASE_PROJECT_REF" ] || { echo "$ENV_FILE must set SUPABASE_PROJECT_REF." >&2; exit 1; }

LOCAL_ENV="supabase/functions/.env"
[ -f "$LOCAL_ENV" ] || { echo "Missing $LOCAL_ENV (the local test key); cannot tell whether staging holds it." >&2; exit 1; }

supabase secrets list --project-ref "$SUPABASE_PROJECT_REF" -o json 2>/dev/null | LOCAL_ENV="$LOCAL_ENV" python3 -c '
import hashlib, json, os, sys
local = None
for line in open(os.environ["LOCAL_ENV"]):
    if line.startswith("MESH_ROUTING_SECRET_KEY="):
        local = line.split("=", 1)[1].strip()
if not local:
    sys.exit("The local test key is not in supabase/functions/.env.")
local_digest = hashlib.sha256(local.encode()).hexdigest()
try:
    secrets = json.load(sys.stdin)
except Exception:
    sys.exit("Could not read `supabase secrets list` (not logged in?).")
digest = next((s.get("value", "") for s in secrets if s.get("name") == "MESH_ROUTING_SECRET_KEY"), None)
if not digest:
    sys.exit("staging has NO MESH_ROUTING_SECRET_KEY: run ./supabase/mesh-keygen.sh")
print("staging mesh key digest: " + digest[:16])
if digest == local_digest:
    sys.exit("staging holds the LOCAL test mesh key: run ./supabase/mesh-keygen.sh")
print("ok: staging holds a key that is not the local test key")
'
