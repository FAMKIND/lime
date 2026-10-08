# Bluetooth spike: results and recommendation (LIME-103, LIME-103b)

**Question:** can two iPhones running Lime find each other and pass encrypted blobs with no internet, and how well does that work with Lime open, in the background, or locked? This is the evidence for the offline mesh ([`architecture.md`](./architecture.md) section 7, DESIGN-01 section 4). It is **evidence, not a design**: where this suggests something changes, it is flagged for the planner, not decided.

**Short answer:** yes, and the long-idle question now has an answer. Two iPhones found each other in about a second, connected on their own, and passed signed blobs from 200 B to 32 KB in both directions, over a standard GATT link and over an L2CAP channel, with no internet and with **no pairing prompt**. A force-quit app is unreachable, as expected. **The overnight test (LIME-103b, section 5) showed that a phone locked, in the background and unplugged on a table received every blob a nearby awake phone sent for 6.3 hours (89 of 89, longest idle stretch 4 h 7 m with all 57 delivered), with each blob acknowledged within about half a second of its schedule.** What is **still unproven** is two phones that are *both* asleep (nothing in the overnight run had to start a transfer from a sleeping phone), a system-ended app being restarted for Bluetooth, and a force-quit re-check; section 5 lists them and section 7 says what the product can and cannot promise today.

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
- *(Answered by the overnight test, section 5.)* Delivery to a phone that has been **backgrounded or locked for a long time**: in the first field test the receiving phone was only 10 to 30 seconds past leaving the app when data arrived (scenarios 2 and 4). The overnight run shows it keeps receiving for hours.
- **State restoration was never exercised, in either test.** The `restore_peripheral` events in the first logs are the same-process managers being re-created, and the sender's overnight log has no `restore_*` events at all (the receiver's log was not available, so a relaunch of the receiver cannot be ruled out, but its card shows an unbroken record). Whether iOS relaunches a *system-ended* app for Bluetooth is unknown. (A user force-quit is the one case iOS never relaunches.)
- Behaviour with more than two phones, with relaying (any multi-hop), at the edge of range (the wall at -83 dBm still worked), or across iOS versions (only 26.5 and 26.6).

## 5. The overnight test (LIME-103b): a locked phone, a whole night

**Setup.** Phone A (iPhone 13 mini, iOS 26.6.2) was the **sender**: awake, open on the test screen and plugged in. Phone B (iPhone 12 mini, iOS 26.5.2, Jean's) was the **receiver**: locked, **unplugged**, left on the table about 1 to 2 m away, with Lime in the background (never swiped away). The night started at 04:58 UTC on 8 October and ran **6.3 hours** (the sender's log; the message with the results said about 7.3 h, the cards and the log both say 6.3 h). A made one signed 4 KB blob every 5 minutes and a 32 KB blob every 30 minutes (89 blobs in all: the cards read 88 when they were photographed, 89 in the log at the end) and kept each queued, re-sending every 90 seconds until B acknowledged it. Jean picked B up four times (the flashlight). Both phones' summary cards were read in the morning; **A's log was copied from the phone and analysed below; B's log was not available, so everything about B is from its card.**

**Results**

| | Sender A (log and card) | Receiver B (card) |
|---|---|---|
| Delivered | created 89, sent 89, **delivered (acknowledged) 89**; no misses | **received 89 of 89 expected**; no misses |
| Longest gap | 6.6 min between acknowledged blobs (the schedule is 5 min) | 5 min |
| Long idle stretch | n/a (A was awake) | **longest idle stretch with no pickups: 4 h 7 m, delivered 57 of 57 in it**; all idle time 6.3 h, delivered 88 of 88 |
| What B was doing at each arrival | n/a | **87 arrivals while locked**, 2 while unlocked with Lime behind another app (the pickups), 0 with Lime in front; the longest run of back-to-back arrivals all while locked was **56, over 3 h 55 m** |
| Battery | plugged in (not a measurement; the card's 80%→80% only means it had no sample, the log's last reading was 100%, full) | **85% → 75%** over 6.3 h |

