package com.limemessenger.lime.ui.settings

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.toggleableState
import androidx.compose.ui.state.ToggleableState
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.limemessenger.lime.LimeApp
import com.limemessenger.lime.R
import com.limemessenger.lime.auth.AccountSession
import com.limemessenger.lime.auth.ChangePasswordModel
import com.limemessenger.lime.chats.ChatsModel
import com.limemessenger.lime.chats.MediaPrefs
import com.limemessenger.lime.chats.NotificationPrefs
import com.limemessenger.lime.security.AppLock
import com.limemessenger.lime.security.BiometricLockAuthenticator
import com.limemessenger.lime.ui.onboarding.PrimaryButton
import com.limemessenger.lime.ui.shell.Icons
import com.limemessenger.lime.ui.theme.Lime
import com.limemessenger.lime.ui.theme.LimeColors
import java.text.DateFormat
import java.util.Date
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import uniffi.lime_core.AutoDownload
import uniffi.lime_core.KeepMedia
import uniffi.lime_core.LockDelay
import uniffi.lime_core.MediaRef
import uniffi.lime_core.NotificationPreview
import uniffi.lime_core.StorageUsage
import uniffi.lime_core.autoDownloadTitle
import uniffi.lime_core.autoDownloads
import uniffi.lime_core.keepMediaChoices
import uniffi.lime_core.keepMediaDays
import uniffi.lime_core.keepMediaTitle
import uniffi.lime_core.lockDelayTitle
import uniffi.lime_core.lockDelays
import uniffi.lime_core.notificationPreviewTitle
import uniffi.lime_core.notificationPreviews

// The account settings that sit under Settings (iOS `AccountScreens`, `NotificationScreens`, `StorageScreens`, the Privacy lock): change password, notifications,
// storage, and Lock lime. Account deletion is not here (a critical design the user reviews first); text size follows the system's font size.

@Composable
fun SettingsPage(title: String, onBack: () -> Unit, tag: String, content: @Composable () -> Unit) {
    val colors = Lime.colors
    Column(Modifier.fillMaxSize().background(colors.canvas).systemBarsPadding().testTag(tag)) {
        Row(Modifier.fillMaxWidth().heightIn(min = 64.dp), verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = onBack, Modifier.size(56.dp).testTag("settings-page-back")) { Icon(Icons.Back, stringResource(R.string.group_back), tint = colors.text) }
            Text(title, color = colors.text, fontSize = 20.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.semantics { heading() })
        }
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 16.dp).padding(bottom = 32.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) { content() }
    }
}

@Composable
internal fun SettingsCardColumn(content: @Composable () -> Unit) {
    Column(Modifier.fillMaxWidth().background(Lime.colors.surface, RoundedCornerShape(20.dp))) { content() }
}

@Composable
internal fun Footnote(text: String, tag: String? = null) {
    Text(text, color = Lime.colors.textSecondary, fontSize = 14.sp, modifier = Modifier.padding(horizontal = 6.dp).then(if (tag != null) Modifier.testTag(tag) else Modifier))
}

/** One choice of a list (a check on the chosen one): one TalkBack stop, "selected" said. */
@Composable
internal fun Choice(title: String, selected: Boolean, tag: String, onClick: () -> Unit) {
    val colors = Lime.colors
    Row(
        Modifier.fillMaxWidth().heightIn(min = 54.dp).semantics(mergeDescendants = true) { role = Role.RadioButton; this.selected = selected }.clickable(onClick = onClick).padding(horizontal = 18.dp).testTag(tag),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(title, color = colors.text, fontSize = 17.sp, modifier = Modifier.weight(1f))
        if (selected) Icon(Icons.Check, null, tint = colors.text, modifier = Modifier.size(20.dp))
    }
}

@Composable
internal fun ToggleRow(title: String, checked: Boolean, tag: String, onChange: (Boolean) -> Unit) {
    val colors = Lime.colors
    Row(
        Modifier.fillMaxWidth().heightIn(min = 58.dp).semantics(mergeDescendants = true) { role = Role.Switch; toggleableState = if (checked) ToggleableState.On else ToggleableState.Off }
            .clickable { onChange(!checked) }.padding(horizontal = 18.dp).testTag(tag),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(title, color = colors.text, fontSize = 17.sp, modifier = Modifier.weight(1f))
        Switch(checked = checked, onCheckedChange = null, colors = SwitchDefaults.colors(checkedTrackColor = colors.accent, checkedThumbColor = colors.accentInk))
    }
}

