# Lime's notification sound (not bundled yet)

Notifications use the iOS default sound, or none (Settings → Notifications → Sound). Lime's own chime
is not here yet, and nothing in this folder is a placeholder: **do not synthesise one.**

To add the chime when the file is ready (at most 2 s, WAV/AIFF/CAF, rights owned by the project):

1. Convert it to `lime-chime.caf` here (linear PCM; Apple requires 30 s or less):

   ```sh
   afconvert -f caff -d LEI16@44100 -c 1 input.wav ios/Lime/Resources/Sounds/lime-chime.caf
   ```

2. Run `xcodegen generate` (the folder is part of the app target, so the file is bundled).
3. In `Lime/Core/Notifications/NotificationSettings.swift` add a `limeChime` case to `NotificationSound`
   ("Lime chime"), make it the default, and use it in:
   - `SystemNotifications.schedule` (`UNNotificationSound(named: UNNotificationSoundName("lime-chime.caf"))`);
   - `SystemArrivalFeedback.playSound` (play the file with `AudioServicesCreateSystemSoundID`, which follows the silent switch).
