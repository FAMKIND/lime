# Android icons: SF Symbol → Material Symbol

The Android app draws glyphs as vector paths (`ui/shell/TabIcons.kt` and siblings) taken from Material Symbols (Apache 2.0). This table lists the SF Symbols iOS uses on the tabs and in the sign-in, chat list and chat screens (LIME-296–298) and the Material Symbol that replaces each. A row is drawn when its screen needs it.

| Where | SF Symbol | Material Symbol | Drawn |
|---|---|---|---|
| tab link | `message` | `chat_bubble` (outlined) | yes (295) |
| tab call | `phone` | `call` | yes (295) |
| tab jam | `quote.closing` | `format_quote` | yes (295) |
| confirm, selected, sent | `checkmark` | `check` | |
| delivered, read | `checkmark` ×2 | `done_all` | |
| done / valid | `checkmark.circle.fill` | `check_circle` (filled) | |
| verified | `checkmark.seal.fill` | `verified` (filled) | |
| search | `magnifyingglass` | `search` | |
| forward, disclosure | `chevron.right` | `chevron_right` | |
| back | `chevron.left` | `arrow_back` (system back gesture first) | |
| up / down (find) | `chevron.up` / `chevron.down` | `keyboard_arrow_up` / `keyboard_arrow_down` | |
| close / clear | `xmark` / `xmark.circle.fill` | `close` / `cancel` (filled) | |
| delete | `trash` | `delete` | |
| new chat / add | `plus` | `add` | |
| emoji | `face.smiling` | `mood` | |
| send | `arrow.up` | `arrow_upward` | |
| open link | `arrow.up.right` | `open_in_new` | |
| forward message | `arrowshape.turn.up.right` | `forward` | |
| edit | `pencil` | `edit` | |
| photo | `photo` | `image` | |
| camera | `camera.fill` | `photo_camera` (filled) | |
| video | `video` | `videocam` | |
| voice message | `waveform` | `graphic_eq` | |
| play | `play.fill` | `play_arrow` | |
| speaker | `speaker.fill` / `speaker.wave.3.fill` | `volume_mute` / `volume_up` | |
| pinned | `pin.fill` | `push_pin` (filled) | |
| muted | `bell.slash.fill` | `notifications_off` (filled) | |
| notifications | `bell.badge` | `notifications_active` | |
| group | `person.3.fill` | `group` (filled) | |
| lock | `lock` | `lock` | |
| link | `link` | `link` | |
| email | `envelope` / `envelope.badge` | `mail` / `mark_email_unread` | |
| QR scan | `qrcode.viewfinder` | `qr_code_scanner` | |
| device | `iphone` | `smartphone` | |
| file | `doc` | `description` | |
| dark mode | `moon.fill` | `dark_mode` (filled) | |
| backup warning | `externaldrive.badge.exclamationmark` | `warning` | |
| radio off | `circle` | `radio_button_unchecked` | |
