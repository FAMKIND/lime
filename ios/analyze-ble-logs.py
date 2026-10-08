#!/usr/bin/env python3
"""LIME-103: reads the Nearby test's JSON-lines logs (one folder per phone: A/ and B/) and prints a
per-scenario timeline and the measurements that docs/spike-ble.md reports.

    ios/analyze-ble-logs.py ~/Downloads/ble-logs [--timeline]

Times are seconds from the scenario's first event on either phone (the phones' clocks agree to within
about a second, so cross-phone ordering is approximate).
"""
import glob, json, os, re, statistics, sys
from collections import defaultdict

def load(root):
    runs = defaultdict(dict)  # scenario -> {side -> [events]}
    for side in sorted(os.listdir(root)):
        for path in sorted(glob.glob(os.path.join(root, side, "*.jsonl"))):
            events = [json.loads(line) for line in open(path)]
            m = re.match(r"nearby-(.+)-\d+\.jsonl", os.path.basename(path))
            name = m.group(1)
            runs[name][side] = events
    return runs

def phase_at(events, ms):
    """The app's phase on that phone at time ms: foreground, background or locked."""
    phase = "foreground"
    for e in events:
        if e["kind"] == "app" and e.get("ms", 0) <= ms:
            p = e["phase"]
            if p == "background": phase = "background"
            elif p in ("foreground", "active"): phase = "foreground" if phase != "locked" else "locked"
            elif p == "locking": phase = "locked"
            elif p == "unlocked": phase = "foreground" if phase == "locked" else phase
        elif e["kind"] == "app" and e.get("ms", 0) > ms:
            break
    return phase

def main():
    root = os.path.expanduser(sys.argv[1] if len(sys.argv) > 1 else "~/Downloads/ble-logs")
    timeline = "--timeline" in sys.argv
    runs = load(root)
    def order(name):
        m = re.match(r"(\d+)([a-z]?)", name); return (int(m.group(1)), m.group(2), "relaunched" in name)
    for name in sorted(runs, key=order):
        sides = runs[name]
        t0 = min(e["ms"] for evs in sides.values() for e in evs if "ms" in e)
        print(f"\n=== {name}")
        for side, evs in sides.items():
            h = evs[0]
            print(f"  {side}: {h['device']} iOS {h['ios']} battery {h['battery']['percent']}% started {h['started']}")
        for side, evs in sides.items():
            started = next(e for e in evs if e["kind"] == "started")["ms"]
            disc = [e for e in evs if e["kind"] == "discovered"]
            conn = [e for e in evs if e["kind"] == "connected"]
            print(f"  {side}: first discovery +{(disc[0]['ms']-started)/1000:.1f}s" if disc else f"  {side}: no discovery",
                  f"| first connect +{(conn[0]['ms']-started)/1000:.1f}s" if conn else "| no connect",
                  f"| discovered x{len(disc)} connected x{len(conn)} disconnected x{sum(e['kind']=='disconnected' for e in evs)}",
                  f"| rssi {sorted(set(e['rssi'] for e in evs if e['kind'] in ('discovered','rssi')))}")
            for e in evs:
                if e["kind"] == "recv_done":
                    ph = phase_at(evs, e["ms"])
                    print(f"    {side} recv {e['size']:>5} B via {e['transport']:<5} {e['ms']:>5} ms {e['kbps']:>5} kbps sig={e['signatureOK']} while {ph} at +{(e['ms']-t0)/1000:.1f}s")
                if e["kind"] == "send_done" and e["size"] in (200, 4096, 32768):
                    print(f"    {side} sent {e['size']:>5} B via {e['transport']:<5} {e['ms']:>5} ms {e['kbps']:>5} kbps at +{(e['ms']-t0)/1000:.1f}s")
        if timeline:
            for side, evs in sides.items():
                for e in evs:
                    if e["kind"] in ("app", "discovered", "connected", "disconnected", "link_closed", "restore_central", "restore_peripheral", "service_missing", "services_modified", "connect_failed", "summary", "l2cap_failed", "write_failed"):
                        extra = {k: v for k, v in e.items() if k not in ("t", "ms", "kind")}
                        print(f"    [{side} +{(e['ms']-t0)/1000:7.1f}s] {e['kind']} {extra}")

if __name__ == "__main__":
    main()
