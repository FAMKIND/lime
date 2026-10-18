# Lime's sounds

- `lime-chime.caf`: the message chime (2.96 s, the user's own sound, LIME-152e). The default Sound in Settings → Notifications; used for local notifications
  (`UNNotificationSound(named:)`) and the in-app banner sound (`SystemArrivalFeedback`, which follows the silent switch).
- `lime-ring.caf`: the call ringtone (12.64 s, the user's own sound; under iOS's 30 s limit). `CallKitSystem` hands `CallRingtone.callKitSoundName` to
  `CXProviderConfiguration.ringtoneSound` (LIME-152g; before that nothing assigned it and CallKit played the phone's default ringtone, although this file
  said it did); it loops while ringing. The log line `callkit ringtone=lime-ring.caf found=true` says the file resolved in the bundle.

The originals stay **out of git**: only these converted files are committed. A new version drops in by replacing the CAFs (keep the names).

## The current three (LIME-152g, 2026-10-18)

The user's own sounds (rights theirs), processed by `ios/tools/process-sound.py` (`afconvert` and `afinfo` only; pass `--loop` for the two that loop).
**The rule: as the source.** Stereo stays stereo, the sample rate is the source's, linear PCM 16-bit, **no loudness normalisation**. Only pure
leading and trailing silence (below -60 dBFS) is trimmed, keeping 5 ms; a peak ceiling of -1 dBFS lowers the whole file only if the source peaks
above it; an 8 ms raised-cosine fade at both ends, and for the two loops the cut moved to the nearest zero crossing so a loop has no click at its seam.
(LIME-152e had made them mono and set every file to an RMS of -16 dBFS, which changed how they sound.)

| File | Source | Format | Duration | RMS | Peak (source peak) | Seam (first 50 ms / last 50 ms, step) | Size |
|---|---|---|---|---|---|---|---|
| `lime-chime.caf` | `lime-chime.m4a` (stereo AAC, 2.963 s) | 2 ch, 44.1 kHz, 16-bit | 2.963 s | -14.2 dBFS | -1.0 (source 0.0, lowered 1 dB) | -27.6 / -22.0 dBFS, not a loop | 527 KB |
| `lime-ringback.caf` (the "Calling…" tone, looped by the app) | `lime-dialtone.m4a` (stereo AAC, 9.225 s) | 2 ch, 44.1 kHz, 16-bit | 9.215 s | -9.2 dBFS | -1.0 (source 0.0, lowered 1 dB) | -7.1 / -12.5 dBFS, step 0 | 1.6 MB |
| `lime-ring.caf` (CallKit loops it; under 30 s) | `lime-ringtone.m4a` (stereo AAC, 12.637 s) | 2 ch, 44.1 kHz, 16-bit | 12.637 s | -17.8 dBFS | -4.8 (unchanged) | -22.8 / -48.5 dBFS, step 0 | 2.2 MB |

The three together are about 4.4 MB (they were 2.2 MB as mono). The ringback starts and ends on sound, so it loops with an 8 ms dip at the seam,
not a pause.

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
