#!/bin/sh
# Makes the server's mesh routing key pair (LIME-140) and puts the SECRET straight into the staging project's function secrets
# (MESH_ROUTING_SECRET_KEY). It prints ONLY the PUBLIC key (and its id) for pinning in lime_core: the secret is never printed, never put in
# a command line, and never left on disk (it passes through a chmod 600 temp file that is deleted at once).
#
#   ./supabase/mesh-keygen.sh            make a key pair and set the staging secret (run by the USER, in a Terminal)
#   ./supabase/mesh-keygen.sh --dry-run  make a pair, print the public key, set nothing, throw the secret away (to see it work)
#
# Needs `supabase login` and ~/.lime/staging.env (SUPABASE_PROJECT_REF), like deploy-staging.sh; and openssl (macOS has it).
# Re-running REPLACES the staging key: mail sealed to the old public key is then refused by mesh-drop until the app pins the new one, so only
# do it when you mean to (it is the key rotation; a later brief adds an overlap with key ids).
set -e
cd "$(dirname "$0")/.."
dry=0
[ "$1" = "--dry-run" ] && dry=1

command -v openssl >/dev/null 2>&1 || { echo "openssl is missing." >&2; exit 1; }
if [ "$dry" = 0 ]; then
  ENV_FILE="$HOME/.lime/staging.env"
  [ -f "$ENV_FILE" ] || { echo "Missing $ENV_FILE (SUPABASE_PROJECT_REF). See supabase/README.md." >&2; exit 1; }
  set -a
  # shellcheck disable=SC1090
  . "$ENV_FILE"
  set +a
  [ -n "$SUPABASE_PROJECT_REF" ] || { echo "$ENV_FILE must set SUPABASE_PROJECT_REF." >&2; exit 1; }
  supabase projects list >/dev/null 2>&1 || { echo "Not logged in. Run: supabase login" >&2; exit 1; }
fi

work="$(mktemp -d)"
chmod 700 "$work"
trap 'rm -rf "$work"' EXIT
openssl genpkey -algorithm X25519 -out "$work/key.pem" 2>/dev/null
# The raw 32 bytes are the last 32 of the DER encoding.
secret="$(openssl pkey -in "$work/key.pem" -outform DER 2>/dev/null | tail -c 32 | base64)"
public="$(openssl pkey -in "$work/key.pem" -pubout -outform DER 2>/dev/null | tail -c 32 | base64)"
[ -n "$secret" ] && [ -n "$public" ] || { echo "Could not make the key pair." >&2; exit 1; }
rm -f "$work/key.pem"

if [ "$dry" = 1 ]; then
  echo
  echo "################################################################"
  echo "#  DRY RUN: DO NOT PIN THIS KEY                                #"
  echo "#  Nothing was set on the server; its secret was thrown away.  #"
  echo "#  Pinning it makes every real upload fail (a 403).            #"
  echo "################################################################"
else
  umask 077
  printf 'MESH_ROUTING_SECRET_KEY=%s\n' "$secret" > "$work/secret.env"
  supabase secrets set --env-file "$work/secret.env" --project-ref "$SUPABASE_PROJECT_REF" >/dev/null
  rm -f "$work/secret.env"
  echo "The secret is set on the staging project (MESH_ROUTING_SECRET_KEY, key id 1)."
  echo
  echo "================================================================"
  echo "  PIN THIS KEY (its secret is now on the server)"
  echo "================================================================"
fi
secret=""
echo
if [ "$dry" = 1 ]; then
  echo "Public key of the THROWN-AWAY pair (DRY RUN: DO NOT PIN):"
else
  echo "Public key (key id 1), for pinning in core/src/mesh.rs (SERVER_KEYS):"
fi
echo "$public"
if [ "$dry" = 1 ]; then
  echo
  echo "DRY RUN: DO NOT PIN THIS KEY"
fi
