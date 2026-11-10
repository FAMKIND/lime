package com.limemessenger.lime.ui.chats

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
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
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.limemessenger.lime.R
import com.limemessenger.lime.chats.RowAction
import com.limemessenger.lime.chats.rowActions
import com.limemessenger.lime.ui.theme.Lime
import uniffi.lime_core.ConversationSummary
import uniffi.lime_core.MuteDuration
import uniffi.lime_core.muteDurationTitle
import uniffi.lime_core.muteDurations

// What a swipe or a long-press on a chat row offers, as iOS's row actions (MessagesView): Read/Unread, Pin/Unpin, Mute/Unmute (with how long),
// a private label for a person, and Leave / Delete / Clear / Delete chat with iOS's confirmations.

@Composable
fun rowActionTitle(action: RowAction): String = stringResource(when (action) {
    RowAction.MarkRead -> R.string.row_action_read
    RowAction.MarkUnread -> R.string.row_action_unread
    RowAction.Pin -> R.string.row_action_pin
    RowAction.Unpin -> R.string.row_action_unpin
    RowAction.Mute -> R.string.row_action_mute
    RowAction.Unmute -> R.string.row_action_unmute
    RowAction.Label -> R.string.row_action_label
    RowAction.Leave -> R.string.row_action_leave
    RowAction.DeleteForEveryone -> R.string.row_action_delete_everyone
    RowAction.Clear -> R.string.row_action_clear
    RowAction.DeleteChat -> R.string.row_action_delete
})

fun rowActionTag(action: RowAction): String = "row-action-" + action.name.lowercase()

/** The sheet of a row's actions, then the choices an action leads to (mute durations, a label, a confirmation). */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ChatRowActionsHost(
    chat: ConversationSummary, muted: Boolean, open: Boolean, pending: RowAction?, onDismiss: () -> Unit, onPick: (RowAction) -> Unit, onClearPending: () -> Unit,
    onRun: (RowAction, MuteDuration?, String?) -> Unit,
) {
    val colors = Lime.colors
    if (open) {
        ModalBottomSheet(onDismissRequest = onDismiss, containerColor = colors.canvas) {
            Column(Modifier.testTag("row-actions").padding(bottom = 16.dp)) {
                Text(chat.title, color = colors.textSecondary, fontSize = 14.sp, modifier = Modifier.padding(horizontal = 24.dp, vertical = 6.dp))
                rowActions(chat, muted).forEach { action ->
                    val danger = action == RowAction.Leave || action == RowAction.DeleteForEveryone || action == RowAction.Clear || action == RowAction.DeleteChat
                    Row(
                        Modifier.fillMaxWidth().heightIn(min = 52.dp).semantics { role = Role.Button }.clickable { onPick(action) }.padding(horizontal = 24.dp).testTag(rowActionTag(action)),
                        verticalAlignment = Alignment.CenterVertically,
                    ) { Text(rowActionTitle(action), color = if (danger) colors.danger else colors.text, fontSize = 17.sp) }
                }
            }
        }
    }
    when (pending) {
        RowAction.Mute -> ModalBottomSheet(onDismissRequest = onClearPending, containerColor = colors.canvas) {
            Column(Modifier.testTag("mute-sheet").padding(bottom = 16.dp)) {
                Text(stringResource(R.string.row_mute_title, chat.title), color = colors.text, fontSize = 20.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(horizontal = 24.dp, vertical = 8.dp))
                muteDurations().forEach { duration ->
                    Row(
                        Modifier.fillMaxWidth().heightIn(min = 52.dp).semantics { role = Role.Button }.clickable { onRun(RowAction.Mute, duration, null) }.padding(horizontal = 24.dp).testTag("mute-${duration.name.lowercase()}"),
                        verticalAlignment = Alignment.CenterVertically,
                    ) { Text(muteDurationTitle(duration), color = colors.text, fontSize = 17.sp) }
                }
            }
        }
        RowAction.Label -> {
            var text by remember { mutableStateOf(chat.members.firstOrNull()?.label.orEmpty()) }
            AlertDialog(
                onDismissRequest = onClearPending,
                title = { Text(stringResource(R.string.row_label_title, chat.members.firstOrNull()?.name ?: chat.title)) },
                text = {
                    Column {
                        OutlinedTextField(value = text, onValueChange = { text = it.take(30) }, singleLine = true, modifier = Modifier.fillMaxWidth().testTag("label-field"))
                        Text(stringResource(R.string.row_label_note), color = colors.textSecondary, fontSize = 13.sp, modifier = Modifier.padding(top = 8.dp))
                    }
                },
                confirmButton = { TextButton(onClick = { onRun(RowAction.Label, null, text) }, Modifier.heightIn(min = 48.dp).testTag("label-save")) { Text(stringResource(R.string.group_save)) } },
                dismissButton = { TextButton(onClick = onClearPending, Modifier.heightIn(min = 48.dp)) { Text(stringResource(R.string.group_cancel)) } },
            )
        }
        RowAction.Leave, RowAction.DeleteForEveryone, RowAction.Clear, RowAction.DeleteChat -> {
            val ended = chat.isGroup && chat.groupEnded != null
            val (title, body, button) = when (pending) {
                RowAction.Leave -> Triple(stringResource(R.string.row_leave_title, chat.title), stringResource(R.string.row_leave_body), stringResource(R.string.row_action_leave))
                RowAction.DeleteForEveryone -> Triple(stringResource(R.string.row_delete_group_title, chat.title), stringResource(R.string.row_delete_group_body), stringResource(R.string.row_action_delete_everyone))
                RowAction.Clear -> Triple(stringResource(R.string.row_clear_title, chat.title), stringResource(R.string.row_clear_body), stringResource(R.string.row_clear_button))
                else -> if (ended) Triple(stringResource(R.string.row_remove_group_title), stringResource(R.string.row_remove_group_body), stringResource(R.string.row_remove_group_button))
                else Triple(stringResource(R.string.row_delete_chat_title), stringResource(R.string.row_delete_chat_body), stringResource(R.string.row_delete_chat_button))
            }
            AlertDialog(
                onDismissRequest = onClearPending,
                title = { Text(title) },
                text = { Text(body) },
                confirmButton = { TextButton(onClick = { onRun(pending, null, null) }, Modifier.heightIn(min = 48.dp).testTag("row-confirm")) { Text(button, color = colors.danger) } },
                dismissButton = { TextButton(onClick = onClearPending, Modifier.heightIn(min = 48.dp)) { Text(stringResource(R.string.group_cancel)) } },
            )
        }
        else -> {}
    }
}
