package com.limemessenger.lime.ui.settings

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.unit.dp
import com.limemessenger.lime.R
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
fun CallSettingsScreen(prefs: CallPrefs, onBack: () -> Unit) {
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
        Footnote(stringResource(R.string.calls_settings_ring_note), "calls-ring-note")
    }
}
