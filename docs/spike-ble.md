# Bluetooth spike: results and recommendation (LIME-103)

**Question:** can two iPhones running Lime find each other and pass encrypted blobs with no internet, and how well does that work with Lime open, in the background, or locked? This is the evidence for the offline mesh ([`architecture.md`](./architecture.md) section 7, DESIGN-01 section 4). It is **evidence, not a design**: where this suggests something changes, it is flagged for the planner, not decided.

**Short answer:** yes for the part that was tested. Two iPhones found each other in about a second, connected on their own, and passed signed blobs from 200 B to 32 KB in both directions, over a standard GATT link and over an L2CAP channel, with no internet (Airplane Mode, Bluetooth on) and with **no pairing prompt**. A phone that was backgrounded or locked **received data and kept its link for minutes**. A force-quit app is unreachable, as expected. **What this test did not show** is whether a phone that has been in the background for a long time (many minutes, when iOS suspends apps) still wakes and receives, and whether iOS ever restarts a terminated app for Bluetooth; section 5 says exactly what to test next.

## 1. What was tested

| | |
|---|---|
| Phones | **A:** iPhone 13 mini (`iPhone14,4`), iOS 26.6.2. **B:** iPhone 12 mini (`iPhone13,1`), iOS 26.5.2. |
| Build | the LIME-103 Debug build (`be3633a`), installed from the Mac with free (Personal Team) provisioning; `bluetooth-central` and `bluetooth-peripheral` background modes in Info.plist only (no entitlement was needed) |
| When | the night of 7 to 8 October 2026, about 85 minutes, eight scenarios, 19 log files (A: 9, B: 10), `~/Downloads/ble-logs/{A,B}/` |
| What each phone does | both advertise one service and scan for it (with the service filter) and connect to each other; blobs are random bytes signed with a throwaway Ed25519 key (no message, no user data); 200 B and 4 KB are sent automatically when a phone says hello, and **All 3** sends 200 B, 4 KB and 32 KB |
| How blobs travel | over **GATT** (write with response from the central, notify from the peripheral, 512-byte chunks) and over an **L2CAP channel** (published without encryption), both at once ("Both"); the receiver keeps the first copy and counts the other as a duplicate |

Reproduce the numbers below with `ios/analyze-ble-logs.py ~/Downloads/ble-logs [--timeline]`.

## 2. Results by scenario

Times are from the log timestamps; the phones' clocks agree to about a second. "Delivered" means the receiver verified the signature. All 81 blobs that arrived first (plus the duplicates) passed; **no blob failed its signature and none was corrupted** (`invalid` is 0 in every summary).

| # | Scenario | Discovery and connection | Delivered | Notes |
|---|---|---|---|---|
| 1 | both open, 1 m | first ever run: first discovery 7.2 s (this includes the Bluetooth permission prompt; B's first connect timed out once at 7.3 s, then connected at 8.0 s) | greeting (200 B + 4 KB) both ways at 9 s; All 3 both ways, twice (at 237 s and 556 s) | two automatic reconnects after a link timeout (at 17 s and 463 s). B went to the background and locked at 233 s, and **received All 3 four seconds later while locked** (not planned) |
| 2 | A open, B backgrounded | discovery 0.3 s, connected 1.3 s | **B received 200 B, 4 KB and 32 KB while backgrounded** (30 s after leaving the app); the data arrived over L2CAP and the GATT copies were duplicates | the link stayed up for the whole 8 minutes B was in the background; A kept seeing B's advertisement (overflow area) every 30 to 60 s |
| 3 | both backgrounded | discovery 0.6 s, connected 1.6 s | the All 3 sent as A was going to the background was received by B (still open) and the GATT tail completed after A had backgrounded; **no new send was possible while both were backgrounded** (a person has to tap) | the link survived about 4 minutes with both phones backgrounded; A's background scan saw B's advertisement at 36 s (B had just gone to the background); B saw A's at 27 s while B was still open |
| 4 | A open, B locked | discovery 0.6 s, connected 1.9 s | **B received 200 B, 4 KB and 32 KB while locked** (10 s after locking; the 32 KB over L2CAP in about 1.2 s) | one link timeout 10 s in ("The connection has timed out unexpectedly"), reconnected in 0.8 s; the link stayed up for the 5 minutes B was locked |
| 5 | both locked | discovery 0.3 s, connected 1.3 s | the All 3 sent just before locking was delivered (before the phones locked) | **links held for the 5 minutes both phones were locked** (no disconnect until B was unlocked and stopped); nothing could be sent while locked |
| 6a | 10 m, same room, both open | discovery 0.4 s | all three sizes, both ways | RSSI -45 to -71 dBm; no drops |
| 6b | through one wall, both open | discovery 0.5 s | all three sizes, both ways | RSSI about -83 to -84 dBm at the wall (-38 to -50 when near); one link timeout at 76 s, automatic reconnect |
| 7 | Airplane Mode + Bluetooth, both open | discovery 0.1 s, connected 1.4 s | greeting both ways; **B's All 3 reached A** (A's All 3 was not tapped) | works with no internet at all |
| 8 | B force-quit | n/a | **nothing after the quit** (see the caveat below) | after B was swiped away A's links closed, A reconnected twice to B's Bluetooth radio but **found no Lime service** (`service_missing`), and A kept seeing B's advertisement (overflow) for about a minute |

