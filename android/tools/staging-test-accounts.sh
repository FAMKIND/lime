#!/bin/sh
# Debug tooling, never shipped. Makes (or reuses) the three throwaway STAGING accounts the Android run uses:
#   android-a@example.invalid  "Ada Android"  @ada_android
#   android-b@example.invalid  "Ben Android"  @ben_android
#   android-c@example.invalid  "Cleo Android" @cleo_android   (LIME-303: the third person of a group)
# and writes their fresh sessions to ~/.lime/android-test-accounts.json (chmod 600, outside the repo).
#
#   staging-test-accounts.sh            create/reuse all three, sign each in fresh, mark the session verified, write the file
#   staging-test-accounts.sh --push     the same, then push the three accounts' tokens (no passwords) to the emulator's debug app
#   staging-test-accounts.sh --delete   delete all three accounts and the file
#
# The keys are read exactly as core/run-integration.sh staging reads them: into this process's memory only, never printed or
# written. It touches nothing on staging except these three accounts (and their profile rows).
set -e
PATH="/opt/homebrew/bin:/opt/homebrew/share/android-commandlinetools/platform-tools:$PATH"
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
FILE = os.path.expanduser("~/.lime/android-test-accounts.json")
ACCOUNTS = {
    "a": {"email": "android-a@example.invalid", "display_name": "Ada Android", "username": "ada_android"},
    "b": {"email": "android-b@example.invalid", "display_name": "Ben Android", "username": "ben_android"},
    "c": {"email": "android-c@example.invalid", "display_name": "Cleo Android", "username": "cleo_android"},
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
    existing = {u["email"]: u for u in all_users() if u.get("email") in {a["email"] for a in ACCOUNTS.values()}}
    out = {}
    for key, acc in ACCOUNTS.items():
        password = secrets.token_urlsafe(24)  # a new password each run: no secret has to be kept anywhere
        if acc["email"] in existing:
            user = existing[acc["email"]]
            call("PUT", f"/auth/v1/admin/users/{user['id']}", {"password": password, "email_confirm": True})
        else:
            user = call("POST", "/auth/v1/admin/users", {"email": acc["email"], "password": password, "email_confirm": True})
        uid = user["id"]
        call("POST", "/rest/v1/profiles", {"user_id": uid, "display_name": acc["display_name"], "username": acc["username"]},
             headers={"Prefer": "resolution=merge-duplicates,return=minimal"})
        session = call("POST", "/auth/v1/token?grant_type=password", {"email": acc["email"], "password": password}, key=anon)
        call("POST", "/rest/v1/auth_proofs", {"session_id": jwt_session_id(session["access_token"]), "user_id": uid, "password_ok": True, "code_ok": True},
             headers={"Prefer": "return=minimal"})
        out[key] = {**acc, "user_id": uid, "access_token": session["access_token"], "refresh_token": session["refresh_token"],
                    "expires_at": int(time.time()) + int(session.get("expires_in", 3600))}
    os.makedirs(os.path.dirname(FILE), exist_ok=True)
    fd = os.open(FILE, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f: json.dump({"api_url": base, "accounts": out}, f, indent=1)
    os.chmod(FILE, 0o600)
    print("wrote", FILE, "for", ", ".join(a["email"] for a in ACCOUNTS.values()))
    return out

def push(out):
    # Tokens only (no passwords), to the debuggable app's private files through adb run-as.
    stripped = {"accounts": {k: {f: v[f] for f in ("display_name", "username", "user_id", "access_token", "refresh_token", "expires_at")} for k, v in out.items()}}
    tmp = "/data/local/tmp/lime-test-accounts.json"
    local = os.path.expanduser("~/.lime/android-test-accounts.push.json")
    fd = os.open(local, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f: json.dump(stripped, f)
    subprocess.run(["adb", "push", local, tmp], check=True, stdout=subprocess.DEVNULL)
    subprocess.run(["adb", "shell", f"run-as com.limemessenger.lime sh -c 'mkdir -p files && cp {tmp} files/test-accounts.json'"], check=True)
    subprocess.run(["adb", "shell", f"rm {tmp}"], check=True)
    os.remove(local)
    print("pushed Ada, Ben and Cleo (tokens only) to the emulator's debug app")

if mode == "--delete": delete_all()
elif mode in ("ensure", "--push"):
    out = ensure()
    if mode == "--push": push(out)
else: sys.exit("usage: staging-test-accounts.sh [--push|--delete]")
PY
