#!/bin/sh
# Debug tooling, never shipped. Makes (or reuses) the three throwaway STAGING accounts the Mac lane uses:
#   mac-a@example.invalid  "Ada Mac"  @ada_mac
#   mac-b@example.invalid  "Ben Mac"  @ben_mac
#   mac-c@example.invalid  "Cleo Mac" @cleo_mac
# and writes their fresh sessions to ~/.lime/mac-test-accounts.json (chmod 600, outside the repo).
#
#   staging-test-accounts.sh                      create/reuse all three, sign each in fresh, mark the session verified, write the file
#   staging-test-accounts.sh --rotate-passwords   as above, but give every account a NEW password: this ENDS every session of the
#                                                 three accounts (the app's and the partner's); restart them afterwards
#   staging-test-accounts.sh --delete             delete all three accounts and the file
#
# Each account's password is kept in the file (chmod 600, outside the repo, throwaway staging accounts) and reused, so running this
# again signs in again with the SAME password, which on staging does not end the sessions already open (LIME-606 probe). A password
# is made only for a new account, for one whose stored password no longer works, or with --rotate-passwords.
#
# The keys are read exactly as core/run-integration.sh staging reads them: into this process's memory only, never printed or
# written. It touches nothing on staging except these three accounts (and their profile rows).
set -e
PATH="/opt/homebrew/bin:$PATH"
ENV_FILE="$HOME/.lime/staging.env"
[ -f "$ENV_FILE" ] || { echo "Missing $ENV_FILE." >&2; exit 1; }
set -a; . "$ENV_FILE"; set +a
keys="$(supabase projects api-keys --project-ref "$SUPABASE_PROJECT_REF" -o json 2>/dev/null)"
export LIME_API_URL="https://$SUPABASE_PROJECT_REF.supabase.co"
export LIME_KEYS="$keys"
unset keys SUPABASE_DB_PASSWORD
MODE="${1:-ensure}"

python3 -I - "$MODE" <<'PY'
import base64, json, os, secrets, subprocess, sys, time, urllib.error, urllib.request

mode = sys.argv[1]
base = os.environ["LIME_API_URL"]
keys = json.loads(os.environ["LIME_KEYS"])
def pick(want):
    for k in keys:
        if k.get("name") == want or (want == "anon" and k.get("type") == "publishable") or (want == "service_role" and k.get("type") == "secret"):
            return k["api_key"]
    sys.exit("could not read the API keys")
anon, service = pick("anon"), pick("service_role")
FILE = os.path.expanduser("~/.lime/mac-test-accounts.json")
ACCOUNTS = {
    "a": {"email": "mac-a@example.invalid", "display_name": "Ada Mac", "username": "ada_mac"},
    "b": {"email": "mac-b@example.invalid", "display_name": "Ben Mac", "username": "ben_mac"},
    "c": {"email": "mac-c@example.invalid", "display_name": "Cleo Mac", "username": "cleo_mac"},
}

def call(method, path, body=None, key=None, headers=None, ok=(200, 201, 204)):
    h = {"apikey": key or service, "content-type": "application/json"}
    if key is None: h["authorization"] = "Bearer " + service
    h.update(headers or {})
    req = urllib.request.Request(base + path, method=method, headers=h, data=None if body is None else json.dumps(body).encode())
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            raw = r.read(); status = r.status
    except urllib.error.HTTPError as e:
        raw = e.read(); status = e.code
    data = json.loads(raw) if raw else {}
    if status not in ok:
        sys.exit(f"{method} {path.split('?')[0]} failed: {status}")
    return data

def all_users():
    users, page = [], 1
    while True:
        batch = call("GET", f"/auth/v1/admin/users?page={page}&per_page=200")
        batch = batch.get("users", batch) if isinstance(batch, dict) else batch
        users += batch
        if len(batch) < 200: return users
        page += 1

def delete_all():
    mine = {a["email"] for a in ACCOUNTS.values()}
    for u in all_users():
        if u.get("email") in mine:
            call("DELETE", f"/auth/v1/admin/users/{u['id']}")
            print("deleted", u["email"])
    if os.path.exists(FILE): os.remove(FILE)

def jwt_session_id(token):
    part = token.split(".")[1]
    return json.loads(base64.urlsafe_b64decode(part + "=" * (-len(part) % 4)))["session_id"]

def ensure():
    try: stored = json.load(open(FILE)).get("accounts", {})
    except (OSError, ValueError): stored = {}
    rotated = []
    existing = {u["email"]: u for u in all_users() if u.get("email") in {a["email"] for a in ACCOUNTS.values()}}
    out = {}
    for key, acc in ACCOUNTS.items():
        password = None if ROTATE else (stored.get(key) or {}).get("password")
        if acc["email"] in existing:
            user = existing[acc["email"]]
            if password:  # does the stored password still work? (it does not after a password change made elsewhere)
                probe = call("POST", "/auth/v1/token?grant_type=password", {"email": acc["email"], "password": password}, key=anon, ok=(200, 400))
                if "access_token" not in probe: password = None
            if not password:
                password = secrets.token_urlsafe(24)
                call("PUT", f"/auth/v1/admin/users/{user['id']}", {"password": password, "email_confirm": True})
                rotated.append(acc["email"])
        else:
            password = password or secrets.token_urlsafe(24)
            user = call("POST", "/auth/v1/admin/users", {"email": acc["email"], "password": password, "email_confirm": True})
        uid = user["id"]
        call("POST", "/rest/v1/profiles", {"user_id": uid, "display_name": acc["display_name"], "username": acc["username"]},
             headers={"Prefer": "resolution=merge-duplicates,return=minimal"})
        session = call("POST", "/auth/v1/token?grant_type=password", {"email": acc["email"], "password": password}, key=anon)
        call("POST", "/rest/v1/auth_proofs", {"session_id": jwt_session_id(session["access_token"]), "user_id": uid, "password_ok": True, "code_ok": True},
             headers={"Prefer": "return=minimal"})
        out[key] = {**acc, "password": password, "user_id": uid, "access_token": session["access_token"], "refresh_token": session["refresh_token"],
                    "expires_at": int(time.time()) + int(session.get("expires_in", 3600))}
    os.makedirs(os.path.dirname(FILE), exist_ok=True)
    fd = os.open(FILE, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f: json.dump({"api_url": base, "accounts": out}, f, indent=1)
    os.chmod(FILE, 0o600)
    print("wrote", FILE, "for", ", ".join(a["email"] for a in ACCOUNTS.values()))
    if rotated:
        print("NEW password for", ", ".join(rotated), "- this ended every session of " + ("these accounts" if len(rotated) > 1 else "that account") + ": restart the app and the partner")
    return out

ROTATE = mode == "--rotate-passwords"
if mode == "--delete": delete_all()
elif mode in ("ensure", "--rotate-passwords"): ensure()
else: sys.exit("usage: staging-test-accounts.sh [--rotate-passwords | --delete]")
PY
