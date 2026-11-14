package com.limemessenger.lime.ui.settings

import androidx.activity.compose.BackHandler
import com.limemessenger.lime.debug.designGalleryTrigger
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.LocalTextStyle
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.disabled
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.limemessenger.lime.BuildConfig
import com.limemessenger.lime.R
import com.limemessenger.lime.auth.AboutPreset
import com.limemessenger.lime.auth.AccountSession
import com.limemessenger.lime.auth.AuthError
import com.limemessenger.lime.auth.ConnectionProblem
import com.limemessenger.lime.auth.FieldEditorModel
import com.limemessenger.lime.auth.Profile
import com.limemessenger.lime.auth.ProfileField
import com.limemessenger.lime.auth.TermsAcceptance
import com.limemessenger.lime.chats.AvatarTone
import com.limemessenger.lime.ui.common.Avatar
import com.limemessenger.lime.ui.common.initialsOf
import com.limemessenger.lime.ui.shell.Icons
import com.limemessenger.lime.ui.theme.Lime
import kotlinx.coroutines.launch
import uniffi.lime_core.coreVersion

/**
 * Settings (iOS `SettingsView`, minimal tonight): the profile card, the fields of my profile (name, about, username, school), About lime, and
 * Sign out (with the honest words about what it does to this phone's keys). The system back gesture leaves a screen.
 */
