#!/usr/bin/env python3
"""LIME-103c: reconciles an unattended Auto test between two phones (the sender's and the receiver's logs) and prints what
docs/spike-ble.md reports for the both-asleep run.

    ios/analyze-auto-logs.py A.jsonl B.jsonl [B2.jsonl ...]     (the sender's log, then every receiver log of the run)

The sender's `auto_created` / `auto_sent` / `auto_ack` events say when each blob was due, when it went out and when the
receiver acknowledged it; the receiver's `auto_recv` events say what it logged itself. The two are compared by key (tick-size).
Where the receiver's log is silent but the sender's acks show it was alive, that is reported as a hole in the receiver's log.
"""
import json, statistics, sys
from collections import Counter, defaultdict

def read(path):
    return [json.loads(line) for line in open(path)]

def fmt(seconds):
    seconds = int(round(seconds))
    h, m, s = seconds // 3600, seconds % 3600 // 60, seconds % 60
    return f"{h} h {m:02d} m" if h else (f"{m} m {s:02d} s" if m else f"{s} s")

def main(sender_path, receiver_paths):
    a = read(sender_path)
    bs = [e for p in receiver_paths for e in read(p)]
    start = next(e for e in a if e["kind"] == "started")["ms"]
    minutes = lambda ms: (ms - start) / 60000
    created = {e["key"]: e for e in a if e["kind"] == "auto_created"}
    acks = {e["key"]: e for e in a if e["kind"] == "auto_ack"}
    sent = defaultdict(list)
    for e in a:
        if e["kind"] == "auto_sent":
            sent[e["key"]].append(e)
    summary = next((e for e in a if e["kind"] == "summary"), None)
    print(f"Run: {len(created)} blobs due over {fmt(summary['seconds']) if summary else '?'}; {len(acks)} acknowledged by the receiver; "
          f"{sum(1 for e in a if e['kind'] == 'send_done')} sends in all (retries and repeats included)")

    # When was the sender itself running? Its ticks are created late when iOS had it suspended.
    print("\nThe sender's ticks (a tick is due every 5 minutes; 'created' is when the app actually ran it):")
    buckets = defaultdict(list)
    for key, e in created.items():
        buckets[round(minutes(e["ms"]))].append(e)
    for minute in sorted(buckets):
        group = buckets[minute]
        lates = [e["lateMs"] / 1000 for e in group]
        print(f"  at {minute:>3} min: {len(group):>2} blobs created, {fmt(min(lates))} to {fmt(max(lates))} after they were due")
    wakes = [(minutes(e["ms"]), e["source"], e["count"]) for e in a if e["kind"] == "wake"]
    print("  Bluetooth wake events logged:", ", ".join(f"{m:.0f} min {s} (#{c})" for m, s, c in wakes))
    print("  App phases:", ", ".join(f"{minutes(e['ms']):.0f} min {e['phase']}" for e in a if e["kind"] == "app"))

    # How late was each blob acknowledged, against when it was due?
    lates = {k: (acks[k]["ms"] - created[k]["scheduledMs"]) / 1000 for k in acks if k in created}
    print("\nAcknowledged against the time each blob was due:")
    for limit in (10, 60, 900, 3600, 4 * 3600):
        print(f"  within {fmt(limit):>8}: {sum(1 for v in lates.values() if v <= limit):>2} of {len(created)}")
    print(f"  median {fmt(statistics.median(lates.values()))}, latest {fmt(max(lates.values()))}")

    # What the receiver logged itself.
    got = {f"{e['tick']}-{e['size']}": e for e in bs if e["kind"] == "auto_recv"}
    dups = sum(1 for e in bs if e["kind"] == "recv_dup")
    relaunch = [e for e in bs if e["kind"] == "wake" and e.get("source") == "restore"]
    first_b = min((e["ms"] for e in bs if e["kind"] == "auto_recv"), default=None)
    print(f"\nThe receiver's own log: {len(got)} blobs received, {dups} repeats (duplicates), {len(relaunch)} state-restoration launch(es)")
    if got:
        print("  by app state:", dict(Counter(("locked" if e["locked"] else "unlocked") + "/" + e["appState"] for e in got.values())))
        print("  by link:", dict(Counter(e["transport"] for e in got.values())))
        late = [e["lateMs"] / 1000 for e in got.values()]
        print(f"  lateness against the due time: median {fmt(statistics.median(late))}, latest {fmt(max(late))}; "
              f"{sum(1 for v in late if v <= 10)} within 10 s")
    before = [k for k, e in acks.items() if first_b and e["ms"] < first_b]
    after = [k for k, e in acks.items() if first_b and e["ms"] >= first_b]
    only_sender = [k for k in acks if k not in got]
    print(f"\nReconciliation: {len(before)} blobs were acknowledged before the receiver's log has its first arrival ({fmt((first_b - start) / 1000) if first_b else '?'} into the run),")
    print(f"  {len(after)} after; {len(only_sender)} acknowledged blobs are absent from the receiver's log: "
          f"{'a hole in the receiver log, the receiver was alive (it acknowledged them) but logged nothing' if only_sender else 'none'}")
    missing = [k for k in created if k not in acks]
    print(f"  never acknowledged: {len(missing)}")

if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2:])
