package com.limemessenger.lime.ui.chat

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
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
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.limemessenger.lime.R
import com.limemessenger.lime.chats.MAX_FORWARD_CHATS
import com.limemessenger.lime.ui.common.Avatar
import com.limemessenger.lime.ui.common.GroupAvatar
import com.limemessenger.lime.ui.common.initialsOf
import com.limemessenger.lime.ui.shell.Icons
import com.limemessenger.lime.ui.theme.Lime
import uniffi.lime_core.ConversationSummary
import uniffi.lime_core.MessageAction
import uniffi.lime_core.MessageItem
import uniffi.lime_core.quickReactions

// The long-press menu of a message, as iOS's `MessageActionsHost`: the six quick reactions, then the actions in the core's order.  TalkBack gets the same actions as custom actions on the message (ChatScreen), never a gesture-only menu.

/** The words of an action, as in the iOS menu. */
@Composable
fun actionTitle(action: MessageAction): String = stringResource(when (action) {
    MessageAction.REACT -> R.string.message_action_react
    MessageAction.REPLY -> R.string.chat_reply
    MessageAction.FORWARD -> R.string.message_action_forward
    MessageAction.EDIT -> R.string.message_action_edit
    MessageAction.COPY -> R.string.chat_copy
    MessageAction.SAVE_GIF -> R.string.message_action_save_gif
    MessageAction.SELECT -> R.string.message_action_select
    MessageAction.REPORT -> R.string.message_action_report
    MessageAction.DELETE -> R.string.message_action_delete
})

/** The actions this screen has: all of the core's list. */
fun shownActions(plan: List<MessageAction>): List<MessageAction> = plan

fun actionTag(action: MessageAction): String = "action-" + action.name.lowercase().replace('_', '-')

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MessageActionsSheet(message: MessageItem, plan: List<MessageAction>, onReact: (String) -> Unit, onAction: (MessageAction) -> Unit, onDismiss: () -> Unit) {
    val colors = Lime.colors
    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = colors.canvas) {
        Column(Modifier.testTag("message-actions").padding(bottom = 16.dp)) {
            if (MessageAction.REACT in plan) {
                Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 8.dp), horizontalArrangement = Arrangement.SpaceBetween) {
                    quickReactions().forEach { emoji ->
                        val mine = message.reactions.firstOrNull { it.emoji == emoji }?.mine == true
                        val words = stringResource(R.string.message_react_with, emoji)
                        Box(
                            Modifier.size(48.dp).background(if (mine) colors.surface else colors.canvas, CircleShape)
                                .semantics { contentDescription = words; role = Role.Button; selected = mine }.clickable { onReact(emoji) }.testTag("react-$emoji"),
                            contentAlignment = Alignment.Center,
                        ) { Text(emoji, fontSize = 24.sp) }
                    }
                }
            }
            shownActions(plan).filter { it != MessageAction.REACT }.forEach { action ->
                val danger = action == MessageAction.DELETE
                Row(
                    Modifier.fillMaxWidth().heightIn(min = 52.dp).semantics { role = Role.Button }.clickable { onAction(action) }.padding(horizontal = 24.dp).testTag(actionTag(action)),
                    verticalAlignment = Alignment.CenterVertically,
                ) { Text(actionTitle(action), color = if (danger) colors.danger else colors.text, fontSize = 17.sp) }
            }
        }
    }
}

/** Edit: the message's words in a small dialog; Save is off for blank words (a caption-less photo may be saved blank, as iOS). */
@Composable
fun EditMessageDialog(initial: String, allowBlank: Boolean, onSave: (String) -> Unit, onCancel: () -> Unit) {
    var text by remember { mutableStateOf(initial) }
    AlertDialog(
        onDismissRequest = onCancel,
        title = { Text(stringResource(R.string.message_edit_title)) },
        text = { OutlinedTextField(value = text, onValueChange = { text = it }, modifier = Modifier.fillMaxWidth().testTag("edit-field")) },
        confirmButton = { TextButton(onClick = { onSave(text) }, enabled = allowBlank || text.trim().isNotEmpty(), modifier = Modifier.heightIn(min = 48.dp).testTag("edit-save")) { Text(stringResource(R.string.group_save)) } },
        dismissButton = { TextButton(onClick = onCancel, Modifier.heightIn(min = 48.dp)) { Text(stringResource(R.string.group_cancel)) } },
    )
}

