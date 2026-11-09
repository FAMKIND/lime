package com.limemessenger.lime.ui.chat

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
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
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.disabled
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTag
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.limemessenger.lime.R
import com.limemessenger.lime.chats.AttachmentFormat
import com.limemessenger.lime.chats.ChatModel
import com.limemessenger.lime.chats.ChatRow
import com.limemessenger.lime.chats.ChatsModel
import com.limemessenger.lime.chats.DeliveryState
import com.limemessenger.lime.chats.MessageFormat
import com.limemessenger.lime.chats.MessageSpeech
import com.limemessenger.lime.chats.isOwn
import com.limemessenger.lime.chats.isRequest
import com.limemessenger.lime.chats.state
import com.limemessenger.lime.ui.common.Avatar
import com.limemessenger.lime.ui.common.initialsOf
import com.limemessenger.lime.ui.shell.Icons
import com.limemessenger.lime.ui.theme.Lime
import kotlinx.coroutines.launch
import uniffi.lime_core.ConversationSummary
import uniffi.lime_core.MessageItem
import uniffi.lime_core.messagePlainText

/** A chat (iOS's `ChatView`): the header, the messages, and the composer (or Accept for a stranger's first message). The system back gesture closes it. */
@Composable
fun ChatScreen(model: ChatModel, chats: ChatsModel, onBack: () -> Unit, onOpenThread: (MessageItem) -> Unit = {}, modifier: Modifier = Modifier) {
    val colors = Lime.colors
    val scope = rememberCoroutineScope()
    val summary = model.summary
    val rows = remember(model.messages) { ChatRow.rows(model.messages) }
    val listState = rememberLazyListState()
    val lastOwnId = model.messages.lastOrNull { it.isOwn && it.state != DeliveryState.System }?.id

    // Read the messages again whenever the list was (a sync brought something), and mark the chat read while it is open.
    LaunchedEffect(chats.revision) { model.reload(); model.markRead() }
    // The newest message is in view on open and when something arrives or is sent.
    LaunchedEffect(rows.lastOrNull()?.id) { if (rows.isNotEmpty()) listState.scrollToItem(rows.lastIndex) }

    Column(modifier.fillMaxSize().background(colors.canvas).systemBarsPadding().imePadding()) {
        Header(summary, onBack)
        LazyColumn(Modifier.weight(1f).fillMaxWidth().testTag("chat-messages"), state = listState, contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 12.dp, vertical = 8.dp)) {
            items(rows, key = { it.id }) { row ->
                when (row) {
                    is ChatRow.Day -> DayChip(row.text)
                    is ChatRow.System -> SystemLine(row.item.text)
                    is ChatRow.DeletedRun -> Text(
                        stringResource(R.string.chat_deleted_run, row.count), color = colors.textSecondary, fontSize = 13.sp, fontStyle = FontStyle.Italic,
                        modifier = Modifier.fillMaxWidth().padding(vertical = 6.dp, horizontal = 24.dp).testTag("deleted-run"),
                    )
                    is ChatRow.Message -> MessageBubble(
                        item = row.item, summary = summary, showAvatar = row.showAvatar, endsRun = row.endsRun,
                        showState = row.item.isOwn && (row.item.state != DeliveryState.Sent || row.item.id == lastOwnId),
                        replyCount = model.replyCounts[row.item.id] ?: 0,
                        onRetry = { scope.launch { model.resend(row.item.id) } },
                        onReply = { model.replyingTo = row.item },
                        onOpenThread = { onOpenThread(row.item) },
                    )
                }
            }
        }
        model.banner?.let { Text(it, color = colors.danger, fontSize = 14.sp, modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp).testTag("chat-banner")) }
        if (summary != null && summary.isRequest) RequestBar(summary.title) { scope.launch { chats.acceptRequest(summary.id) } }
        else Composer(model) { text -> scope.launch { model.send(text) } }
    }
}

