# Bluetooth overnight test: the plan (LIME-103b)

Two phones on a table, about 2 minutes of setup, then bed. **A** = Shem's iPhone (the sender), **B** = Jean's iPhone (the receiver, locked and left alone; picking it up now and then is fine, just never swipe Lime away).

1. **Power:** plug **A** in for the night. **B** stays **unplugged** (that gives the battery reading); if it is below 50%, plug it in and say so.
2. **Both phones:** Bluetooth on, Low Power Mode off, and never swipe Lime away (leave it wherever it is when you lock).
3. **B first:** open Lime → Settings (your picture) → About → press and hold the Lime logo for a second → **Auto test (overnight)…** → choose **Receiver** → **Start**, then press the side button to **lock B**.
4. **Then A:** the same way → choose **Sender** → leave "Keep the screen on" ticked → **Start**. Leave A open on that screen, plugged in, within 2 metres of B.
5. **Check after a minute:** A's summary shows "Created 2 · sent 2 · delivered 2" (the first blobs are made at once). If it says delivered 0, tap Stop on both and Start again (B first).
6. **In the morning:** open the Auto test screen on both phones and **screenshot the summary card on each** (leave the test running or tap Stop; the card stays). Send both screenshots. Optional, 2 minutes: tick "2-minute force-quit check" on both, Start B, then swipe Lime away on B, wait 4 minutes, open Lime on B again, and screenshot both cards.

If the share sheet is empty, the logs can still be copied over USB (see "Nearby test logs" in `ios/README.md`).