@Composable
private fun appOrNull() = LocalContext.current.applicationContext as? LimeApp

private fun friendlyBytes(bytes: Long): String = when {
    bytes < 1_000 -> "$bytes B"
    bytes < 1_000_000 -> "%.0f KB".format(bytes / 1_000.0)
    bytes < 1_000_000_000 -> "%.1f MB".format(bytes / 1_000_000.0)
    else -> "%.2f GB".format(bytes / 1_000_000_000.0)
}

// ---------------------------------------------------------------- change password

/** Change password: the current one and the new one (twice), then the emailed code (iOS `ChangePasswordScreen`). */
@Composable
fun ChangePasswordScreen(session: AccountSession, onBack: () -> Unit) {
    val colors = Lime.colors
    val scope = rememberCoroutineScope()
    val model = remember { ChangePasswordModel(start = { session.startPasswordChange(it) }, finish = { code, new -> session.finishPasswordChange(code, new) }) }
    SettingsPage(stringResource(R.string.pw_title), onBack, "change-password") {
        @Composable
        fun field(label: String, value: String, tag: String, onChange: (String) -> Unit) = OutlinedTextField(
            value = value, onValueChange = { model.edit { _ -> onChange(it) } }, singleLine = true, visualTransformation = PasswordVisualTransformation(),
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password, autoCorrectEnabled = false), shape = RoundedCornerShape(16.dp),
            label = { Text(label, color = colors.textSecondary) },
            colors = OutlinedTextFieldDefaults.colors(focusedTextColor = colors.text, unfocusedTextColor = colors.text, focusedContainerColor = colors.surface, unfocusedContainerColor = colors.surface, focusedBorderColor = colors.text, unfocusedBorderColor = colors.hairline, cursorColor = colors.text),
            modifier = Modifier.fillMaxWidth().heightIn(min = 56.dp).testTag(tag),
        )
        when (model.step) {
            ChangePasswordModel.Step.Passwords -> {
                field(stringResource(R.string.pw_current), model.current, "pw-current") { model.current = it }
                field(stringResource(R.string.pw_new), model.newPassword, "pw-new") { model.newPassword = it }
                field(stringResource(R.string.pw_confirm), model.confirmation, "pw-confirm") { model.confirmation = it }
                Footnote(model.hint, "pw-hint")
                model.errorMessage?.let { Text(it, color = colors.danger, fontSize = 15.sp, modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite }.testTag("pw-error")) }
                PrimaryButton(stringResource(R.string.pw_send), { scope.launch { model.sendCode() } }, Modifier.testTag("pw-send"), enabled = model.canSend, busy = model.isBusy)
            }
            ChangePasswordModel.Step.Code -> {
                Footnote(stringResource(R.string.pw_code_note))
                OutlinedTextField(
                    value = model.code, onValueChange = { model.edit { _ -> model.code = it.filter(Char::isDigit).take(8) } }, singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword), shape = RoundedCornerShape(16.dp),
                    label = { Text(stringResource(R.string.pw_code), color = colors.textSecondary) },
                    colors = OutlinedTextFieldDefaults.colors(focusedTextColor = colors.text, unfocusedTextColor = colors.text, focusedContainerColor = colors.surface, unfocusedContainerColor = colors.surface, focusedBorderColor = colors.text, unfocusedBorderColor = colors.hairline, cursorColor = colors.text),
                    modifier = Modifier.fillMaxWidth().heightIn(min = 56.dp).testTag("pw-code"),
                )
                model.errorMessage?.let { Text(it, color = colors.danger, fontSize = 15.sp, modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite }.testTag("pw-error")) }
                PrimaryButton(stringResource(R.string.pw_verify), { scope.launch { model.verify() } }, Modifier.testTag("pw-verify"), enabled = model.canVerify, busy = model.isBusy)
                TextButton(onClick = { model.back() }, Modifier.heightIn(min = 48.dp).testTag("pw-back")) { Text(stringResource(R.string.group_back), color = colors.text) }
            }
            ChangePasswordModel.Step.Done -> {
                Column(Modifier.fillMaxWidth().padding(top = 24.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text(stringResource(R.string.pw_done), color = colors.text, fontSize = 20.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite }.testTag("pw-done"))
                    Text(stringResource(R.string.pw_done_note), color = colors.textSecondary, fontSize = 15.sp)
                }
                PrimaryButton(stringResource(R.string.pw_finish), onBack, Modifier.testTag("pw-finish"))
            }
        }
    }
}

