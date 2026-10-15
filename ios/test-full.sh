#!/bin/sh
# LIME-151: the full iOS suite (unit + UI) on the 13 mini simulator, in parallel (each worker is a clone of the simulator).
# Signing stays ON (the Keychain tests need it; never pass CODE_SIGNING_ALLOWED=NO for tests).
#
#   ./ios/test-full.sh                      the whole suite, parallel
#   ./ios/test-full.sh --workers 3          choose the number of parallel workers (default 3)
#   ./ios/test-full.sh --serial             one simulator, one test at a time (the old way)
#   ./ios/test-full.sh --only GroupCallLayoutTests [--only CallScreenUITests ...]   chosen test classes only
#   ./ios/test-full.sh --device <udid>      another simulator (default: the 13 mini)
#
# Prints one summary line (unit and UI: run / skipped / failed, minutes) and exits non-zero on any failure.
# The full log is $TMPDIR/lime-test-full.log, the result bundle $TMPDIR/lime-test-full.xcresult.
set -u
cd "$(dirname "$0")"
device="1AB12230-CBEB-49DE-88AA-BEAB8668AD3C"
workers=3
serial=0
only=""
while [ $# -gt 0 ]; do
  case "$1" in
    --workers) workers="$2"; shift 2 ;;
    --serial) serial=1; shift ;;
    --only) only="$only $2"; shift 2 ;;
    --device) device="$2"; shift 2 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done
tmp="${TMPDIR:-/tmp}"
log="$tmp/lime-test-full.log"
result="$tmp/lime-test-full.xcresult"
rm -rf "$result"

filters=""
for name in $only; do
  if grep -rqE "class $name\b" LimeTests; then filters="$filters -only-testing:LimeTests/$name"
  elif grep -rqE "class $name\b" LimeUITests; then filters="$filters -only-testing:LimeUITests/$name"
  else echo "no test class named $name" >&2; exit 2; fi
done

if [ "$serial" = 1 ]; then mode="-parallel-testing-enabled NO"; else mode="-parallel-testing-enabled YES -parallel-testing-worker-count $workers"; fi

start=$(date +%s)
# shellcheck disable=SC2086
xcodebuild test -project Lime.xcodeproj -scheme Lime -destination "platform=iOS Simulator,id=$device" \
  $mode $filters -resultBundlePath "$result" >"$log" 2>&1
status=$?
minutes=$(( ($(date +%s) - start + 30) / 60 ))

python3 - "$result" "$minutes" "$status" "$log" <<'PY'
import json, subprocess, sys
result, minutes, status, log = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]
def counts(node, c):
    for child in node.get("children", []):
        if child.get("nodeType") == "Test Case":
            r = child.get("result", "")
            c["run"] += 1
            if r == "Skipped": c["skipped"] += 1
            elif r == "Failed": c["failed"] += 1
        else:
            counts(child, c)
try:
    out = subprocess.run(["xcrun", "xcresulttool", "get", "test-results", "tests", "--path", result, "--compact"], capture_output=True, text=True, check=True).stdout
    tree = json.loads(out)
    totals = {}
    for plan in tree.get("testNodes", []):
        for bundle in plan.get("children", []):
            name = bundle.get("name", "")
            c = totals.setdefault("UI" if "UITests" in name else "unit", {"run": 0, "skipped": 0, "failed": 0})
            counts(bundle, c)
    parts = [f"{k}: {v['run']} run, {v['skipped']} skipped, {v['failed']} failed" for k, v in sorted(totals.items(), reverse=True)]
    failed = sum(v["failed"] for v in totals.values())
    if not totals or sum(v["run"] for v in totals.values()) == 0:
        parts, failed = ["no tests ran (is the class in the generated project? run ./ios/generate.sh or xcodegen)"], 1
except Exception as error:  # the build failed before any test ran, or the bundle is unreadable
    parts, failed = [f"no result bundle ({error.__class__.__name__}); see {log}"], 1
print("; ".join(parts) + f"; {minutes} min; " + ("PASSED" if status == 0 and failed == 0 else "FAILED"))
sys.exit(0 if status == 0 and failed == 0 else 1)
PY
