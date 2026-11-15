package com.limemessenger.lime.ui.settings

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.role
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.unit.dp
import com.limemessenger.lime.R
import com.limemessenger.lime.calls.IncomingCallNotifier
import com.limemessenger.lime.calls.CallPrefs
import com.limemessenger.lime.ui.theme.Lime
import com.limemessenger.lime.ui.theme.LimeSpacing
import com.limemessenger.lime.ui.theme.LimeType
import com.limemessenger.lime.ui.theme.LimeType.style

/**
 * Settings → Calls (iOS `CallSettingsScreen`, LIME-169): Low Data Mode for video and how loud the other people sound, each with one line saying what it does, kept on this
 * phone. ("Include in Recents" is the iPhone's Phone app and has no Android twin.) They take effect in a call from LIME-425 on; a last line says calls ring only while lime is open.
 */
@Composable
fun CallSettingsScreen(prefs: CallPrefs, onBack: () -> Unit, surfaceOf: (android.content.Context) -> IncomingCallNotifier.Surface = { IncomingCallNotifier.surface(it) }) {
    val colors = Lime.colors
    SettingsPage(stringResource(R.string.calls_settings_title), onBack, "calls-settings") {
        SettingsCardColumn { ToggleRow(stringResource(R.string.calls_settings_low_data), prefs.lowDataMode, "calls-low-data") { prefs.changeLowData(it) } }
        Footnote(stringResource(R.string.calls_settings_low_data_note))
        val words = stringResource(R.string.calls_settings_volume)
        SettingsCardColumn {
            Column(Modifier.padding(horizontal = 18.dp, vertical = LimeSpacing.l), horizontalAlignment = Alignment.CenterHorizontally) {
                Slider(
                    value = prefs.volume.toFloat(), onValueChange = { prefs.changeVolume(it.toDouble()) },
                    valueRange = CallPrefs.VOLUME_RANGE.start.toFloat()..CallPrefs.VOLUME_RANGE.endInclusive.toFloat(), steps = 14,
                    colors = SliderDefaults.colors(thumbColor = colors.text, activeTrackColor = colors.text, inactiveTrackColor = colors.hairline, activeTickColor = colors.text, inactiveTickColor = colors.hairline),
                    modifier = Modifier.semantics { contentDescription = words; stateDescription = CallPrefs.percent(prefs.volume) }.testTag("calls-volume"),
                )
                Text(CallPrefs.percent(prefs.volume), color = colors.textSecondary, style = LimeType.run { secondary.style() }, modifier = Modifier.testTag("calls-volume-value"))
            }
        }
        Footnote(stringResource(R.string.calls_settings_volume_note))
        RingSurface(surfaceOf)
        Footnote(stringResource(R.string.calls_settings_ring_note), "calls-ring-note")
    }
}

/**
 * Whether an incoming call can ring while lime is in the background (LIME-427): the phone's notification permission, the "Incoming calls" channel, and (Android 14+) full-screen calls on a
 * locked phone, each in words, with buttons to allow what can be allowed here and to open the phone's own settings page. Read again each time the person comes back from there.
 */
@Composable
private fun RingSurface(surfaceOf: (android.content.Context) -> IncomingCallNotifier.Surface) {
    val colors = Lime.colors
    val context = androidx.compose.ui.platform.LocalContext.current
    var surface by androidx.compose.runtime.remember { androidx.compose.runtime.mutableStateOf(surfaceOf(context)) }
    val lifecycle = androidx.lifecycle.compose.LocalLifecycleOwner.current.lifecycle
    androidx.compose.runtime.DisposableEffect(lifecycle) {
        val observer = androidx.lifecycle.LifecycleEventObserver { _, event -> if (event == androidx.lifecycle.Lifecycle.Event.ON_RESUME) surface = surfaceOf(context) }
        lifecycle.addObserver(observer)
        onDispose { lifecycle.removeObserver(observer) }
    }
    val ask = androidx.activity.compose.rememberLauncherForActivityResult(androidx.activity.result.contract.ActivityResultContracts.RequestPermission()) { surface = surfaceOf(context) }
    val runtimeMissing = android.os.Build.VERSION.SDK_INT >= 33 && !surface.notificationsAllowed
    SettingsCardColumn {
        Column(Modifier.padding(horizontal = 18.dp, vertical = LimeSpacing.l), verticalArrangement = androidx.compose.foundation.layout.Arrangement.spacedBy(LimeSpacing.m)) {
            Text(stringResource(R.string.calls_ring_title), color = colors.text, style = LimeType.run { title.style() }, modifier = Modifier.semantics { heading() })
            Text(
                stringResource(if (!surface.notificationsAllowed) R.string.calls_ring_off_notifications else if (!surface.channelAllowed) R.string.calls_ring_off_channel else R.string.calls_ring_on),
                color = colors.textSecondary, style = LimeType.run { secondary.style() }, modifier = Modifier.testTag("calls-ring-state"),
            )
            if (android.os.Build.VERSION.SDK_INT >= 34) Text(
                stringResource(if (surface.fullScreenAllowed) R.string.calls_ring_fullscreen_on else R.string.calls_ring_fullscreen_off),
                color = colors.textSecondary, style = LimeType.run { secondary.style() }, modifier = Modifier.testTag("calls-ring-fullscreen"),
            )
            if (runtimeMissing) SettingsButton(stringResource(R.string.calls_ring_allow), "calls-ring-allow") { ask.launch(android.Manifest.permission.POST_NOTIFICATIONS) }
            SettingsButton(stringResource(R.string.calls_ring_phone_settings), "calls-ring-settings") { runCatching { context.startActivity(IncomingCallNotifier.settingsIntent(context)) } }
            if (!surface.fullScreenAllowed) IncomingCallNotifier.fullScreenSettingsIntent(context)?.let { intent ->
                SettingsButton(stringResource(R.string.calls_ring_fullscreen_settings), "calls-ring-fullscreen-settings") { runCatching { context.startActivity(intent) } }
            }
        }
    }
}

@Composable
private fun SettingsButton(text: String, tag: String, onClick: () -> Unit) {
    val colors = Lime.colors
    androidx.compose.foundation.layout.Box(
        Modifier.fillMaxWidth().heightIn(min = 48.dp).background(colors.pressed, com.limemessenger.lime.ui.theme.LimeShapes.pill)
            .semantics { role = androidx.compose.ui.semantics.Role.Button }.clickable(onClick = onClick).testTag(tag),
        contentAlignment = Alignment.Center,
    ) { Text(text, color = colors.text, style = LimeType.run { body.style() }) }
}
