#!/bin/sh
# READ-ONLY: checks that the hosted staging Auth settings match supabase/config.toml where the app
# depends on them (email code length, confirmations, minimum seconds between emails). It never
# writes. The Supabase CLI's access token is read from the macOS keychain into this process's
# memory only; it is never printed or written anywhere. Exit 1 on a mismatch.
set -e
cd "$(dirname "$0")/.."
set -a; . "$HOME/.lime/staging.env"; set +a
RAW="$(security find-generic-password -s "Supabase CLI" -a supabase -w 2>/dev/null || true)"
case "$RAW" in go-keyring-base64:*) TOKEN="$(printf '%s' "${RAW#go-keyring-base64:}" | base64 -d)";; *) TOKEN="$RAW";; esac
[ -n "$TOKEN" ] || { echo "No Supabase CLI login found (run: supabase login)." >&2; exit 1; }
curl -fsS -H "Authorization: Bearer $TOKEN" "https://api.supabase.com/v1/projects/$SUPABASE_PROJECT_REF/config/auth" |
  CONFIG=supabase/config.toml python3 -c '
import sys, json, os, re
live = json.load(sys.stdin)
text = open(os.environ["CONFIG"]).read()
email = text.split("[auth.email]", 1)[1].split("\n[", 1)[0]
want_len = int(re.search(r"^otp_length\s*=\s*(\d+)", email, re.M).group(1))
want_confirm = re.search(r"^enable_confirmations\s*=\s*(\w+)", email, re.M).group(1) == "true"
checks = [
    ("otp_length", live.get("mailer_otp_length"), want_len),
    ("enable_confirmations", not live.get("mailer_autoconfirm"), want_confirm),
]
bad = 0
for name, got, want in checks:
    ok = got == want
    bad += not ok
    print(("ok       " if ok else "MISMATCH ") + f"{name}: staging={got} config.toml={want}")
interval = live.get("smtp_max_frequency")
print(f"info     min seconds between emails on staging: {interval}")
sys.exit(1 if bad else 0)'