@Composable
fun SettingsScreen(session: AccountSession, onClose: () -> Unit, chats: com.limemessenger.lime.chats.ChatsModel? = null) {
    val app = androidx.compose.ui.platform.LocalContext.current.applicationContext as? com.limemessenger.lime.LimeApp
    var route by rememberSaveable { mutableStateOf("") }
    val colors = Lime.colors
    var editing by remember { mutableStateOf<ProfileField?>(null) }
    var aboutOpen by rememberSaveable { mutableStateOf(false) }
    var confirmingSignOut by remember { mutableStateOf(false) }
    var confirmingRemoval by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    BackHandler(enabled = aboutOpen) { aboutOpen = false }
    BackHandler(enabled = route != "") { route = "" }
    BackHandler(enabled = !aboutOpen && route == "") { onClose() }
    val profile = session.profile ?: Profile(displayName = "")

    if (aboutOpen) { AboutScreen(onBack = { aboutOpen = false }); return }
    // The screens under Account, Notifications, Storage and Privacy.
    when (route) {
        "password" -> { ChangePasswordScreen(session, onBack = { route = "" }); return }
        "notifications" -> if (app != null) { NotificationsScreen(chats, app.notificationPrefs, onBack = { route = "" }); return }
        "storage" -> if (app != null && chats != null) { StorageScreen(chats, app.mediaPrefs, onBack = { route = "" }); return }
        "calls" -> if (app != null) { CallSettingsScreen(app.callPrefs, onBack = { route = "" }); return }
        "appearance" -> if (app != null) { AppearanceScreen(app.themePrefs, onBack = { route = "" }); return }
        "privacy" -> if (app != null) { PrivacyScreen(app.appLock, onBack = { route = "" }, linkPreviews = app.linkPreviewPrefs); return }
        "debug-tools" -> { com.limemessenger.lime.debug.DesignGallery(onBack = { route = "" }); return }
        "blocked" -> if (chats != null) { com.limemessenger.lime.ui.moderation.BlockedScreen(chats, onBack = { route = "" }); return }
    }

    Column(Modifier.fillMaxSize().background(colors.canvas).systemBarsPadding()) {
        Row(Modifier.fillMaxWidth().heightIn(min = 64.dp), verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = onClose, Modifier.size(56.dp).testTag("settings-close")) { Icon(Icons.Close, stringResource(R.string.settings_close), tint = colors.text) }
            Text(stringResource(R.string.settings_title), color = colors.text, fontSize = 20.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.designGalleryTrigger { route = "debug-tools" }.semantics { heading() })
        }
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 16.dp).padding(bottom = 32.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            // The profile card: who I am, as others see me.
            Row(
                Modifier.fillMaxWidth().background(colors.surface, RoundedCornerShape(20.dp)).padding(16.dp).testTag("settings-profile"),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp),
            ) {
                Avatar(initialsOf(profile.displayName), AvatarTone.tone(session.userId.orEmpty()), 64.dp)
                Column {
                    Text(profile.displayName, color = colors.text, fontSize = 20.sp, fontWeight = FontWeight.Bold, modifier = Modifier.testTag("settings-name"))
                    profile.username?.let { Text("@$it", color = colors.textSecondary, fontSize = 15.sp) }
                    profile.about?.let { Text(it, color = colors.textSecondary, fontSize = 15.sp, modifier = Modifier.testTag("settings-about-line")) }
                }
            }
            Card {
                Row2(stringResource(R.string.settings_name), profile.displayName, "settings-row-name") { editing = ProfileField.Name }
                Row2(stringResource(R.string.settings_about_you), profile.about ?: stringResource(R.string.settings_not_set), "settings-row-about") { editing = ProfileField.About }
                Row2(stringResource(R.string.settings_username), profile.username?.let { "@$it" } ?: stringResource(R.string.settings_not_set), "settings-row-username") { editing = ProfileField.Username }
                Row2(stringResource(R.string.settings_school), profile.school ?: stringResource(R.string.settings_not_set), "settings-row-school", last = true) { editing = ProfileField.School }
            }
            Card {
                profile.maskedEmail?.let { Row2(stringResource(R.string.settings_email), it, "settings-row-email", last = false, onClick = null) }
                Row2(stringResource(R.string.settings_change_password), "", "settings-row-password") { route = "password" }
                Row2(stringResource(R.string.settings_notifications), "", "settings-row-notifications") { route = "notifications" }
                Row2(stringResource(R.string.settings_storage), "", "settings-row-storage") { route = "storage" }
                Row2(stringResource(R.string.settings_calls), "", "settings-row-calls") { route = "calls" }
                Row2(stringResource(R.string.settings_appearance), "", "settings-row-appearance") { route = "appearance" }
                Row2(stringResource(R.string.settings_privacy), "", "settings-row-privacy") { route = "privacy" }
                if (chats != null) Row2(stringResource(R.string.blocked_title), "", "settings-row-blocked") { route = "blocked" }
                Row2(stringResource(R.string.settings_about), "", "settings-row-about-lime", last = true) { aboutOpen = true }
            }
            Card {
                Row2(stringResource(R.string.settings_sign_out), "", "settings-sign-out") { confirmingSignOut = true }
                Row2(stringResource(R.string.settings_remove_everything), "", "settings-remove-everything", last = true, destructive = true) { confirmingRemoval = true }
            }
        }
    }

    editing?.let { kind -> FieldEditor(session, FieldEditorModel(kind, profile), onDone = { editing = null }) }
    if (confirmingSignOut) ConfirmDialog(
        title = stringResource(R.string.settings_sign_out), message = stringResource(R.string.settings_sign_out_warning), button = stringResource(R.string.settings_sign_out), tag = "sign-out-confirm",
        onDismiss = { confirmingSignOut = false }, onConfirm = { confirmingSignOut = false; scope.launch { session.signOut() } },
    )
    if (confirmingRemoval) ConfirmDialog(
        title = stringResource(R.string.settings_remove_everything), message = stringResource(R.string.settings_remove_warning), button = stringResource(R.string.settings_remove_button), tag = "remove-confirm",
        destructive = true, onDismiss = { confirmingRemoval = false }, onConfirm = { confirmingRemoval = false; scope.launch { session.signOut(removingData = true) } },
    )
}

@Composable
private fun Card(content: @Composable () -> Unit) {
    Column(Modifier.fillMaxWidth().background(Lime.colors.surface, RoundedCornerShape(20.dp))) { content() }
}

@Composable
private fun Row2(title: String, value: String, tag: String, last: Boolean = false, destructive: Boolean = false, onClick: (() -> Unit)?) {
    val colors = Lime.colors
    val measurer = rememberTextMeasurer()
    val titleStyle = LocalTextStyle.current.copy(fontSize = 17.sp)
    val valueStyle = LocalTextStyle.current.copy(fontSize = 16.sp)
    Column {
        BoxWithConstraints(
            Modifier.fillMaxWidth().heightIn(min = 56.dp)
                .then(if (onClick != null) Modifier.semantics(mergeDescendants = true) { role = Role.Button }.clickable(onClick = onClick) else Modifier.semantics(mergeDescendants = true) { })
                .padding(horizontal = 16.dp).testTag(tag),
            contentAlignment = Alignment.CenterStart,
        ) {
            val titleColor = if (destructive) colors.danger else colors.text
            // Side by side only when both fit on one line (the normal-size look); otherwise the value goes under the label and wraps, never cut off.
            val fits = value.isEmpty() || with(LocalDensity.current) {
                val t = measurer.measure(title, titleStyle, maxLines = 1).size.width
                val v = measurer.measure(value, valueStyle, maxLines = 1).size.width
                t + v + 12.dp.roundToPx() <= constraints.maxWidth && v <= 200.dp.roundToPx()
            }
            if (fits) {
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Text(title, color = titleColor, fontSize = 17.sp, modifier = Modifier.weight(1f))
                    if (value.isNotEmpty()) Text(value, color = colors.textSecondary, fontSize = 16.sp, maxLines = 1, modifier = Modifier.padding(start = 12.dp))
                }
            } else {
                Column(Modifier.fillMaxWidth().padding(vertical = 10.dp)) {
                    Text(title, color = titleColor, fontSize = 17.sp)
                    Text(value, color = colors.textSecondary, fontSize = 16.sp)
                }
            }
        }
        if (!last) Box(Modifier.fillMaxWidth().padding(start = 16.dp).size(1.dp).background(colors.hairline))
    }
}