// ---------------------------------------------------------------- notifications

private fun muteUntilText(until: Long, now: Long = System.currentTimeMillis()): String {
    if (until == Long.MAX_VALUE) return "Muted always"
    val sameDay = java.time.Instant.ofEpochMilli(until).atZone(java.time.ZoneId.systemDefault()).toLocalDate() == java.time.Instant.ofEpochMilli(now).atZone(java.time.ZoneId.systemDefault()).toLocalDate()
    return if (sameDay) "Muted until " + DateFormat.getTimeInstance(DateFormat.SHORT).format(Date(until)) else "Muted until " + java.text.SimpleDateFormat("MMM d", java.util.Locale.getDefault()).format(Date(until))
}

/** Notifications: on or off, what a banner shows, and the muted chats. lime has no push service yet, so alerts show only while lime is open (as iOS says it). */
@Composable
fun NotificationsScreen(chats: ChatsModel?, prefs: NotificationPrefs, onBack: () -> Unit) {
    val colors = Lime.colors
    SettingsPage(stringResource(R.string.notif_title), onBack, "notifications-screen") {
        SettingsCardColumn { ToggleRow(stringResource(R.string.notif_toggle), prefs.enabled, "notif-toggle") { prefs.changeEnabled(it) } }
        Footnote(stringResource(R.string.notif_calls_note))
        if (prefs.enabled) {
            Footnote(stringResource(R.string.notif_preview_heading))
            SettingsCardColumn {
                notificationPreviews().forEach { option -> Choice(notificationPreviewTitle(option), prefs.preview == option, "preview-${option.name.lowercase()}") { prefs.changePreview(option) } }
            }
            Footnote(stringResource(R.string.notif_preview_note))
            Footnote(stringResource(R.string.notif_muted_heading))
            val muted = chats?.muteEntries().orEmpty()
            SettingsCardColumn {
                if (muted.isEmpty()) Text(stringResource(R.string.notif_no_muted), color = colors.textSecondary, fontSize = 15.sp, modifier = Modifier.padding(18.dp).testTag("notif-no-muted"))
                muted.forEach { entry ->
                    val title = chats?.conversations?.firstOrNull { it.id == entry.conversationId }?.title ?: stringResource(R.string.notif_chat)
                    val unmuteWords = stringResource(R.string.notif_unmute_chat, title)
                    Row(Modifier.fillMaxWidth().heightIn(min = 58.dp).padding(horizontal = 18.dp), verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f)) {
                            Text(title, color = colors.text, fontSize = 17.sp)
                            Text(muteUntilText(entry.untilMs), color = colors.textSecondary, fontSize = 13.sp)
                        }
                        TextButton(onClick = { chats?.unmute(entry.conversationId) }, Modifier.heightIn(min = 48.dp).semantics { contentDescription = unmuteWords }.testTag("unmute-${entry.conversationId}")) { Text(stringResource(R.string.row_action_unmute), color = colors.text) }
                    }
                }
            }
        }
        Footnote(stringResource(R.string.notif_no_push), "notif-no-push")
    }
}

// ---------------------------------------------------------------- storage