/** Delete: for me always; for everyone when every message allows it (the core's rule), with iOS's words. */
@Composable
fun DeleteMessagesDialog(count: Int, everyoneAllowed: Boolean, onDelete: (everyone: Boolean) -> Unit, onCancel: () -> Unit) {
    val colors = Lime.colors
    AlertDialog(
        onDismissRequest = onCancel,
        title = { Text(if (count > 1) stringResource(R.string.message_delete_title_many, count) else stringResource(R.string.message_delete_title_one)) },
        text = {
            Text(
                when {
                    everyoneAllowed && count == 1 -> stringResource(R.string.message_delete_body_everyone_one)
                    everyoneAllowed -> stringResource(R.string.message_delete_body_everyone_many)
                    count == 1 -> stringResource(R.string.message_delete_body_me_one)
                    else -> stringResource(R.string.message_delete_body_me_many)
                },
            )
        },
        confirmButton = {
            Column(horizontalAlignment = Alignment.End) {
                if (everyoneAllowed) TextButton(onClick = { onDelete(true) }, Modifier.heightIn(min = 48.dp).testTag("delete-for-everyone")) { Text(stringResource(R.string.message_delete_everyone), color = colors.danger) }
                TextButton(onClick = { onDelete(false) }, Modifier.heightIn(min = 48.dp).testTag("delete-for-me")) { Text(stringResource(R.string.message_delete_me), color = colors.danger) }
            }
        },
        dismissButton = { TextButton(onClick = onCancel, Modifier.heightIn(min = 48.dp)) { Text(stringResource(R.string.group_cancel)) } },
    )
}

/** Forward: pick up to five chats, then Send (iOS's `ForwardSheet`). */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ForwardSheet(targets: List<ConversationSummary>, myName: String, myTone: Int, onSend: (List<String>) -> Unit, onDismiss: () -> Unit) {
    val colors = Lime.colors
    var chosen by remember { mutableStateOf(listOf<String>()) }
    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = colors.canvas) {
        Column(Modifier.testTag("forward-sheet")) {
            Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(R.string.message_forward_title), color = colors.text, fontSize = 20.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
                Box(
                    Modifier.heightIn(min = 48.dp).background(if (chosen.isEmpty()) colors.pressed else colors.accent, RoundedCornerShape(24.dp))
                        .then(if (chosen.isEmpty()) Modifier else Modifier.semantics { role = Role.Button }.clickable { onSend(chosen) }).padding(horizontal = 18.dp).testTag("forward-send"),
                    contentAlignment = Alignment.Center,
                ) { Text(stringResource(R.string.message_forward_send), color = if (chosen.isEmpty()) colors.textSecondary else colors.accentInk, fontSize = 17.sp, fontWeight = FontWeight.SemiBold) }
            }
            Text(stringResource(R.string.message_forward_limit, MAX_FORWARD_CHATS), color = colors.textSecondary, fontSize = 14.sp, modifier = Modifier.padding(horizontal = 20.dp, vertical = 4.dp))
            LazyColumn(Modifier.heightIn(max = 420.dp)) {
                items(targets, key = { it.id }) { chat ->
                    val on = chat.id in chosen
                    val first = chat.members.firstOrNull()
                    Row(
                        Modifier.fillMaxWidth().heightIn(min = 60.dp).semantics(mergeDescendants = true) { role = Role.Checkbox; selected = on }
                            .clickable { chosen = if (on) chosen - chat.id else if (chosen.size < MAX_FORWARD_CHATS) chosen + chat.id else chosen }
                            .padding(horizontal = 20.dp, vertical = 6.dp).testTag("forward-pick-${chat.id}"),
                        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp),
                    ) {
                        if (!chat.isGroup && first != null) Avatar(first.initials.ifEmpty { initialsOf(first.name) }, first.tone.toInt(), 44.dp) else GroupAvatar(chat, myName, myTone, 44.dp)
                        Text(chat.title, color = colors.text, fontSize = 17.sp, modifier = Modifier.weight(1f))
                        Icon(if (on) Icons.CheckedBox else Icons.UncheckedBox, null, tint = if (on) colors.text else colors.textSecondary, modifier = Modifier.size(24.dp))
                    }
                }
            }
        }
    }
}

/** The reactions under a bubble: one chip per emoji with its count; mine is filled; tapping one toggles mine. Each chip is its own 48 dp button for TalkBack. */
@Composable
fun ReactionChips(message: MessageItem, onToggle: (String) -> Unit) {
    if (message.reactions.isEmpty() || message.deleted) return
    val colors = Lime.colors
    Row(Modifier.padding(top = 2.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        message.reactions.forEach { r ->
            val words = stringResource(if (r.mine) R.string.message_reaction_mine else R.string.message_reaction_chip, r.emoji, r.count.toInt())
            Row(
                Modifier.heightIn(min = 48.dp).semantics { contentDescription = words; role = Role.Button; selected = r.mine }.clickable { onToggle(r.emoji) }.testTag("reaction-${message.id}-${r.emoji}"),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Row(
                    Modifier.background(if (r.mine) colors.own else colors.surface, RoundedCornerShape(14.dp)).padding(horizontal = 8.dp, vertical = 3.dp),
                    horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(r.emoji, fontSize = 14.sp)
                    if (r.count > 1u) Text("${r.count}", color = if (r.mine) colors.ownInk else colors.text, fontSize = 13.sp)
                }
            }
        }
    }
}