@Composable
private fun ConfirmDialog(title: String, message: String, button: String, tag: String, onDismiss: () -> Unit, onConfirm: () -> Unit, destructive: Boolean = false) {
    val colors = Lime.colors
    AlertDialog(
        onDismissRequest = onDismiss, containerColor = colors.canvas,
        title = { Text(title, color = colors.text) }, text = { Text(message, color = colors.textSecondary) },
        confirmButton = { TextButton(onConfirm, Modifier.heightIn(min = 48.dp).testTag(tag)) { Text(button, color = if (destructive) colors.danger else colors.text, fontWeight = FontWeight.SemiBold) } },
        dismissButton = { TextButton(onDismiss, Modifier.heightIn(min = 48.dp).testTag("$tag-cancel")) { Text(stringResource(R.string.settings_cancel), color = colors.text) } },
    )
}

/** Editing one field (iOS `FieldEditorSheet`): the field, what is wrong with it in words, the About presets; Save is the one lime action. */
@Composable
fun FieldEditor(session: AccountSession, model: FieldEditorModel, onDone: () -> Unit) {
    val colors = Lime.colors
    val scope = rememberCoroutineScope()
    val focus = remember { FocusRequester() }
    LaunchedEffect(Unit) { runCatching { focus.requestFocus() } }
    BackHandler { onDone() }
    fun save() {
        if (!model.canSave) return
        model.isSaving = true; model.errorMessage = null
        scope.launch {
            try { session.updateProfile(model.draft()); onDone() }
            catch (e: kotlinx.coroutines.CancellationException) { throw e }
            catch (e: Throwable) { model.errorMessage = (e as? AuthError)?.message ?: ConnectionProblem.from(e).message; model.isSaving = false }
        }
    }
    Column(Modifier.fillMaxSize().background(colors.canvas).systemBarsPadding().imePadding().testTag("field-editor")) {
        Row(Modifier.fillMaxWidth().heightIn(min = 64.dp).padding(horizontal = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = onDone, Modifier.size(56.dp).testTag("editor-close")) { Icon(Icons.Close, stringResource(R.string.settings_cancel), tint = colors.text) }
            Text(model.title, color = colors.text, fontSize = 20.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f).semantics { heading() }.testTag("editor-title"))
            val saveLabel = stringResource(R.string.settings_save)
            Box(
                Modifier.size(56.dp).background(if (model.canSave) colors.accent else colors.pressed, androidx.compose.foundation.shape.CircleShape)
                    .then(if (model.canSave) Modifier.clickable(role = Role.Button, onClick = ::save) else Modifier.semantics { role = Role.Button; disabled() })
                    .semantics { contentDescription = saveLabel }.testTag("editor-save"),
                contentAlignment = Alignment.Center,
            ) { Icon(Icons.Check, null, tint = if (model.canSave) colors.accentInk else colors.textSecondary) }
        }
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                if (model.kind == ProfileField.About) {
                    OutlinedTextField(
                        value = model.emoji, onValueChange = { if (it.isEmpty()) model.emoji = "" else model.pickEmoji(it) }, singleLine = true,
                        placeholder = { Text("🙂") }, modifier = Modifier.size(width = 76.dp, height = 56.dp).testTag("editor-emoji"),
                        shape = RoundedCornerShape(28.dp), colors = fieldColors(),
                    )
                }
                OutlinedTextField(
                    value = model.text, onValueChange = { model.text = it; model.errorMessage = null }, singleLine = model.kind != ProfileField.About,
                    placeholder = { Text(model.placeholder, color = colors.textSecondary) }, shape = RoundedCornerShape(28.dp), colors = fieldColors(),
                    keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(imeAction = ImeAction.Done, autoCorrectEnabled = model.kind != ProfileField.Username),
                    keyboardActions = androidx.compose.foundation.text.KeyboardActions(onDone = { save() }),
                    modifier = Modifier.weight(1f).heightIn(min = 56.dp).focusRequester(focus).testTag("editor-field"),
                )
                if (model.text.isNotEmpty()) IconButton(onClick = { model.clear() }, Modifier.size(48.dp).testTag("editor-clear")) { Icon(Icons.Close, stringResource(R.string.settings_clear), tint = colors.textSecondary) }
            }
            val message = model.errorMessage ?: (if (model.hasChange) model.validationMessage else null)
            if (message != null) Text(message, color = colors.danger, fontSize = 15.sp, modifier = Modifier.semantics { liveRegion = LiveRegionMode.Assertive }.testTag("editor-error"))
            else model.footer?.let { Text(it, color = colors.textSecondary, fontSize = 15.sp) }
            if (model.kind == ProfileField.About) {
                Column(Modifier.fillMaxWidth().background(colors.surface, RoundedCornerShape(20.dp))) {
                    AboutPreset.all.forEach { preset ->
                        Row(
                            Modifier.fillMaxWidth().heightIn(min = 50.dp).semantics(mergeDescendants = true) { role = Role.Button }.clickable { model.applyPreset(preset) }.padding(horizontal = 18.dp).testTag("preset-${preset.text}"),
                            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
                        ) { Text(preset.emoji, fontSize = 22.sp); Text(preset.text, color = colors.text, fontSize = 17.sp) }
                    }
                }
            }
        }
    }
}

