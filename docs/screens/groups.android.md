# Groups on Android (LIME-303)

The spec is the iOS app (`ios/Lime/Features/Groups/`). Where Android differs:

- **New group:** New message → the "New group" row at the top (iOS: an action row in the same sheet) → the people picker (chips on top, "N members", a search at the bottom, Next) → the name (starts as the picked people's first names, the core's `default_group_name`; 50 characters; "n/50" counter) and an optional emoji typed in a field (iOS has an emoji/photo editor; the group photo is not built on Android yet) → Create. Back from any step goes one step back (system back gesture too).
- **Group chat:** sender name and avatar on the first message of a run, centred system lines ("Ada added Ben"), as 298 already drew. A group that ended (you left, or the owner deleted it) is read-only: "You left this group." / "This group was deleted." with "Remove from my list" (iOS `endedBar`).
- **Group details** (tap the chat's name and picture): the picture, name, member count, Rename and Add members (owner/admin), the members with their role and Remove where the core says `can_remove`, Leave group. **Not on Android yet:** the hero/cover, Members · Media · Files · Links tabs, Mute/Pin/Chat appearance, Clear messages, Delete group, admin promotion, report.
- **The picture of a group with no photo or emoji** is drawn from the core's `group_avatar_plan` / `group_avatar_spots` (the same numbers iOS draws from `GroupAvatarPlan.swift`), with a 1.2+ dp ring in the surface colour so each face reads where circles overlap.
- **TalkBack:** the avatar is skipped (the row says the name); each person in the picker is one checkbox stop ("selected" state); chips say "Remove <name>"; all targets are 48 dp or more.