@Composable
private fun Header(summary: ConversationSummary?, onBack: () -> Unit) {
    val colors = Lime.colors
    val first = summary?.members?.firstOrNull()
    Row(Modifier.fillMaxWidth().heightIn(min = 64.dp).padding(horizontal = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        IconButton(onClick = onBack, Modifier.size(56.dp).testTag("chat-back")) {
            Icon(Icons.Back, contentDescription = stringResource(R.string.chat_back), tint = colors.text)
        }
        if (summary != null) {
            if (!summary.isGroup && first != null) Avatar(first.initials.ifEmpty { initialsOf(first.name) }, first.tone.toInt(), 36.dp)
            else Avatar(initialsOf(summary.title), 0, 36.dp, emoji = summary.groupEmoji)
        }
        Text(
            summary?.title.orEmpty(), color = colors.text, fontSize = 20.sp, fontWeight = FontWeight.SemiBold, maxLines = 1,
            modifier = Modifier.padding(start = 12.dp).weight(1f).semantics { heading() }.testTag("chat-title"),
        )
    }
}

@Composable
private fun DayChip(text: String) {
    val colors = Lime.colors
    Box(Modifier.fillMaxWidth().padding(vertical = 12.dp), contentAlignment = Alignment.Center) {
        Text(
            text, color = colors.textSecondary, fontSize = 13.sp, fontWeight = FontWeight.Medium,
            modifier = Modifier.background(colors.surface, RoundedCornerShape(12.dp)).padding(horizontal = 10.dp, vertical = 4.dp).semantics { heading() }.testTag("day-separator"),
        )
    }
}

@Composable
private fun SystemLine(text: String) {
    Text(text, color = Lime.colors.textSecondary, fontSize = 13.sp, modifier = Modifier.fillMaxWidth().padding(vertical = 6.dp, horizontal = 24.dp).testTag("system-line"))
}

/**
 * One message: my bubble on the right (the own colour), theirs on the left. The whole message, its time and its state is ONE TalkBack stop
 * ("<who>, <words>, <time>, <state>"); Copy, Reply, Retry and Open link are its custom actions as well as a long-press menu.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun MessageBubble(
    item: MessageItem, summary: ConversationSummary?, showAvatar: Boolean, endsRun: Boolean, showState: Boolean, replyCount: Int,
    onRetry: () -> Unit, onReply: () -> Unit, onOpenThread: () -> Unit,
) {
    val colors = Lime.colors
    val context = LocalContext.current
    val own = item.isOwn
    val sender = summary?.members?.firstOrNull { it.id == item.senderId }
    val isGroup = summary?.isGroup == true
    val label = MessageSpeech.label(item, sender?.name, replyCount, plainText = ::messagePlainText)
    var menu by remember { mutableStateOf(false) }
    val plain = remember(item.text) { messagePlainText(item.text) }
    val copyLabel = stringResource(R.string.chat_copy)
    val replyLabel = stringResource(R.string.chat_reply)
    val retryLabel = stringResource(if (item.state == DeliveryState.Undelivered) R.string.chat_resend_action else R.string.chat_retry_action)
    val failed = own && (item.state == DeliveryState.Failed || item.state == DeliveryState.Undelivered)
    val maxBubble = (LocalConfiguration.current.screenWidthDp * 0.78f).dp
    val actions = buildList {
        if (!item.deleted && plain.isNotEmpty()) add(CustomAccessibilityAction(copyLabel) { copy(context, plain); true })
        if (!item.deleted) add(CustomAccessibilityAction(replyLabel) { onReply(); true })
        if (failed) add(CustomAccessibilityAction(retryLabel) { onRetry(); true })
    }
    Row(
        Modifier.fillMaxWidth().padding(vertical = 2.dp),
        horizontalArrangement = if (own) Arrangement.End else Arrangement.Start,
    ) {
        if (!own) {
            if (showAvatar && sender != null) Avatar(sender.initials.ifEmpty { initialsOf(sender.name) }, sender.tone.toInt(), 32.dp)
            else Spacer(Modifier.size(32.dp))
            Spacer(Modifier.size(8.dp))
        }
        Column(horizontalAlignment = if (own) Alignment.End else Alignment.Start) {
            Column(
                Modifier.clearAndSetSemantics { contentDescription = label; customActions = actions; role = Role.Button; testTag = "message-${item.id}" },
                horizontalAlignment = if (own) Alignment.End else Alignment.Start,
            ) {
                if (!own && isGroup && showAvatar && sender != null) Text(sender.name, color = colors.textSecondary, fontSize = 13.sp, modifier = Modifier.padding(start = 4.dp, bottom = 2.dp))
                Box {
                    val bubbleShape = RoundedCornerShape(22.dp)
                    Column(
                        Modifier.widthIn(max = maxBubble)
                            .then(if (item.deleted) Modifier.border(0.8.dp, colors.bubbleEdge, bubbleShape) else if (own) Modifier.background(colors.own, bubbleShape) else Modifier.background(colors.bubbleOther, bubbleShape).border(0.8.dp, colors.bubbleEdge, bubbleShape))
                            .combinedClickable(onClick = {}, onLongClick = { menu = true }, onClickLabel = null)
                            .padding(horizontal = 14.dp, vertical = 10.dp),
                        verticalArrangement = Arrangement.spacedBy(4.dp),
                    ) {
                        if (item.deleted) {
                            Text(stringResource(R.string.chat_deleted), color = colors.textSecondary, fontSize = 16.sp, fontStyle = FontStyle.Italic)
                        } else {
                            if (item.text.isNotEmpty()) MessageText(item.text, color = if (own) colors.ownInk else colors.text, linkColor = if (own) colors.linkOwn else colors.link, modifier = Modifier.testTag("message-text-${item.id}"))
                            AttachmentFormat.summary(item.attachments)?.let { Text(it, color = if (own) colors.ownInk else colors.text, fontSize = 16.sp, fontWeight = FontWeight.SemiBold) }
                        }
                    }
                    DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                        if (!item.deleted && plain.isNotEmpty()) DropdownMenuItem(text = { Text(copyLabel) }, onClick = { menu = false; copy(context, plain) }, modifier = Modifier.testTag("action-copy"))
                        if (!item.deleted) DropdownMenuItem(text = { Text(replyLabel) }, onClick = { menu = false; onReply() }, modifier = Modifier.testTag("action-reply"))
                        if (failed) DropdownMenuItem(text = { Text(retryLabel) }, onClick = { menu = false; onRetry() })
                    }
                }
                if (!item.deleted && (endsRun || showState || item.edited)) Footer(item, showState, onRetry)
            }
            if (replyCount > 0 && !item.deleted) {
                val words = if (replyCount == 1) stringResource(R.string.chat_reply_one) else stringResource(R.string.chat_reply_other, replyCount)
                Box(Modifier.heightIn(min = 48.dp).clickable(onClick = onOpenThread).padding(horizontal = 4.dp), contentAlignment = Alignment.CenterStart) {
                    Text(words, color = colors.text, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.testTag("replies-${item.id}"))
                }
            }
        }
    }
}

/** The time, "Edited" and the delivery state under a message (as iOS: Sending…, Sent, Not sent, Not delivered; the nearby-phone words). */
@Composable
private fun Footer(item: MessageItem, showState: Boolean, onRetry: () -> Unit) {
    val colors = Lime.colors
    Row(Modifier.padding(horizontal = 6.dp, vertical = 2.dp), horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(MessageFormat.clock(item.sentAt), color = colors.textSecondary, fontSize = 12.sp, modifier = Modifier.testTag("message-time-${item.id}"))
        if (item.edited) Text(stringResource(R.string.chat_edited), color = colors.textSecondary, fontSize = 12.sp)
        if (showState && item.isOwn) when (val state = item.state) {
            DeliveryState.Sending -> Text(stringResource(R.string.chat_state_sending), color = colors.textSecondary, fontSize = 12.sp, modifier = Modifier.testTag("delivery-sending"))
            DeliveryState.Sent -> Text(stringResource(R.string.chat_state_sent), color = colors.textSecondary, fontSize = 12.sp, modifier = Modifier.testTag("delivery-sent"))
            DeliveryState.Failed -> Text(stringResource(R.string.chat_state_not_sent), color = colors.danger, fontSize = 12.sp, modifier = Modifier.heightIn(min = 48.dp).clickable(onClick = onRetry).padding(vertical = 14.dp).testTag("delivery-failed"))
            DeliveryState.Undelivered -> Text(stringResource(R.string.chat_state_not_delivered), color = colors.danger, fontSize = 12.sp, modifier = Modifier.heightIn(min = 48.dp).clickable(onClick = onRetry).padding(vertical = 14.dp).testTag("delivery-undelivered"))
            DeliveryState.Waiting, DeliveryState.Passed, DeliveryState.Offline -> Text("· ${state.statusWords}", color = colors.textSecondary, fontSize = 12.sp, modifier = Modifier.testTag("delivery-${state.raw}"))
            else -> {}
        }
    }
}

@Composable
private fun RequestBar(title: String, onAccept: () -> Unit) {
    val colors = Lime.colors
    Column(Modifier.fillMaxWidth().background(colors.surface).padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(stringResource(R.string.chat_request_bar, title), color = colors.text, fontSize = 16.sp, modifier = Modifier.testTag("request-bar"))
        Box(
            Modifier.fillMaxWidth().heightIn(min = 52.dp).background(colors.accent, RoundedCornerShape(26.dp))
                .semantics { role = Role.Button }.clickable(onClick = onAccept).testTag("request-accept"),
            contentAlignment = Alignment.Center,
        ) { Text(stringResource(R.string.chat_accept), color = colors.accentInk, fontSize = 17.sp, fontWeight = FontWeight.SemiBold) }
    }
}

/** The composer: plain text tonight (no formatting toolbar), a reply bar when replying, and send = the one lime action. */
@Composable
private fun Composer(model: ChatModel, onSend: (String) -> Unit) {
    val colors = Lime.colors
    var text by rememberSaveable { mutableStateOf("") }
    val reply = model.replyingTo
    Column(Modifier.fillMaxWidth().background(colors.canvas).padding(horizontal = 8.dp, vertical = 6.dp)) {
        if (reply != null) {
            val name = model.summary?.members?.firstOrNull { it.id == reply.senderId }?.name?.split(" ")?.firstOrNull() ?: "you"
            Row(Modifier.fillMaxWidth().background(colors.surface, RoundedCornerShape(12.dp)).padding(start = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f).padding(vertical = 8.dp)) {
                    Text(stringResource(R.string.chat_replying_to, name), color = colors.text, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.testTag("reply-bar"))
                    Text(messagePlainText(reply.text).replace("\n", " ").ifEmpty { AttachmentFormat.summary(reply.attachments).orEmpty() }, color = colors.textSecondary, fontSize = 13.sp, maxLines = 1)
                }
                IconButton(onClick = { model.replyingTo = null }, Modifier.size(48.dp).testTag("reply-cancel")) {
                    Icon(Icons.Close, contentDescription = stringResource(R.string.chat_cancel_reply), tint = colors.text)
                }
            }
            Spacer(Modifier.size(6.dp))
        }
        Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedTextField(
                value = text, onValueChange = { text = it }, modifier = Modifier.weight(1f).heightIn(min = 56.dp).testTag("composer-field"),
                placeholder = { Text(stringResource(R.string.chat_message_hint), color = colors.textSecondary) }, maxLines = 5,
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Default), shape = RoundedCornerShape(24.dp),
                colors = OutlinedTextFieldDefaults.colors(
                    focusedTextColor = colors.text, unfocusedTextColor = colors.text, focusedContainerColor = colors.surface, unfocusedContainerColor = colors.surface,
                    focusedBorderColor = colors.text, unfocusedBorderColor = colors.hairline, cursorColor = colors.text,
                ),
            )
            val canSend = text.isNotBlank()
            val sendLabel = stringResource(R.string.chat_send)
            Box(
                Modifier.size(56.dp).background(if (canSend) colors.accent else colors.pressed, CircleShape)
                    .then(if (canSend) Modifier.clickable(role = Role.Button) { onSend(text); text = "" } else Modifier.semantics { role = Role.Button; disabled() })
                    .semantics { contentDescription = sendLabel }.testTag("send-button"),
                contentAlignment = Alignment.Center,
            ) { Icon(Icons.Send, contentDescription = null, tint = if (canSend) colors.accentInk else colors.textSecondary) }
        }
    }
}

