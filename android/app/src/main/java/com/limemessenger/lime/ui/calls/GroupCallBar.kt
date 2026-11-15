package com.limemessenger.lime.ui.calls

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.limemessenger.lime.R
import com.limemessenger.lime.ui.shell.Icons
import com.limemessenger.lime.ui.theme.Lime
import com.limemessenger.lime.ui.theme.LimeShapes
import com.limemessenger.lime.ui.theme.LimeSpacing
import com.limemessenger.lime.ui.theme.LimeType
import com.limemessenger.lime.ui.theme.LimeType.style
import uniffi.lime_core.GroupCallInfo

/**
 * The strip under a group chat's header (iOS: the call buttons and the "Join" pill): when a call is on, one lime "Join the call (3 in it)" button (the live action); otherwise a voice call
 * and a video call button in the warm neutral. Hidden while this phone is in a call.
 */
@Composable
fun GroupCallBar(call: GroupCallInfo?, busy: Boolean, onStart: (video: Boolean) -> Unit, onJoin: (GroupCallInfo) -> Unit, modifier: Modifier = Modifier) {
    if (busy) return
    val colors = Lime.colors
    Row(modifier.fillMaxWidth().padding(horizontal = LimeSpacing.l, vertical = 4.dp), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
        if (call != null) {
            Box(
                Modifier.weight(1f).heightIn(min = 48.dp).background(colors.accent, LimeShapes.pill).semantics { role = Role.Button }.clickable { onJoin(call) }.testTag("group-call-join"),
                contentAlignment = Alignment.Center,
            ) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    Icon(if (call.video) Icons.Video else Icons.Phone, null, tint = androidx.compose.ui.graphics.Color(0xFF131B17), modifier = Modifier.size(20.dp))
                    Text(stringResource(R.string.group_call_join_count, call.participantCount.toInt()), color = androidx.compose.ui.graphics.Color(0xFF131B17), style = LimeType.run { secondary.style() })
                }
            }
        } else {
            for ((video, tag, icon, label) in listOf(Quad(false, "group-call-start-voice", Icons.Phone, R.string.group_call_start_voice), Quad(true, "group-call-start-video", Icons.Video, R.string.group_call_start_video))) {
                Box(
                    Modifier.weight(1f).heightIn(min = 48.dp).background(colors.pressed, LimeShapes.pill).semantics { role = Role.Button }.clickable { onStart(video) }.testTag(tag),
                    contentAlignment = Alignment.Center,
                ) {
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                        Icon(icon, null, tint = colors.text, modifier = Modifier.size(20.dp))
                        Text(stringResource(label), color = colors.text, style = LimeType.run { secondary.style() })
                    }
                }
            }
        }
    }
}

private data class Quad(val video: Boolean, val tag: String, val icon: androidx.compose.ui.graphics.vector.ImageVector, val label: Int)
