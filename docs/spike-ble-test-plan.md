# Bluetooth field test: the plan (LIME-103)

**What this answers:** can two iPhones with Lime find each other and pass data over Bluetooth with no internet, and how well does that work when Lime is open, in the background, or the phone is locked? The result decides how the offline mesh is built ([`architecture.md`](./architecture.md) section 7). **This is a throwaway test build**: it sends random signed bytes (200 B, 4 KB and 32 KB), never a real message, and nothing personal is logged.

You need **two iPhones** (Shem's 13 mini and Jean's 12 mini; both already have the test build installed), about **90 minutes**, and a room with one wall.

## Before you start (once)

1. **Jean's phone:** the first time, iOS may say the developer is not trusted. Go to **Settings → General → VPN & Device Management → Developer App → Trust**. (A free developer build lasts 7 days; after that it must be installed again from the Mac.)
2. On both phones: **Low Power Mode off**, **Do Not Disturb/Focus off**, Bluetooth **on**, and charge to **80% or more**. Unplug them for the test (a charging phone behaves differently).
3. Open Lime on each phone, then **Settings (your picture, top right) → About**, and **press and hold the Lime logo row for about a second**. The **Nearby test** screen opens. Allow Bluetooth when iOS asks ("Lime uses Bluetooth to pass messages between nearby teachers when there's no internet").
4. Call the phones **A** and **B** (Shem's = A, Jean's = B). **Note both battery percentages now** and write them on the results sheet at the bottom.

## How every scenario runs

1. On **both** phones, type the **scenario label** (given below, the same on both) in the box, set **Transport** to **Both**, leave "greeting" on, and tap **Start**. The label is saved with the log.
2. Wait up to a minute. The screen shows **Links: 2** or more when the phones have found each other. If nothing after one minute, note it ("no discovery") and carry on with the scenario's steps anyway.
3. Do the scenario's steps. To send test data, tap **All 3** on the phone the scenario says (it sends the 200 B, 4 KB and 32 KB blobs).
4. After about **5 minutes**, bring both phones back to the front, look at the counters ("sent / received") and tap **Stop** on both. Stopping closes that run's log.
5. Write the counters on the results sheet.

You do not have to read the log; it is saved. After the last scenario, share the logs (below).

## The scenarios

Keep both phones within **1 metre** unless the scenario says otherwise.

| # | Label (type exactly) | What to do |
|---|---|---|
| 1 | `1-both-open-1m` | Both Lime screens open on the Nearby test. After Links shows 2, tap **All 3** on A, then on B. Leave both open for 5 minutes. |
| 2 | `2-A-open-B-background` | After Links shows 2, press **Home on B** (Lime goes to the background). Wait 1 minute. On A tap **All 3**. Wait. After 5 minutes open B and read its counters. |
| 3 | `3-both-background` | After Links shows 2, tap **All 3** on A and **at once** press Home on A, then Home on B. Leave them 5 minutes (screens may dim, do not lock). Open both and read the counters. |
| 4 | `4-A-open-B-locked` | After Links shows 2, **lock B** (side button; screen off). Wait 1 minute. On A tap **All 3**. After 5 minutes unlock B and read its counters. |
| 5 | `5-both-locked` | After Links shows 2, tap **All 3** on A, then lock A, then lock B. Leave them 5 minutes. Unlock both and read the counters. |
| 6a | `6a-10m-same-room` | Both open. Put the phones about **10 metres** apart in the same room (a hall is fine), clear line of sight. Wait for Links, tap **All 3** on A, then on B. Walk back and read the counters. |
| 6b | `6b-through-one-wall` | Both open. Put **one wall** between the phones (about 3 to 5 metres). Same steps as 6a. |
| 7 | `7-airplane-bluetooth-on` | Turn on **Airplane Mode** on both phones, then turn **Bluetooth back on** (Control Centre) and make sure Wi-Fi is **off**. Both open. Same steps as scenario 1. (This proves it works with no internet at all.) |
| 8 | `8-B-force-quit` | After Links shows 2, **swipe Lime away on B** (force-quit: app switcher, swipe up). Wait 1 minute. On A tap **All 3**. After 5 minutes open Lime on B again and note whether anything arrived. (**Expected: nothing**, because iOS does not wake a force-quit app. This confirms it.) |

Between scenarios you may leave both phones open on the Nearby test screen. If a phone force-quit by accident or the app closed, note it.

## What to write down for each scenario

On the results sheet: the scenario number, whether the phones **found each other** (yes, no, after how long roughly), the **sent / received counters on each phone** at the end, and anything odd (an alert, the app closing, a long wait). The logs hold the exact times, signal strength (RSSI), sizes, speeds, reconnects, and when each phone was in the background or locked, so you do not need to time anything yourself.

## At the end

1. Note both **battery percentages** again and the **total minutes** the test took.
2. On **each phone**: Nearby test → **Share all** → **AirDrop** to the Mac (the logs are small text files, one per run, named like `nearby-2-A-open-B-background-….jsonl`).
3. Put both phones' files in one folder on the Mac and tell tend the folder. Tend reads them and writes `docs/spike-ble.md` with the results and a recommendation.

## Results sheet (copy this)

```
Start battery:  A __%   B __%        End battery:  A __%   B __%      Minutes: __
1  found? __   A sent/recv __/__   B sent/recv __/__   notes:
2  found? __   A __/__   B __/__   notes:
3  found? __   A __/__   B __/__   notes:
4  found? __   A __/__   B __/__   notes:
5  found? __   A __/__   B __/__   notes:
6a found? __   A __/__   B __/__   notes:
6b found? __   A __/__   B __/__   notes:
7  found? __   A __/__   B __/__   notes:
8  found? __   A __/__   B __/__   notes:
```

## What the test build does (for the curious)

- Each phone is **both** a peripheral (advertising one custom service) and a central (scanning for it), and connects to the other.
- It sends the blobs two ways, so they can be compared: **GATT** (the standard Bluetooth data channel: write with response, and notify) and an **L2CAP channel** (a faster stream). "Transport: Both" tries both; the log says which carried each blob.
- Each blob is **signed** with a throwaway key made for this test, and the receiver checks the signature (`signatureOK` in the log). A blob already received is counted as a duplicate.
- **State restoration** is on: if iOS ends the app in the background and Bluetooth has something to do, iOS may start it again, and the log records that (`restore_central`, `restore_peripheral`, and a new run named `…-relaunched`).
- The test build exists only in Debug builds. A release build has no Bluetooth code at all (`./ios/check-release-no-bluetooth.sh` checks this).
