package com.limemessenger.lime.ui.chat

import androidx.compose.foundation.clickable
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.limemessenger.lime.R
import com.limemessenger.lime.chats.isOwn
import com.limemessenger.lime.ui.shell.Icons
import com.limemessenger.lime.ui.theme.Lime
import com.limemessenger.lime.ui.theme.LimeShapes
import com.limemessenger.lime.ui.theme.LimeType
import com.limemessenger.lime.ui.theme.LimeType.style
import uniffi.lime_core.CallBubbleWords
import uniffi.lime_core.ConversationSummary
import uniffi.lime_core.MessageItem

/**
 * A call as it shows in a 1:1 chat (iOS `CallBubbleView`): an icon, the title ("Voice call", "Missed voice call") and a second line (the length, or what became of
 * it), in the danger red when it is a missed incoming call. The words are the core's (`call_bubble_words`). One TalkBack stop; a tap asks, then calls back.
 */
@Composable
internal fun CallBubbleRow(item: MessageItem, words: CallBubbleWords, summary: ConversationSummary?, onCallBack: (peerId: String, name: String, video: Boolean) -> Unit) {
    val colors = Lime.colors
    val own = item.isOwn
    val spoken = stringResource(R.string.calls_bubble_label, words.title, words.detail)
    var asking by remember { mutableStateOf(false) }
    val peer = summary?.members?.firstOrNull()
    val tint = if (words.isMissedIncoming) colors.danger else colors.text
    Row(
        Modifier.fillMaxWidth().padding(vertical = 2.dp).padding(start = if (own) 0.dp else 40.dp),
        horizontalArrangement = if (own) Arrangement.End else Arrangement.Start,
    ) {
        Row(
            Modifier.background(colors.surface, LimeShapes.bubble)
                .semantics { contentDescription = spoken; role = Role.Button }
                .clickable(enabled = peer != null && !words.isGroup) { asking = true }
                .padding(horizontal = 14.dp, vertical = 10.dp).testTag("call-bubble-${item.id.removePrefix("call:")}"),
            horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(if (words.video) Icons.Video else Icons.Phone, null, tint = tint, modifier = Modifier.size(22.dp).clearAndSetSemantics { })
            Column(Modifier.clearAndSetSemantics { }, verticalArrangement = Arrangement.spacedBy(1.dp)) {
                Text(words.title, color = tint, style = LimeType.run { body.style() }, modifier = Modifier.testTag("call-bubble-title"))
                Text(words.detail, color = colors.textSecondary, style = LimeType.run { caption.style() }, modifier = Modifier.testTag("call-bubble-detail"))
            }
        }
    }
    if (asking && peer != null) {
        AlertDialog(
            onDismissRequest = { asking = false }, modifier = Modifier.testTag("call-bubble-ask"),
            title = { Text(stringResource(R.string.calls_bubble_ask_title, peer.name)) },
            confirmButton = { TextButton(onClick = { asking = false; onCallBack(peer.id, peer.name, words.video) }, modifier = Modifier.heightIn(min = 48.dp).testTag("call-bubble-ask-call")) { Text(stringResource(if (words.video) R.string.calls_bubble_ask_video else R.string.calls_bubble_ask_voice)) } },
            dismissButton = { TextButton(onClick = { asking = false }, modifier = Modifier.heightIn(min = 48.dp).testTag("call-bubble-ask-cancel")) { Text(stringResource(R.string.calls_bubble_ask_cancel)) } },
        )
    }
}