private fun copy(context: Context, text: String) {
    (context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).setPrimaryClip(ClipData.newPlainText("message", text))
}

/** A thread's replies, read-only tonight. */
@Composable
fun ThreadScreen(root: MessageItem, model: ChatModel, onBack: () -> Unit) {
    val colors = Lime.colors
    var replies by remember { mutableStateOf<List<MessageItem>>(emptyList()) }
    LaunchedEffect(root.id) { replies = model.thread(root.id) }
    Column(Modifier.fillMaxSize().background(colors.canvas).systemBarsPadding()) {
        Row(Modifier.fillMaxWidth().heightIn(min = 64.dp), verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = onBack, Modifier.size(56.dp)) { Icon(Icons.Back, stringResource(R.string.chat_back), tint = colors.text) }
            Text(stringResource(R.string.chat_thread_title), color = colors.text, fontSize = 20.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.semantics { heading() })
        }
        LazyColumn(Modifier.weight(1f).testTag("thread-replies"), contentPadding = androidx.compose.foundation.layout.PaddingValues(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            item { Text(messagePlainText(root.text), color = colors.textSecondary, fontSize = 15.sp) }
            items(replies, key = { it.id }) { reply ->
                val own = reply.isOwn
                Box(Modifier.fillMaxWidth(), contentAlignment = if (own) Alignment.CenterEnd else Alignment.CenterStart) {
                    Text(
                        messagePlainText(reply.text), color = if (own) colors.ownInk else colors.text, fontSize = 16.sp,
                        modifier = Modifier.background(if (own) colors.own else colors.bubbleOther, RoundedCornerShape(18.dp)).padding(12.dp),
                    )
                }
            }
        }
    }
}