@Composable
private fun fieldColors() = Lime.colors.let {
    OutlinedTextFieldDefaults.colors(
        focusedTextColor = it.text, unfocusedTextColor = it.text, focusedContainerColor = it.surface, unfocusedContainerColor = it.surface,
        focusedBorderColor = it.text, unfocusedBorderColor = it.hairline, cursorColor = it.text,
    )
}

/** About lime: the version and the links (Terms, Privacy, Guidelines, Safety). */
@Composable
fun AboutScreen(onBack: () -> Unit) {
    val colors = Lime.colors
    val uri = LocalUriHandler.current
    Column(Modifier.fillMaxSize().background(colors.canvas).systemBarsPadding().testTag("about-screen")) {
        Row(Modifier.fillMaxWidth().heightIn(min = 64.dp), verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = onBack, Modifier.size(56.dp).testTag("about-back")) { Icon(Icons.Back, stringResource(R.string.chat_back), tint = colors.text) }
            Text(stringResource(R.string.settings_about), color = colors.text, fontSize = 20.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.semantics { heading() })
        }
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(stringResource(R.string.app_name), color = colors.text, fontSize = 40.sp, fontWeight = FontWeight.Bold)
            Text(stringResource(R.string.about_tagline), color = colors.textSecondary, fontSize = 17.sp)
            Text(stringResource(R.string.about_version, BuildConfig.VERSION_NAME), color = colors.textSecondary, fontSize = 15.sp, modifier = Modifier.testTag("about-version"))
            Text(stringResource(R.string.about_core, runCatching { coreVersion() }.getOrDefault("?")), color = colors.textSecondary, fontSize = 15.sp, modifier = Modifier.testTag("about-core"))
            Column(Modifier.fillMaxWidth().background(colors.surface, RoundedCornerShape(20.dp))) {
                listOf(
                    Triple(R.string.about_terms, TermsAcceptance.TERMS_URL, "about-terms"), Triple(R.string.about_privacy, TermsAcceptance.PRIVACY_URL, "about-privacy"),
                    Triple(R.string.about_guidelines, TermsAcceptance.GUIDELINES_URL, "about-guidelines"), Triple(R.string.about_safety, TermsAcceptance.SAFETY_URL, "about-safety"),
                ).forEach { (label, url, tag) ->
                    Row(Modifier.fillMaxWidth().heightIn(min = 56.dp).semantics(mergeDescendants = true) { role = Role.Button }.clickable { uri.openUri(url) }.padding(horizontal = 16.dp).testTag(tag), verticalAlignment = Alignment.CenterVertically) {
                        Text(stringResource(label), color = colors.text, fontSize = 17.sp)
                    }
                }
            }
            Spacer(Modifier.size(24.dp))
        }
    }
}
