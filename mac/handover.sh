#!/bin/sh
# Makes fresh sessions for the three Mac test accounts and hands Ada Mac's tokens (no password) to the sandboxed app, the way Android's --push
# hands them to the emulator: a file in the app's own container. The app (Debug only, `-lime-use-test-account`) signs in with them through
# the same session code iOS uses and deletes the file. Only the three Mac test accounts are accepted (mac/Lime/MacTestAccount.swift).
# Each run ends the older sessions on the server, so start the partner (`partner --as b echo`) AFTER this.
set -e
cd "$(dirname "$0")"
BUNDLE_ID="com.famkind.lime"
./tools/staging-test-accounts.sh >/dev/null
osascript -e 'tell application id "'"$BUNDLE_ID"'" to quit' >/dev/null 2>&1 || true
sleep 1
DEST="$HOME/Library/Containers/$BUNDLE_ID/Data/Library/Application Support"
mkdir -p "$DEST"
python3 -I - "$DEST/lime-test-account.json" <<'PY'
import json, os, sys
d = json.load(open(os.path.expanduser("~/.lime/mac-test-accounts.json")))
a = d["accounts"]["a"]
out = {"allowed_user_ids": [v["user_id"] for v in d["accounts"].values()],
       "account": {k: a[k] for k in ("display_name", "username", "user_id", "access_token", "refresh_token", "expires_at")}}
fd = os.open(sys.argv[1], os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
with os.fdopen(fd, "w") as f: json.dump(out, f)
PY