/** Storage: what lime keeps on this phone, how long it keeps received files, what it downloads by itself, and what each chat takes (iOS `StorageScreen`). */
@Composable
fun StorageScreen(chats: ChatsModel, prefs: MediaPrefs, onBack: () -> Unit) {
    val colors = Lime.colors
    val scope = rememberCoroutineScope()
    var usage by remember { mutableStateOf<StorageUsage?>(null) }
    var removing by remember { mutableStateOf<uniffi.lime_core.ChatUsage?>(null) }
    var gifs by remember { mutableStateOf<uniffi.lime_core.MyGifUsage?>(null) }
    var clearingGifs by remember { mutableStateOf(false) }
    suspend fun load() {
        val core = chats.core() ?: return
        usage = withContext(Dispatchers.IO) { runCatching { core.storageUsage() }.getOrNull() }
        gifs = withContext(Dispatchers.IO) { runCatching { core.myGifsUsage() }.getOrNull() }
    }
    LaunchedEffect(Unit) { load() }
    if (clearingGifs) androidx.compose.material3.AlertDialog(
        onDismissRequest = { clearingGifs = false }, containerColor = colors.canvas,
        title = { Text(stringResource(R.string.storage_clear_gifs), color = colors.text) },
        text = { Text(stringResource(R.string.storage_clear_gifs_body), color = colors.textSecondary) },
        confirmButton = { TextButton({ clearingGifs = false; scope.launch { chats.core()?.let { core -> withContext(Dispatchers.IO) { runCatching { core.removeAllMyGifs() } } }; load() } }, Modifier.heightIn(min = 48.dp).testTag("storage-gifs-clear-confirm")) { Text(stringResource(R.string.storage_clear_gifs), color = colors.danger) } },
        dismissButton = { TextButton({ clearingGifs = false }, Modifier.heightIn(min = 48.dp)) { Text(stringResource(R.string.jam_cancel), color = colors.text) } },
    )
    SettingsPage(stringResource(R.string.storage_title), onBack, "storage-screen") {
        val u = usage
        SettingsCardColumn {
            ValueRow(stringResource(R.string.storage_total), friendlyBytes(u?.databaseBytes?.toLong() ?: 0), "storage-total")
            ValueRow(stringResource(R.string.storage_media), friendlyBytes(u?.mediaBytes?.toLong() ?: 0), "storage-media")
        }
        Footnote(stringResource(R.string.storage_note))
        // My GIFs (LIME-313): how many, their size, and Clear (they live in this phone's store, not in a chat).
        SettingsCardColumn {
            ValueRow(stringResource(R.string.storage_my_gifs), "${gifs?.count ?: 0} · ${friendlyBytes(gifs?.bytes?.toLong() ?: 0)}", "storage-gifs")
            if ((gifs?.count ?: 0u) > 0u) Row(Modifier.fillMaxWidth().heightIn(min = 54.dp).padding(horizontal = 18.dp), verticalAlignment = Alignment.CenterVertically) {
                TextButton(onClick = { clearingGifs = true }, Modifier.heightIn(min = 48.dp).testTag("storage-gifs-clear")) { Text(stringResource(R.string.storage_clear_gifs), color = colors.danger) }
            }
        }
        Footnote(stringResource(R.string.storage_keep_heading))
        SettingsCardColumn {
            keepMediaChoices().forEach { option ->
                Choice(keepMediaTitle(option), prefs.keep == option, "keep-${option.name.lowercase()}") {
                    prefs.changeKeep(option)
                    // Older files go from this phone now; the messages stay, marked "Media removed".
                    keepMediaDays(option)?.let { days -> scope.launch { chats.core()?.let { core -> withContext(Dispatchers.IO) { runCatching { core.removeMediaOlderThan(days) } } }; load() } }
                }
            }
        }
        Footnote(stringResource(R.string.storage_keep_note))
        Footnote(stringResource(R.string.storage_photos_heading))
        SettingsCardColumn { autoDownloads().forEach { option -> Choice(autoDownloadTitle(option), prefs.photos == option, "auto-photos-${option.name.lowercase()}") { prefs.changePhotos(option) } } }
        Footnote(stringResource(R.string.storage_videofiles_heading))
        SettingsCardColumn { autoDownloads().forEach { option -> Choice(autoDownloadTitle(option), prefs.videoAndFiles == option, "auto-videofiles-${option.name.lowercase()}") { prefs.changeVideoAndFiles(option) } } }
        Footnote(stringResource(R.string.storage_auto_note))
        Footnote(stringResource(R.string.storage_bychat_heading))
        SettingsCardColumn {
            if (u != null && u.chats.isEmpty()) Text(stringResource(R.string.storage_empty), color = colors.textSecondary, fontSize = 16.sp, modifier = Modifier.padding(18.dp).testTag("storage-empty"))
            u?.chats?.forEach { chat ->
                val title = chats.conversations.firstOrNull { it.id == chat.conversationId }?.title ?: stringResource(R.string.notif_chat)
                val words = stringResource(R.string.storage_remove_chat_media, title)
                Row(Modifier.fillMaxWidth().heightIn(min = 54.dp).padding(horizontal = 18.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(title, color = colors.text, fontSize = 17.sp, maxLines = 1, modifier = Modifier.weight(1f))
                    Text(friendlyBytes(chat.bytes.toLong()), color = colors.textSecondary, fontSize = 16.sp, modifier = Modifier.padding(horizontal = 8.dp))
                    TextButton(onClick = { removing = chat }, Modifier.heightIn(min = 48.dp).semantics { contentDescription = words }.testTag("storage-remove-${chat.conversationId}")) { Text(stringResource(R.string.group_remove), color = colors.danger) }
                }
            }
        }
    }
    removing?.let { chat ->
        val title = chats.conversations.firstOrNull { it.id == chat.conversationId }?.title ?: stringResource(R.string.notif_chat)
        AlertDialog(
            onDismissRequest = { removing = null },
            title = { Text(stringResource(R.string.storage_remove_title, title)) },
            text = { Text(stringResource(R.string.storage_remove_body)) },
            confirmButton = {
                TextButton(onClick = {
                    removing = null
                    scope.launch {
                        val core = chats.core() ?: return@launch
                        withContext(Dispatchers.IO) { runCatching { core.removeMedia(core.listMedia(chat.conversationId).map { MediaRef(it.messageId, it.attachmentId) }) } }
                        load()
                    }
                }, Modifier.heightIn(min = 48.dp).testTag("storage-remove-confirm")) { Text(stringResource(R.string.storage_remove_button), color = colors.danger) }
            },
            dismissButton = { TextButton(onClick = { removing = null }, Modifier.heightIn(min = 48.dp)) { Text(stringResource(R.string.group_cancel)) } },
        )
    }
}

@Composable
private fun ValueRow(title: String, value: String, tag: String) {
    val colors = Lime.colors
    Row(Modifier.fillMaxWidth().heightIn(min = 54.dp).padding(horizontal = 18.dp).semantics(mergeDescendants = true) {}, verticalAlignment = Alignment.CenterVertically) {
        Text(title, color = colors.text, fontSize = 17.sp, modifier = Modifier.weight(1f))
        Text(value, color = colors.textSecondary, fontSize = 17.sp, modifier = Modifier.testTag(tag))
    }
}

// ---------------------------------------------------------------- privacy: Lock lime

/** Privacy: Lock lime (off by default) and how long lime may be away before it asks again (iOS's Privacy screen). */
@Composable
fun PrivacyScreen(lock: AppLock, onBack: () -> Unit, linkPreviews: com.limemessenger.lime.chats.LinkPreviewPrefs? = null) {
    val scope = rememberCoroutineScope()
    var cannot by remember { mutableStateOf(false) }
    SettingsPage(stringResource(R.string.privacy_title), onBack, "privacy-screen") {
        SettingsCardColumn {
            ToggleRow(stringResource(R.string.privacy_lock), lock.isEnabled, "privacy-lock") { want ->
                if (want) scope.launch { cannot = !lock.turnOn() } else { lock.turnOff(); cannot = false }
            }
            if (lock.isEnabled) {
                Footnote(stringResource(R.string.privacy_lock_ask))
                lockDelays().forEach { delay -> Choice(lockDelayTitle(delay), lock.delay == delay, "lock-delay-${delay.name.lowercase()}") { lock.changeDelay(delay) } }
            }
        }
        if (cannot) Text(stringResource(R.string.privacy_lock_unavailable), color = Lime.colors.danger, fontSize = 15.sp, modifier = Modifier.testTag("privacy-lock-unavailable"))
        Footnote(stringResource(R.string.privacy_lock_note), "privacy-lock-note")
        Footnote(stringResource(R.string.privacy_e2ee))
        // Link previews (LIME-407, iOS "Generate link previews"): on by default, as iOS. Off: no page is visited and no card is made.
        if (linkPreviews != null) {
            SettingsCardColumn { ToggleRow(stringResource(R.string.privacy_link_previews), linkPreviews.enabled, "privacy-link-previews") { linkPreviews.change(it) } }
            Footnote(stringResource(R.string.privacy_link_previews_note), "privacy-link-previews-note")
        }
    }
}

// ---------------------------------------------------------------- appearance

/**
 * Appearance (iOS Customize → Appearance, Colour, Background): follow the phone or always light or dark, one of the eight colours (they colour the main
 * button, my bubbles and badges), one of the eight backgrounds. Every combination is worked out by the core and passed through its contrast guard, so text
 * stays readable (4.5:1) on whatever is chosen. The screen itself is the preview: it changes as you choose. Kept on this phone only.
 */
@Composable
fun AppearanceScreen(prefs: com.limemessenger.lime.chats.ThemePrefs, onBack: () -> Unit) {
    val colors = Lime.colors
    SettingsPage(stringResource(R.string.appearance_title), onBack, "appearance-screen") {
        SettingsCardColumn {
            com.limemessenger.lime.chats.AppearanceMode.entries.forEach { mode -> Choice(mode.title, prefs.mode == mode, "appearance-${mode.name.lowercase()}") { prefs.changeMode(mode) } }
        }
        Footnote(stringResource(R.string.appearance_colour_heading))
        SettingsCardColumn {
            val names = uniffi.lime_core.accentNames()
            androidx.compose.foundation.layout.FlowRow(Modifier.padding(12.dp), horizontalArrangement = Arrangement.spacedBy(4.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                (0..7).forEach { tone ->
                    val on = prefs.accent == tone
                    val words = stringResource(if (on) R.string.appearance_colour_selected else R.string.appearance_colour_option, names[tone])
                    Box(
                        Modifier.size(56.dp).semantics { contentDescription = words; role = Role.RadioButton; selected = on }.clickable { prefs.changeAccent(tone) }.testTag("accent-$tone"),
                        contentAlignment = Alignment.Center,
                    ) {
                        Box(Modifier.size(40.dp).background(Color(0xFF000000 or uniffi.lime_core.accentHex(tone).toLong()), androidx.compose.foundation.shape.CircleShape), contentAlignment = Alignment.Center) {
                            // Not by colour alone: the chosen one has a check, in the ink that reads on it.
                            if (on) Icon(Icons.Check, null, tint = Color(0xFF000000 or uniffi.lime_core.contrastInk(uniffi.lime_core.accentHex(tone)).toLong()), modifier = Modifier.size(22.dp))
                        }
                    }
                }
            }
        }
        Footnote(stringResource(R.string.appearance_background_heading))
        SettingsCardColumn {
            uniffi.lime_core.themeBackgrounds().forEach { background ->
                val swatch = uniffi.lime_core.resolveTheme(prefs.accent, background, colors.dark || uniffi.lime_core.themeBackgroundForcesDark(background), false)
                val title = uniffi.lime_core.themeBackgroundTitle(background)
                Row(
                    Modifier.fillMaxWidth().heightIn(min = 60.dp).semantics(mergeDescendants = true) { role = Role.RadioButton; selected = prefs.background == background }
                        .clickable { prefs.changeBackground(background) }.padding(horizontal = 18.dp).testTag("background-${background.name.lowercase()}"),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp),
                ) {
                    Row(Modifier.size(width = 44.dp, height = 32.dp).background(Color(0xFF000000 or swatch.canvas.toLong()), RoundedCornerShape(8.dp)).padding(4.dp)) {
                        Box(Modifier.weight(1f).fillMaxSize().background(Color(0xFF000000 or swatch.surface.toLong()), RoundedCornerShape(5.dp)))
                    }
                    Text(title, color = colors.text, fontSize = 17.sp, modifier = Modifier.weight(1f))
                    if (prefs.background == background) Icon(Icons.Check, null, tint = colors.text, modifier = Modifier.size(20.dp))
                }
            }
        }
        Footnote(stringResource(R.string.appearance_note), "appearance-note")
        if (!prefs.isDefault) {
            TextButton(onClick = { prefs.reset() }, Modifier.heightIn(min = 48.dp).testTag("appearance-reset")) { Text(stringResource(R.string.appearance_reset), color = colors.text) }
        }
    }
}