**Scenario 8 caveat.** In the log, A's "All 3" was sent at 124 s and B received it, then B was swiped away at about 186 s; **A did not send again after the quit**, so "nothing received while quit" is true but trivially so. The indirect evidence is strong: after the quit A could connect to B's phone but the Lime service was gone, so GATT and L2CAP were unreachable. When B opened Lime again at 284 s, the test resumed (a new log, `…-relaunched`, with `app foreground` as its first event, so that was the person opening the app, not iOS starting it).

**Time from "both running" to first data** (the later phone's Start to the first blob received): 0.5 to 1.6 seconds in scenarios 2 to 8 (median 0.8 s), 9.0 seconds in scenario 1 (first ever run, with the permission prompt).

## 3. Throughput

The log's duration fields were overwritten by a logging bug (section 6), so the figures below are recovered from the logged kbit/s, which was computed from the true duration. Receiver times run from the first byte of a blob to the last; "send" times are how long the sender took to hand a blob to Bluetooth. Sizes are the random body; add 109 bytes of signature and framing. The sample is small (one pair of phones, one room), so read these as orders of magnitude.

| Transport | 200 B | 4 KB | 32 KB |
|---|---|---|---|
| **L2CAP** (receiver) | not measured (under the timer's resolution) | **89 ms median** (59 to 150 ms; about 380 kbit/s) | **1.26 s median** (1.08 to 1.62 s; about 210 kbit/s) |
| **GATT notify** (peripheral to central; sender time) | instant | 34 ms median (flow-controlled handoff) | **2.3 s median** (2.29 to 2.68 s; about 115 kbit/s) |
| **GATT write with response** (central to peripheral; sender time) | 80 ms median | 2.0 s median (0.6 to 4.8 s) | **5.1 s median** (4.5 to 6.9 s; about 52 kbit/s) |

- **L2CAP was first for every 32 KB blob** (15 of 15) and for every 4 KB blob sent after the channel was open (18); the 15 other 4 KB blobs were the greetings, sent over GATT before the channel existed. GATT won 22 of the 33 first arrivals of 200 B blobs (a tiny blob finishes at about the same moment either way).
- **L2CAP is about 4 times faster than GATT notify and about 4 to 5 times faster than a GATT write** for 32 KB.
- The negotiated sizes were the same everywhere: a 512-byte GATT write or notification.
- **Latency** (sender's clock to receiver's clock, so only roughly right): median 0.19 s, range 13 ms to 1.8 s over 81 blobs.

## 4. What iOS allowed, and what it blocked

**Allowed (observed):**
- **Free provisioning is enough.** The Bluetooth background modes are Info.plist keys, not entitlements; the build signed, installed and ran on both phones with a Personal Team profile. (A free build expires after 7 days.)
- **Both roles at once.** Each phone was a central and a peripheral at the same time, found the other, and connected both ways. The result is **two GATT links and two L2CAP channels per pair**, which a mesh must collapse (the test did it with a random per-run tag exchanged in a hello frame).
- **Discovery works in the background in both directions.** A backgrounded advertiser is found by a foreground scanner (its advertisement moves to the "overflow" area: 51 of the 89 discovery events were overflow adverts) and by a backgrounded scanner (scenario 3). A scan with the service filter, as iOS requires in the background, found it.
- **L2CAP works with no pairing and no encryption**, published and opened in every scenario, including while the receiver was backgrounded or locked (scenario 4: 32 KB received while locked). No pairing prompt ever appeared.
- **A backgrounded or locked app receives and processes data at once** (the receive timings while backgrounded or locked are the same as in the foreground).
- **Links persist** for minutes while both apps are backgrounded or locked (4 to 5 minutes, scenarios 3 to 5; 8 minutes for the backgrounded side in scenario 2).
- **Automatic reconnection is reliable but needed:** four "connection timed out unexpectedly" drops in about 85 minutes (each seen by both phones; at 10 s, 17 s, 76 s and 463 s into a run), plus one connect that timed out at the very first start. That is about one drop per 20 minutes, even 1 m apart; each recovered within about a second when the client re-issued the connect.
- **When a phone's service list changes** (the other phone restarted its test), the first service discovery returned nothing (`service_missing`) and iOS then reported `services_modified`; discovering again worked. A mesh must handle "service changed".
- **No Bluetooth traffic needs the internet**, confirmed in Airplane Mode.

**Blocked or not allowed:**
- **A force-quit app does nothing.** Its Bluetooth service disappears (`service_missing`); the other phone can still connect to the radio but there is nothing to talk to.
- **An app cannot originate a send while it is backgrounded and idle** (nothing wakes it unless Bluetooth delivers an event). Scenarios 3 and 5 could not start a send; this is why section 5 matters.
- **A background advertisement carries only the service UUID**, so identifying the phone has to happen after connecting (we used a hello frame). There is no name or other data in a background advertisement.

**Not tested, so unknown:**
- Delivery to a phone that has been **backgrounded or locked for a long time**. The receiving phone was only 10 to 30 seconds past leaving the app when data arrived (scenarios 2 and 4), because the field script had the sender wait about 30 seconds, not minutes. Whether iOS suspends the app and still wakes it to deliver is the main unknown. The links did stay up for minutes with both apps backgrounded or locked, which is encouraging but is not delivery.
- **State restoration was never exercised.** The `restore_peripheral` events in the logs are the same-process managers being re-created; there was no run in which iOS ended the app and started it again for Bluetooth. (A user force-quit is the one case iOS never relaunches.)
- Behaviour with more than two phones, with relaying (any multi-hop), at the edge of range (the wall at -83 dBm still worked), or across iOS versions (only 26.5 and 26.6).

## 5. The next test (from the field test's own note)

The user's suggestion is the right one: **automatic queued sending**, because scenarios 3 and 5 showed the part that matters most for a mesh (a phone in a pocket with something to deliver when it meets another phone) cannot be tested by a person tapping. Proposed as a separate brief, **LIME-103b**, to run in about an hour with the same two phones:

1. **Queue then walk in:** A holds queued blobs (3 sizes). Both phones locked, then B moves out of range (another room, 15 minutes) and comes back, **no one touching either phone**. Success: B received the queue after the phones met again, and the log shows what woke each app and when.
2. **Long background receive:** B locked for 15 minutes, 30 minutes and 60 minutes with Lime not force-quit; A (open) sends All 3 at the end of each. Success: B receives; the log shows the app phase and how long the wake took.
3. **System-ended app:** put B under memory pressure (open many apps) while locked, then have A send, to see whether iOS restarts Lime for Bluetooth (the `restore_*` events and a relaunched run without an `app foreground` event).
4. **Scenario 8 properly:** force-quit B, wait, then A taps All 3, to record the result of a send to a dead app rather than infer it.
5. **A battery run:** an hour in the background with both phones' screens off and nothing sent, to put a number on the radio cost (section 6).

**Fix first (all in the Debug-only spike code):** the duration logging bug and the blank share sheet (section 6), and send the greeting again when a link re-forms, not only once per run, so a reconnect after a walk-in triggers data without a tap.

## 6. Battery, and problems with the test itself

- **Battery:** over the 85-minute session A went from 83% to 69% (14 points) and B from 100% to 88% (12 points), with the radios scanning, advertising and connected the whole time and the screens on for much of it (the field script has people tapping and reading). That is an **upper bound on the cost of Bluetooth, not a measurement of it**; the battery run in section 5 is the way to get the real number.
- **The log's duration fields were wrong.** `NearbyLog.record` writes the event's epoch time under the key `ms`, which overwrote the `ms` duration of `send_done`, `recv_done` and `recv_dup`. The kbit/s was computed first and is correct, which is how section 3 was recovered; but the **duplicate arrivals' timings are lost**, so the GATT and L2CAP arrival times could not be compared for the same blob. Fix before any re-run (rename the duration to `durMs`).
- **"Share all" showed a blank share sheet** on both phones (noted in `TEND.md`), so the logs were copied from the app's data container over USB (`xcrun devicectl device copy from …`).
- **The first run included a permission prompt**, so its 7.2 s first discovery is not a typical discovery time.
- **Everything ran with the two phones' screens often on and 1 m apart** except scenarios 6a and 6b.
- **One pair of phones, two iOS versions, one place.** Nothing here is statistical.

## 7. Recommendation for mesh v1

These are recommendations from the evidence, for the planner to confirm.

1. **Use both: GATT to meet, L2CAP to move data.** GATT is needed regardless (the L2CAP PSM was read from a GATT characteristic, and the hello and identification happened there). Move envelopes over **L2CAP when it opens** (about 4 to 5 times faster, unpaired, and it worked while the receiver was locked), and fall back to GATT notify/write for small items or when the channel fails. At envelope sizes of a few KB either is under a couple of seconds; L2CAP matters for bulk and for a short contact window between two people walking past each other.
2. **Plan for the phone being known only after connecting.** Background advertisements carry nothing but the service UUID, so identify and de-duplicate links by a hello after connect, and **choose one link per pair** (the test got two of each; a deterministic rule such as "the lower identifier initiates" avoids it). Treat the link as untrusted and unauthenticated (it was unpaired and unencrypted): everything of value must be in the sealed, signed envelope, which is already the design.
3. **Make transfers resumable and idempotent.** Links dropped about every 20 minutes even at 1 m. The mesh's "what I have" summaries and hash-based de-duplication already fit; add per-envelope acknowledgement and re-issue the connect after a drop.
4. **Realistic expectations to write down:** it works while Lime is open or has been recently used; a phone that Lime has been left running on (not force-quit) in a pocket keeps its link and received data in these tests; **a force-quit Lime is invisible to the mesh**; and nothing yet proves delivery to a phone that has been idle in the background for long (section 5). Do not promise "works with the app closed" in the product until the next test.
5. **UX implications:** a one-time Bluetooth permission explainer before the system prompt (the prompt delayed the first discovery in scenario 1, and the first connection timed out once); a "Nearby" status somewhere visible (on, looking, a phone found, or off because Bluetooth is off or permission is denied); and a gentle note that swiping Lime away stops nearby delivery. A "Nearby mode" the teacher switches on is plausible but is not required by the evidence: the radios ran for 85 minutes without any visible side effect other than battery.

## 8. Flags for the planner (not decisions)

- **`architecture.md` section 7, "the key open question: how well iPhones relay with the app closed."** The answer so far splits: *force-quit* is a hard no; *backgrounded or locked* works for the cases tested (minutes, with an active link) but long-idle behaviour is unproven. The wording of the open question, and any promise in DESIGN-01 section 4, should say "force-quit" and "idle" separately.
- **"Wire format borrowed from bitchat."** Bitchat is GATT-only. This test suggests L2CAP is considerably faster; if the wire format must interoperate with bitchat, that is a decision the plan should make deliberately.
- **DESIGN-01 section 4 ("someone you meet and scan in person")** is unaffected by these results.
- **The Debug spike signs with a throwaway CryptoKit key, not the account's device key,** because the core has no signing call. Mesh v1 will need the core to sign and verify envelopes, which is already planned; nothing here needs to change for that.
- The 7-hop, 72-hour limits are unaffected: per-hop transfer is fast enough that the limits are about contact opportunities, not bandwidth.
