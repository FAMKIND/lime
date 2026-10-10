# Lime's sounds

- `lime-chime.caf`: the message chime (1.2 s). The default Sound in Settings → Notifications; used for local notifications
  (`UNNotificationSound(named:)`) and the in-app banner sound (`SystemArrivalFeedback`, which follows the silent switch).
- `lime-ring.caf`: the call ringtone (25.9 s, under iOS's 30 s limit). `CallRingtone.callKitSoundName` names it for CallKit's
  `CXProviderConfiguration.ringtoneSound` (LIME-111 uses it; it loops while ringing).

The originals (`lime-message-chime.m4a`, `lime-call-steelpan.m4a`) are the project's, with rights confirmed, and stay **out of git**: only these
converted files are committed. A more produced version will drop in by replacing the two CAFs (keep the names).

## How they were made

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