**How promptly each blob arrived (from A's acknowledgements).** Measured from the blob's schedule to its acknowledgement, the **median was 0.5 s**, the 90th percentile 1.8 s, and the round trip from the last send to the acknowledgement a median of 0.33 s (maximum 1.8 s). **87 of 89 blobs were delivered on the first attempt.** The other two (a 32 KB blob at about 1.5 h and a 4 KB one at about 6 minutes) were hit by a link drop, were re-sent by the queue 90 seconds later, and arrived 95 and 96.5 seconds after their schedule; **the store-and-forward queue did its job**. A blob never failed its signature (`invalid` 0 on A; B's card shows no misses).

**What this says:**
- **A locked, backgrounded, unplugged iPhone keeps receiving for hours.** iOS woke Lime on B for essentially every arrival, within about half a second of the data being sent, over a night, with the screen off. 87 of the 89 blobs arrived while the phone was locked. This answers the main open question of section 4 for the **receiving** side.
- **Links dropped a lot, and recovered by themselves.** A logged **39 link drops in 6.3 hours** ("The connection has timed out unexpectedly"; about 6 an hour, a median of 8 minutes apart, spread over every hour of the night), against 4 in 85 minutes in the first test. iOS reconnected on its own (about 0.7 s typical) and the queue re-sent what had not been acknowledged. This is the strongest argument for resumable, idempotent transfers (section 7, item 3).
- **No relaunches and no restoration were seen.** A's log has no `restore_*` events, no `service_missing` and no `services_modified` all night. B's own log was not available, so B being restarted by iOS cannot be ruled out, but its card shows no misses; the system-ended case is still untested. One connect attempt timed out (at about 3 hours) and recovered.
- **iOS's wake-ups were not the limit.** The sender's log counts 626 Bluetooth callbacks (102 log lines) while it was awake; what matters is that B's side woke for each arrival.

**What this does not say:**
- **Both phones asleep.** A was awake, so something always started each transfer. **Nothing in this run shows a locked phone starting a transfer, or two locked phones meeting.** In the first test a backgrounded phone's scan did discover the other (scenario 3), which is the wake that would start one, but a transfer started that way has not been run.
- **A system-ended app** (memory pressure) being restarted by iOS for Bluetooth.
- **A force-quit check was not run this time**; scenario 8 of the first test stands (the service disappears; the evidence is indirect).
- **Moving phones.** Everything was within 1 to 2 m on a table. The two-phone, two-iOS-version, one-place sample is still small.
- **Battery per hour** is only the receiver's 10 points over 6.3 h (about 1.6 points an hour including the four pickups and whatever the phone does with the screen off anyway); a quiet phone with Bluetooth off was not measured, so the cost of the radio alone is somewhere below that.

**Still to test (LIME-103c, if the planner wants it).** The same overnight run with **both phones locked**: untick "Keep the screen on" on the sender, so the sender is also asleep; its card then reports how many Bluetooth wake-ups it got and how late its ticks were made. Add a walk-in (B out of range for an hour, then back, nobody touching either phone), and optionally a memory-pressure run and the 2-minute force-quit check. No new code is needed for the first of these.

## 6. Battery, and problems with the test itself

- **Battery:** over the 85-minute session A went from 83% to 69% (14 points) and B from 100% to 88% (12 points), with the radios scanning, advertising and connected the whole time and the screens on for much of it (the field script has people tapping and reading). That is an **upper bound on the cost of Bluetooth, not a measurement of it**. The overnight receiver (screen off, unplugged, 4 pickups) lost 10 points in 6.3 hours (section 5), a better upper bound; the radio alone is somewhere below it.
- **The log's duration fields were wrong in the first test** (the epoch time overwrote the `ms` duration of `send_done`, `recv_done` and `recv_dup`); the kbit/s was correct, which is how section 3 was recovered, but the duplicate arrivals' timings are lost. **Fixed in LIME-103b:** durations are `duration_ms` and a field can no longer overwrite the log's own keys (tested). The overnight logs have correct durations.
- **"Share all" showed a blank share sheet** on both phones in the first test, so the logs were copied from the app's data container (`xcrun devicectl device copy from …`). LIME-103b presents the sheet differently, **unverified**; the overnight logs were again copied this way. A's copied over USB; **B's could not be copied** (Jean's phone was not connected, and the wireless copy failed with "Connection reset by peer"), which is why section 5 has no B log.
- **The first run included a permission prompt**, so its 7.2 s first discovery is not a typical discovery time.
- **Everything ran with the two phones' screens often on and 1 m apart** except scenarios 6a and 6b.
- **One pair of phones, two iOS versions, one place.** Nothing here is statistical.

## 7. Recommendation for mesh v1

These are recommendations from the evidence, for the planner to confirm.

1. **Use both: GATT to meet, L2CAP to move data.** GATT is needed regardless (the L2CAP PSM was read from a GATT characteristic, and the hello and identification happened there). Move envelopes over **L2CAP when it opens** (about 4 to 5 times faster, unpaired, and it worked while the receiver was locked), and fall back to GATT notify/write for small items or when the channel fails. At envelope sizes of a few KB either is under a couple of seconds; L2CAP matters for bulk and for a short contact window between two people walking past each other.
2. **Plan for the phone being known only after connecting.** Background advertisements carry nothing but the service UUID, so identify and de-duplicate links by a hello after connect, and **choose one link per pair** (the test got two of each; a deterministic rule such as "the lower identifier initiates" avoids it). Treat the link as untrusted and unauthenticated (it was unpaired and unencrypted): everything of value must be in the sealed, signed envelope, which is already the design.
3. **Make transfers resumable and idempotent.** Links dropped about every 20 minutes even at 1 m. The mesh's "what I have" summaries and hash-based de-duplication already fit; add per-envelope acknowledgement and re-issue the connect after a drop.
4. **What the product can promise today, and what it cannot.** From the evidence:
   - **Can say:** *"Lime can receive messages over Bluetooth while your iPhone is locked or Lime is in the background, as long as you have not swiped Lime away and someone nearby with Lime open is sending."* Proven for a whole night (6.3 h, 89 of 89, 4 h of it with nobody touching the phone), on one pair of phones.
   - **Should say, as a limit:** *"If you swipe Lime away (force-quit), nearby delivery stops until you open it again."* The Bluetooth service disappears when the app is gone; this was seen in the first test (the check was not repeated).
   - **Must not yet say:** that two phones that are both locked in pockets will pass messages to each other, or that Lime relays for strangers while it is not open. Nothing yet shows a sleeping phone starting a transfer, and relaying means exactly that. Until the both-asleep test (section 5), the mesh should be described as working **"when at least one of the two phones has Lime open or has just been used"**, which is the case that has been proven and the one that matches carrying a phone around and opening it.
   - **The word "closed":** everyday users mean "locked / in the background"; engineers mean "force-quit". The product copy should use the first meaning only with the "not swiped away" condition, and never promise the second.
5. **UX implications:** a one-time Bluetooth permission explainer before the system prompt (the prompt delayed the first discovery in scenario 1, and the first connection timed out once); a "Nearby" status somewhere visible (on, looking, a phone found, or off because Bluetooth is off or permission is denied); and a gentle note that swiping Lime away stops nearby delivery. A "Nearby mode" the teacher switches on is plausible but is not required by the evidence: the radios ran for 85 minutes without any visible side effect other than battery.

## 8. Flags for the planner (not decisions)

- **`architecture.md` section 7, "the key open question: how well iPhones relay with the app closed."** The answer now splits three ways: *force-quit* is a hard no; *a locked or backgrounded phone receiving from an awake phone* works, proven for a whole night; *both phones asleep, or a phone relaying while asleep* is **unproven** (the overnight run did not need a sleeping phone to start a transfer). The wording of the open question, the plot's rule that the product must not promise "works with the app closed" until the long-idle case is proven (it is, for receiving), and any promise in DESIGN-01 section 4 should say "force-quit", "locked and receiving" and "both asleep" separately. **A second overnight run with both phones locked would settle the third; it needs no new code.**
- **"Wire format borrowed from bitchat."** Bitchat is GATT-only; L2CAP was about 4 to 5 times faster here. (The plan has since decided against bitchat wire compatibility; this note stands only as the evidence for it.)
- **DESIGN-01 section 4 ("someone you meet and scan in person")** is unaffected by these results.
- **The Debug spike signs with a throwaway CryptoKit key, not the account's device key,** because the core has no signing call. Mesh v1 will need the core to sign and verify envelopes, which is already planned; nothing here needs to change for that.
- The 7-hop, 72-hour limits are unaffected: per-hop transfer is fast enough that the limits are about contact opportunities, not bandwidth.
