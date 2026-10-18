# Lime's sounds

- `lime-chime.caf`: the message chime (2.96 s, the user's own sound, LIME-152e). The default Sound in Settings → Notifications; used for local notifications
  (`UNNotificationSound(named:)`) and the in-app banner sound (`SystemArrivalFeedback`, which follows the silent switch).
- `lime-ring.caf`: the call ringtone (12.64 s, the user's own sound, LIME-152e; under iOS's 30 s limit). `CallRingtone.callKitSoundName` names it for CallKit's
  `CXProviderConfiguration.ringtoneSound` (LIME-111 uses it; it loops while ringing).

The originals stay **out of git**: only these converted files are committed. A new version drops in by replacing the CAFs (keep the names).

## The current three (LIME-152e, 2026-10-18)

The user's own sounds (rights theirs), processed by `ios/tools/process-sound.py` (`afconvert` only; pass `--loop` for the two that loop):

| File | Source | Duration | RMS | Peak | Seam (first 50 ms / last 50 ms, step) |
|---|---|---|---|---|---|
| `lime-chime.caf` | `lime-chime.m4a` (2.963 s, already trimmed by the user: not cut further) | 2.963 s | -16.0 dBFS | -5.6 dBFS | not a loop |
| `lime-ringback.caf` (the "Calling…" tone, looped by the app) | `lime-dialtone.m4a` (9.225 s) | 9.215 s | -16.0 dBFS | -9.9 dBFS | -13.9 / -18.4 dBFS, step 0 |
| `lime-ring.caf` (CallKit loops it; under 30 s) | `lime-ringtone.m4a` (12.637 s) | 12.637 s | -16.0 dBFS | -3.4 dBFS | -20.9 / -47.0 dBFS, step 0 |

Mono, 16-bit, 44.1 kHz CAF. Pure leading and trailing silence (below -60 dBFS) trimmed, keeping 5 ms; the level set to an RMS of -16 dBFS (no
file needed the -1 dBFS peak limit); an 8 ms raised-cosine fade at both ends of each file, and for the two loops the cut moved to the nearest zero
crossing, so a loop has no click at its seam (the last and first samples are both zero). The ringback starts and ends on sound, so it loops
with an 8 ms dip at the seam, not a pause.

## How the earlier ones were made

```sh
afconvert in.m4a in.wav -f WAVE -d LEI16@44100 -c 1      # decode to mono 16-bit
# gain: the chime +4.3 dB to about -16 dBFS RMS (peak -1.4 dBFS); the ringtone -1.0 dB so its peak is -1.0 dBFS (it was at 0 dBFS)
afconvert -f caff -d LEI16@44100 -c 1 in-normalised.wav ios/Lime/Resources/Sounds/lime-chime.caf
```

Loudness was set by RMS (no K-weighting tool was available), with a peak ceiling of -1 dBFS: it is close to, not exactly, -16 LUFS.

## The person's own sounds

Settings → Notifications → Add your own… picks a file, trims it (a message sound to 2 s, a call sound to under 30 s), converts it to CAF and
keeps it in `Library/Sounds` (where iOS looks for custom notification sounds), excluded from backup. They never leave the phone.
CallKit documents `ringtoneSound` as a sound **in the app bundle**, so a custom call sound plays in Lime's own ringing screen and the system
call screen uses the Lime steelpan.

## Call tones (LIME-118)

`lime-ringback.caf` is now the user's own sound (see above; it was a 6 s North American ringback, 440 + 480 Hz for 2 s and 4 s of silence),
`lime-connect.caf` (0.18 s, two soft notes when the media comes up) and `lime-end.caf` (0.30 s, a short descending pair when a call
ends) are plain sine tones made by `ios/tools/make-call-tones.py` (run `python3 ios/tools/make-call-tones.py`; it writes the two
CAFs here with `afconvert`). Level about -18 dBFS. They are lime's own: no Apple sounds and no third-party recordings. They play through
the call's audio session (play-and-record), so the silent switch does not mute them.
