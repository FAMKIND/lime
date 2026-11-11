package com.limemessenger.lime.ui.chat

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.Image
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.TextButton
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import com.limemessenger.lime.chats.AttachmentProcessing
import android.widget.Toast
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import uniffi.lime_core.AttachmentInfo
import uniffi.lime_core.OutgoingAttachment
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
import com.limemessenger.lime.chats.removeChat
import com.limemessenger.lime.chats.VoiceRecorder
import kotlinx.coroutines.delay
import androidx.compose.ui.semantics.selected
import com.limemessenger.lime.chats.react
import com.limemessenger.lime.chats.edit
import com.limemessenger.lime.chats.delete
import com.limemessenger.lime.chats.forward
import com.limemessenger.lime.chats.forwardTargets
import com.limemessenger.lime.chats.ChatRow
import com.limemessenger.lime.chats.ChatsModel
import com.limemessenger.lime.chats.block
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
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.shadow
import androidx.compose.foundation.layout.isImeVisible
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import kotlinx.coroutines.launch
import uniffi.lime_core.ConversationSummary
import uniffi.lime_core.MessageItem
import uniffi.lime_core.messagePlainText

/** A chat (iOS's `ChatView`): the header, the messages, and the composer (or Accept for a stranger's first message). The system back gesture closes it. */
@Composable
fun ChatScreen(model: ChatModel, chats: ChatsModel, onBack: () -> Unit, onOpenThread: (MessageItem) -> Unit = {}, modifier: Modifier = Modifier, onOpenProfile: (String, String) -> Unit = { _, _ -> }, onOpenGroup: () -> Unit = {}, focusMessageId: String? = null,
    /** Photos already in the composer's draft strip (screenshots and tests: the Photo Picker cannot be driven headless). */
    seedPhotos: List<OutgoingAttachment> = emptyList()) {
    val colors = Lime.colors
    val scope = rememberCoroutineScope()
    val summary = model.summary
    val rows = remember(model.messages) { ChatRow.rows(model.messages) }
    val listState = rememberLazyListState()
    val lastOwnId = model.messages.lastOrNull { it.isOwn && it.state != DeliveryState.System }?.id
    var viewer by remember { mutableStateOf<Pair<MessageItem, Int>?>(null) }
    BackHandler(enabled = viewer != null) { viewer = null }
    // Message actions (LIME-304): the menu, the edit dialog, the delete confirmation, the forward picker, and Select mode.
    var menuFor by remember { mutableStateOf<MessageItem?>(null) }
    var editing by remember { mutableStateOf<MessageItem?>(null) }
    var deleting by remember { mutableStateOf<List<MessageItem>>(emptyList()) }
    var forwarding by remember { mutableStateOf<List<String>?>(null) }
    var reporting by remember { mutableStateOf<uniffi.lime_core.ReportTargetInfo?>(null) }
    var blocking by remember { mutableStateOf(false) }
    var gifPanel by remember { mutableStateOf(false) }
    var selection by remember { mutableStateOf<Set<String>?>(null) }
    BackHandler(enabled = selection != null && viewer == null) { selection = null }
    val context = LocalContext.current
    // Voice messages (LIME-308): one player for the chat; the next voice message of the chat plays on by itself; bytes are looked up by attachment id.
    val voice = remember { com.limemessenger.lime.chats.VoicePlayer(context.applicationContext) }
    androidx.compose.runtime.DisposableEffect(Unit) { onDispose { voice.stop() } }
    val voiceNext: (String) -> String? = { id ->
        val all = model.messages.filter { !it.deleted }.flatMap { m -> m.attachments.filter { it.mime.startsWith("audio/") } }
        all.getOrNull(all.indexOfFirst { it.id == id } + 1)?.id
    }
    val voiceData: suspend (String) -> ByteArray? = { id -> model.messages.flatMap { it.attachments }.firstOrNull { it.id == id }?.let { model.attachmentBytes(it) } }
    fun perform(action: uniffi.lime_core.MessageAction, item: MessageItem) {
        menuFor = null
        when (action) {
            uniffi.lime_core.MessageAction.REPLY -> model.replyingTo = item
            uniffi.lime_core.MessageAction.COPY -> copy(context, messagePlainText(item.text))
            uniffi.lime_core.MessageAction.FORWARD -> forwarding = listOf(item.id)
            uniffi.lime_core.MessageAction.EDIT -> editing = item
            uniffi.lime_core.MessageAction.SELECT -> selection = setOf(item.id)
            uniffi.lime_core.MessageAction.DELETE -> deleting = listOf(item)
            uniffi.lime_core.MessageAction.SAVE_GIF -> scope.launch {
                val gif = item.attachments.firstOrNull { it.mime == "image/gif" }
                val bytes = gif?.let { model.attachmentBytes(it) }
                val info = bytes?.let { uniffi.lime_core.gifInspect(it) }
                val ok = bytes != null && withContext(Dispatchers.IO) { runCatching { chats.core()!!.addMyGif(bytes, "", messagePlainText(item.text), "", info?.width, info?.height) }.isSuccess }
                Toast.makeText(context, if (ok) R.string.gif_saved_to_mine else R.string.gif_save_failed, Toast.LENGTH_SHORT).show()
            }
            uniffi.lime_core.MessageAction.REPORT -> {
                val sender = item.senderId.orEmpty()
                val name = summary?.members?.firstOrNull { it.id == sender }?.name ?: summary?.title
                reporting = uniffi.lime_core.reportTargetMessage(item.id, item.conversationId, sender, name, messagePlainText(item.text), item.sentAt, item.attachments.size.toUInt())
            }
            else -> {}
        }
    }

    // Read the messages again whenever the list was (a sync brought something), and mark the chat read while it is open.
    LaunchedEffect(chats.revision) { model.reload(); model.markRead() }
    // The newest message is in view on open and when something arrives or is sent.
    // (A search result opens the chat at its message instead.)
    var focused by remember { mutableStateOf(false) }
    LaunchedEffect(rows.lastOrNull()?.id, focusMessageId) {
        if (rows.isEmpty()) return@LaunchedEffect
        val target = if (focusMessageId != null) rows.indexOfFirst { it.id == focusMessageId } else -1
        if (target >= 0 && !focused) { listState.scrollToItem(target); focused = true } else if (target < 0 || focused) { if (focusMessageId == null || focused) listState.scrollToItem(rows.lastIndex) }
    }

    Column(modifier.fillMaxSize().background(colors.canvas).systemBarsPadding().imePadding()) {
        val chosen = selection
        if (chosen != null) SelectionBar(chosen.size, onCancel = { selection = null },
            onForward = { forwarding = chosen.toList() }, onDelete = { deleting = model.messages.filter { it.id in chosen } })
        else Header(summary, chats.myName, chats.myTone, onBack, onOpenGroup) { m -> onOpenProfile(m.id, m.name) }
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
                        model = model,
                        onOpenPhoto = { index -> viewer = row.item to index },
                        selecting = selection != null, selected = selection?.contains(row.item.id) == true,
                        onToggleSelect = { selection = selection?.let { if (row.item.id in it) it - row.item.id else it + row.item.id } },
                        onOpenMenu = { menuFor = row.item },
                        onPerform = { action -> perform(action, row.item) },
                        onReact = { emoji -> scope.launch { model.react(row.item, emoji) } },
                        voice = voice, voiceNext = voiceNext, voiceData = voiceData,
                    )
                }
            }
        }
        model.banner?.let { Text(it, color = colors.danger, fontSize = 14.sp, modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp).testTag("chat-banner")) }
        if (summary != null && summary.isRequest) RequestBar(summary.title, onBlock = { blocking = true }) { scope.launch { chats.acceptRequest(summary.id) } }
        else if (summary?.groupEnded != null) EndedBar(summary.groupEnded == "left") { scope.launch { chats.removeChat(summary.id); onBack() } }
        else if (selection == null) Composer(model, seedPhotos, panelOpen = gifPanel, onGif = { gifPanel = true }) { text, photos -> scope.launch { if (photos.isNotEmpty()) model.sendPhotos(photos, text) else model.send(text) } }
    }
    viewer?.let { (item, index) -> PhotoViewer(item.attachments.filter { it.mime.startsWith("image/") }, index, model, onClose = { viewer = null }) }
    menuFor?.let { item ->
        MessageActionsSheet(item, uniffi.lime_core.messageActions(item, false, System.currentTimeMillis()),
            onReact = { emoji -> menuFor = null; scope.launch { model.react(item, emoji) } }, onAction = { perform(it, item) }, onDismiss = { menuFor = null })
    }
    editing?.let { item ->
        EditMessageDialog(item.text, allowBlank = item.attachments.isNotEmpty(),
            onSave = { text -> editing = null; scope.launch { model.edit(item, text) } }, onCancel = { editing = null })
    }
    if (gifPanel) GifPanel(chats, onSend = { gif -> gifPanel = false; scope.launch { model.sendPhotos(listOf(gif), "", "GIF") } }, onDismiss = { gifPanel = false })
    reporting?.let { target -> com.limemessenger.lime.ui.moderation.ReportDialog(target, chats, onDismiss = { reporting = null }) }
    if (blocking && summary != null) com.limemessenger.lime.ui.moderation.BlockConfirm(
        summary.title, stringResource(R.string.block_request_body), "request-block-confirm",
        onConfirm = { blocking = false; scope.launch { chats.block(summary.id); onBack() } }, onDismiss = { blocking = false },
    )
    if (deleting.isNotEmpty()) {
        val now = System.currentTimeMillis()
        DeleteMessagesDialog(deleting.size, everyoneAllowed = deleting.all { uniffi.lime_core.canDeleteForEveryone(it, now) },
            onDelete = { everyone -> val ids = deleting.map { it.id }; deleting = emptyList(); selection = null; scope.launch { model.delete(ids, everyone) } }, onCancel = { deleting = emptyList() })
    }
    forwarding?.let { ids ->
        ForwardSheet(chats.forwardTargets, chats.myName, chats.myTone,
            onSend = { to -> forwarding = null; selection = null; scope.launch { model.forward(ids, to) } }, onDismiss = { forwarding = null })
    }
}

/** Select mode's bar: how many are selected, Forward and Delete for them, and a way out (as iOS's selection bar). */
@Composable
private fun SelectionBar(count: Int, onCancel: () -> Unit, onForward: () -> Unit, onDelete: () -> Unit) {
    val colors = Lime.colors
    Row(Modifier.fillMaxWidth().heightIn(min = 64.dp).padding(horizontal = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        IconButton(onClick = onCancel, Modifier.size(56.dp).testTag("select-cancel")) { Icon(Icons.Close, stringResource(R.string.message_select_cancel), tint = colors.text) }
        Text(stringResource(R.string.message_selected_count, count), color = colors.text, fontSize = 20.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f).semantics { heading() }.testTag("select-count"))
        TextButton(onClick = onForward, enabled = count > 0, modifier = Modifier.heightIn(min = 48.dp).testTag("select-forward")) { Text(stringResource(R.string.message_action_forward), color = colors.text, fontSize = 16.sp) }
        TextButton(onClick = onDelete, enabled = count > 0, modifier = Modifier.heightIn(min = 48.dp).testTag("select-delete")) { Text(stringResource(R.string.message_action_delete), color = colors.danger, fontSize = 16.sp) }
    }
}

@Composable
private fun Header(summary: ConversationSummary?, myName: String, myTone: Int, onBack: () -> Unit, onGroup: () -> Unit, onProfile: (uniffi.lime_core.MemberInfo) -> Unit) {
    val colors = Lime.colors
    val first = summary?.members?.firstOrNull()
    Row(Modifier.fillMaxWidth().heightIn(min = 64.dp).padding(horizontal = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        IconButton(onClick = onBack, Modifier.size(56.dp).testTag("chat-back")) {
            Icon(Icons.Back, contentDescription = stringResource(R.string.chat_back), tint = colors.text)
        }
        // In a one-to-one chat the avatar and the name open the person's profile.
        val opensProfile = summary != null && !summary.isGroup && first != null
        // In a group they open the group's details (not once it has ended: nothing there can change).
        val opensGroup = summary != null && summary.isGroup && !summary.isRequest && summary.groupEnded == null
        val groupLabel = stringResource(R.string.group_info_open)
        Row(
            Modifier.weight(1f).heightIn(min = 48.dp)
                .then(if (opensProfile) Modifier.semantics(mergeDescendants = true) { role = Role.Button }.clickable { onProfile(first!!) } else Modifier)
                .then(if (opensGroup) Modifier.semantics(mergeDescendants = true) { role = Role.Button; contentDescription = "${summary!!.title}, $groupLabel" }.clickable(onClick = onGroup) else Modifier)
                .testTag("chat-header"),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            if (summary != null) {
                if (!summary.isGroup && first != null) Avatar(first.initials.ifEmpty { initialsOf(first.name) }, first.tone.toInt(), 36.dp)
                else com.limemessenger.lime.ui.common.GroupAvatar(summary, myName, myTone, 36.dp)
            }
            Text(
                summary?.title.orEmpty(), color = colors.text, fontSize = 20.sp, fontWeight = FontWeight.SemiBold, maxLines = 1,
                modifier = Modifier.padding(start = 12.dp).weight(1f).semantics { heading() }.testTag("chat-title"),
            )
        }
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
    onRetry: () -> Unit, onReply: () -> Unit, onOpenThread: () -> Unit, model: ChatModel, onOpenPhoto: (Int) -> Unit,
    selecting: Boolean, selected: Boolean, onToggleSelect: () -> Unit, onOpenMenu: () -> Unit, onPerform: (uniffi.lime_core.MessageAction) -> Unit, onReact: (String) -> Unit,
    voice: com.limemessenger.lime.chats.VoicePlayer, voiceNext: (String) -> String?, voiceData: suspend (String) -> ByteArray?,
) {
    val colors = Lime.colors
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val own = item.isOwn
    val sender = summary?.members?.firstOrNull { it.id == item.senderId }
    val isGroup = summary?.isGroup == true
    val label = MessageSpeech.label(item, sender?.name, replyCount, plainText = ::messagePlainText)
    val plan = remember(item) { uniffi.lime_core.messageActions(item, false, System.currentTimeMillis()) }
    val plain = remember(item.text) { messagePlainText(item.text) }
    val copyLabel = stringResource(R.string.chat_copy)
    val replyLabel = stringResource(R.string.chat_reply)
    val retryLabel = stringResource(if (item.state == DeliveryState.Undelivered) R.string.chat_resend_action else R.string.chat_retry_action)
    val failed = own && (item.state == DeliveryState.Failed || item.state == DeliveryState.Undelivered)
    val photoLabel = stringResource(R.string.photo_open)
    val photos = item.attachments.filter { it.mime.startsWith("image/") }
    val maxBubble = (LocalConfiguration.current.screenWidthDp * 0.78f).dp
    val actions = buildList {
        // The same actions as the long-press menu, by name, for TalkBack and Switch Access (never a gesture-only menu).
        shownActions(plan).forEach { action ->
            val title = actionTitleText(action)
            when (action) {
                uniffi.lime_core.MessageAction.REACT -> add(CustomAccessibilityAction(title) { onOpenMenu(); true })
                uniffi.lime_core.MessageAction.COPY -> if (plain.isNotEmpty()) add(CustomAccessibilityAction(title) { copy(context, plain); true })
                uniffi.lime_core.MessageAction.REPLY -> add(CustomAccessibilityAction(title) { onReply(); true })
                else -> add(CustomAccessibilityAction(title) { onPerform(action); true })
            }
        }
        if (!item.deleted && photos.isNotEmpty()) add(CustomAccessibilityAction(photoLabel) { onOpenPhoto(0); true })
        // A voice message plays from its custom actions too (one TalkBack stop per message): play or pause, the speed, and skipping 10 seconds.
        item.attachments.firstOrNull { it.mime.startsWith("audio/") && !item.deleted }?.let { audio ->
            val playing = voice.isCurrent(audio.id) && voice.isPlaying
            add(CustomAccessibilityAction(if (playing) "Pause" else "Play") { scope.launch { voice.toggle(audio.id, voiceNext, voiceData) }; true })
            add(CustomAccessibilityAction("Change speed") { voice.cycleSpeed(); true })
            add(CustomAccessibilityAction("Skip forward 10 seconds") { voice.skip(10.0); true })
            add(CustomAccessibilityAction("Skip back 10 seconds") { voice.skip(-10.0); true })
        }
        if (failed) add(CustomAccessibilityAction(retryLabel) { onRetry(); true })
    }
    Row(
        Modifier.fillMaxWidth().padding(vertical = 2.dp),
        horizontalArrangement = if (own) Arrangement.End else Arrangement.Start,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (selecting) {
            val toggleWords = stringResource(R.string.message_select_toggle)
            Box(Modifier.size(48.dp).semantics { contentDescription = toggleWords; role = Role.Checkbox; this.selected = selected }.clickable(onClick = onToggleSelect).testTag("select-${item.id}"), contentAlignment = Alignment.Center) {
                Icon(if (selected) Icons.CheckedBox else Icons.UncheckedBox, null, tint = if (selected) colors.text else colors.textSecondary, modifier = Modifier.size(24.dp))
            }
        }
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
                            .combinedClickable(onClick = { if (selecting) onToggleSelect() }, onLongClick = { if (!selecting) onOpenMenu() }, onClickLabel = null)
                            .padding(horizontal = 14.dp, vertical = 10.dp),
                        verticalArrangement = Arrangement.spacedBy(4.dp),
                    ) {
                        if (item.deleted) {
                            Text(stringResource(R.string.chat_deleted), color = colors.textSecondary, fontSize = 16.sp, fontStyle = FontStyle.Italic)
                        } else {
                            photos.forEachIndexed { index, photo -> PhotoThumb(photo, model) { onOpenPhoto(index) } }
                            if (item.text.isNotEmpty()) MessageText(item.text, color = if (own) colors.ownInk else colors.text, linkColor = if (own) colors.linkOwn else colors.link, modifier = Modifier.testTag("message-text-${item.id}"))
                            item.attachments.filter { !it.mime.startsWith("image/") }.forEach { a ->
                                val ink = if (own) colors.ownInk else colors.text
                                if (a.mime.startsWith("audio/")) com.limemessenger.lime.ui.chat.VoiceCard(a, voice, voiceNext, voiceData, ink)
                                else com.limemessenger.lime.ui.chat.FileCard(a, model, ink)
                            }
                        }
                    }
                }
                if (!item.deleted && (endsRun || showState || item.edited)) Footer(item, showState, onRetry)
            }
            ReactionChips(item, onReact)
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
private fun RequestBar(title: String, onBlock: () -> Unit, onAccept: () -> Unit) {
    val colors = Lime.colors
    Column(Modifier.fillMaxWidth().background(colors.surface).padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(stringResource(R.string.chat_request_bar, title), color = colors.text, fontSize = 16.sp, modifier = Modifier.testTag("request-bar"))
        // Block is the quiet choice (a grey pill); Accept stays the one lime button.
        Box(
            Modifier.fillMaxWidth().heightIn(min = 52.dp).background(colors.chip, RoundedCornerShape(26.dp))
                .semantics { role = Role.Button }.clickable(onClick = onBlock).testTag("request-block"),
            contentAlignment = Alignment.Center,
        ) { Text(stringResource(R.string.block_confirm), color = colors.text, fontSize = 17.sp, fontWeight = FontWeight.SemiBold) }
        Box(
            Modifier.fillMaxWidth().heightIn(min = 52.dp).background(colors.accent, RoundedCornerShape(26.dp))
                .semantics { role = Role.Button }.clickable(onClick = onAccept).testTag("request-accept"),
            contentAlignment = Alignment.Center,
        ) { Text(stringResource(R.string.chat_accept), color = colors.accentInk, fontSize = 17.sp, fontWeight = FontWeight.SemiBold) }
    }
}

/** A photo chosen for the next message, with a picture to show and its description. */
private class DraftPhoto(var attachment: OutgoingAttachment, val preview: ImageBitmap)

/** The composer: plain text, photos from the system Photo Picker, a reply bar when replying, and send = the one lime action. */
@Composable
private fun Composer(model: ChatModel, seedPhotos: List<OutgoingAttachment>, panelOpen: Boolean, onGif: () -> Unit, onSend: (String, List<OutgoingAttachment>) -> Unit) {
    val colors = Lime.colors
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var text by rememberSaveable { mutableStateOf("") }
    val drafts = remember {
        mutableStateListOf<DraftPhoto>().also { list -> seedPhotos.forEach { a -> AttachmentProcessing.decodeForDisplay(a.bytes, 320)?.let { list.add(DraftPhoto(a, it.asImageBitmap())) } } }
    }
    var describing by remember { mutableStateOf<DraftPhoto?>(null) }
    var problem by remember { mutableStateOf<String?>(null) }
    val tooLarge = stringResource(R.string.photo_too_large)
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.PickMultipleVisualMedia(AttachmentProcessing.MAX_PER_MESSAGE)) { uris ->
        scope.launch {
            val made = withContext(Dispatchers.IO) {
                uris.take(AttachmentProcessing.MAX_PER_MESSAGE - drafts.size).mapNotNull { uri ->
                    AttachmentProcessing.photo(context.contentResolver, uri)?.let { att -> AttachmentProcessing.decodeForDisplay(att.bytes, 320)?.let { DraftPhoto(att, it.asImageBitmap()) } }
                }
            }
            problem = if (made.size < uris.size) tooLarge else null
            drafts.addAll(made)
        }
    }
    // Voice messages and files (LIME-308).
    val capture = LocalVoiceCapture.current
    val recorder = remember { VoiceRecorder(capture(context.applicationContext)) }
    val micDenied = stringResource(R.string.voice_mic_denied)
    val micUnavailable = stringResource(R.string.voice_mic_unavailable)
    val unreadable = stringResource(R.string.file_unreadable)
    val fileTitle = uniffi.lime_core.fileTooLargeWords()
    var micAllowedNow by remember { mutableStateOf(androidx.core.content.ContextCompat.checkSelfPermission(context, android.Manifest.permission.RECORD_AUDIO) == android.content.pm.PackageManager.PERMISSION_GRANTED) }
    val micPermission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted -> micAllowedNow = granted; if (!granted) problem = micDenied }
    val finishVoice: () -> Unit = { recorder.finish()?.let { note -> scope.launch { model.sendVoice(note) } } }
    LaunchedEffect(recorder.isRecording) {
        while (recorder.isRecording) {
            recorder.tick()
            if (recorder.elapsedMs >= recorder.limitMs) finishVoice()   // the longest a voice message can be
            delay(50)
        }
    }
    androidx.compose.runtime.DisposableEffect(Unit) { onDispose { recorder.cancel() } }
    val filePicker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) scope.launch {
            val picked = withContext(Dispatchers.IO) { readPickedFile(context, uri) }
            when (picked) {
                is PickedFile.TooLarge -> problem = fileTitle.joinToString(" ")
                is PickedFile.Unreadable -> problem = unreadable
                is PickedFile.Ok -> { problem = null; model.sendPhotos(listOf(picked.attachment), "", "file") }
            }
        }
    }
    val reply = model.replyingTo
    val keyboard = androidx.compose.ui.platform.LocalSoftwareKeyboardController.current
    val focus = androidx.compose.ui.platform.LocalFocusManager.current
    val focusRequester = remember { androidx.compose.ui.focus.FocusRequester() }
    @OptIn(androidx.compose.foundation.layout.ExperimentalLayoutApi::class)
    val keyboardUp = androidx.compose.foundation.layout.WindowInsets.isImeVisible
    var attaching by remember { mutableStateOf(false) }
    val canSend = text.isNotBlank() || drafts.isNotEmpty()
    val cardShape = RoundedCornerShape(26.dp)
    // The lime pattern (iOS `ChatComposer`): ONE rounded card, the text on top at the card's full width, one tool row under it. Adding a tool never changes the field's size.
    Column(Modifier.fillMaxWidth().padding(horizontal = 12.dp).padding(bottom = 4.dp).testTag("composer-bar")) {
        Column(
            Modifier.fillMaxWidth().shadow(6.dp, cardShape, clip = false, ambientColor = Color.Black.copy(alpha = 0.12f), spotColor = Color.Black.copy(alpha = 0.12f))
                .background(colors.surface, cardShape).border(1.dp, colors.hairline, cardShape).testTag("composer-card").padding(horizontal = 12.dp).padding(top = 2.dp, bottom = 4.dp),
        ) {
            if (reply != null) {
                val name = model.summary?.members?.firstOrNull { it.id == reply.senderId }?.name?.split(" ")?.firstOrNull() ?: "you"
                Row(Modifier.fillMaxWidth().padding(top = 8.dp).background(colors.chip, RoundedCornerShape(12.dp)).padding(start = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f).padding(vertical = 8.dp)) {
                        Text(stringResource(R.string.chat_replying_to, name), color = colors.text, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.testTag("reply-bar"))
                        Text(messagePlainText(reply.text).replace("\n", " ").ifEmpty { AttachmentFormat.summary(reply.attachments).orEmpty() }, color = colors.textSecondary, fontSize = 13.sp, maxLines = 1)
                    }
                    IconButton(onClick = { model.replyingTo = null }, Modifier.size(48.dp).testTag("reply-cancel")) {
                        Icon(Icons.Close, contentDescription = stringResource(R.string.chat_cancel_reply), tint = colors.text)
                    }
                }
            }
            if (drafts.isNotEmpty()) {
                LazyRow(Modifier.fillMaxWidth().testTag("draft-photos"), horizontalArrangement = Arrangement.spacedBy(8.dp), contentPadding = androidx.compose.foundation.layout.PaddingValues(vertical = 8.dp)) {
                    items(drafts.toList()) { draft ->
                        val photo = stringResource(R.string.photo_label)
                        val described = draft.attachment.alt.isNotEmpty()
                        Box(Modifier.size(88.dp).semantics { contentDescription = if (described) "$photo, ${draft.attachment.alt}" else photo }) {
                            Image(draft.preview, contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize().clip(RoundedCornerShape(12.dp)))
                            // Alt: describe it for people who cannot see it (a 48 dp target, as iOS's "+ Alt" chip).
                            Box(
                                Modifier.align(Alignment.BottomStart).heightIn(min = 48.dp).widthIn(min = 48.dp)
                                    .semantics { role = Role.Button; contentDescription = if (described) "Edit description" else "Add description" }
                                    .clickable { describing = draft }.testTag("draft-describe"),
                                contentAlignment = Alignment.BottomStart,
                            ) {
                                Text(
                                    if (described) stringResource(R.string.photo_alt_chip) else stringResource(R.string.photo_alt_chip_add), color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.Bold,
                                    modifier = Modifier.padding(4.dp).background(Color.Black.copy(alpha = 0.6f), RoundedCornerShape(8.dp)).padding(horizontal = 6.dp, vertical = 2.dp),
                                )
                            }
                            IconButton(onClick = { drafts.remove(draft) }, Modifier.align(Alignment.TopEnd).size(48.dp).testTag("draft-remove")) {
                                Icon(Icons.Close, contentDescription = stringResource(R.string.photo_remove), tint = Color.White, modifier = Modifier.background(Color.Black.copy(alpha = 0.6f), CircleShape).padding(4.dp))
                            }
                        }
                    }
                }
            }
            problem?.let { Text(it, color = colors.danger, fontSize = 14.sp, modifier = Modifier.padding(horizontal = 4.dp, vertical = 4.dp).testTag("photo-problem")) }
            // The words, or the recording bar in their place.
            if (recorder.isRecording) RecordingBar(recorder, onSend = finishVoice, onCancel = { recorder.cancel() }, modifier = Modifier.fillMaxWidth()) else {
                val hint = stringResource(R.string.chat_message_hint)
                androidx.compose.foundation.text.BasicTextField(
                    value = text, onValueChange = { text = it }, maxLines = 5, minLines = 1,
                    textStyle = androidx.compose.ui.text.TextStyle(color = colors.text, fontSize = 17.sp, lineHeight = 24.sp),
                    cursorBrush = androidx.compose.ui.graphics.SolidColor(colors.text),
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Default),
                    modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp).focusRequester(focusRequester).semantics { contentDescription = hint }.testTag("composer-field"),
                    decorationBox = { inner ->
                        Box(Modifier.fillMaxWidth().padding(horizontal = 4.dp, vertical = 12.dp)) {
                            if (text.isEmpty()) Text(hint, color = colors.textSecondary, fontSize = 17.sp, modifier = Modifier.clearAndSetSemantics {})
                            inner()
                        }
                    },
                )
            }
            // The tool row: + · face · keyboard on the left, then the one right control: send (lime) with words or a draft, else the microphone.
            if (recorder.phase != VoiceRecorder.Phase.Locked) Row(Modifier.fillMaxWidth().heightIn(min = 48.dp), verticalAlignment = Alignment.CenterVertically) {
                Row(Modifier.alpha(if (recorder.isRecording) 0f else 1f), horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                    val plusWords = stringResource(R.string.composer_plus)
                    ToolButton(plusWords, "composer-plus", enabled = !recorder.isRecording, onClick = { attaching = true; problem = null })
                    val emojiWords = stringResource(R.string.composer_emoji)
                    ToolButton(emojiWords, "attach-gif", selected = panelOpen, enabled = !recorder.isRecording, onClick = onGif) { Icon(Icons.Face, null, tint = colors.text) }
                    val keyboardWords = stringResource(if (keyboardUp) R.string.composer_hide_keyboard else R.string.composer_show_keyboard)
                    ToolButton(keyboardWords, "composer-hide-keyboard", enabled = !recorder.isRecording, onClick = {
                        if (keyboardUp) { keyboard?.hide(); focus.clearFocus() } else { focusRequester.requestFocus(); keyboard?.show() }
                    }) { Icon(if (keyboardUp) Icons.KeyboardHide else Icons.Keyboard, null, tint = colors.text) }
                }
                Spacer(Modifier.weight(1f))
                val sendLabel = stringResource(R.string.chat_send)
                if (canSend && !recorder.isRecording) {
                    Box(Modifier.size(48.dp).semantics { contentDescription = sendLabel; role = Role.Button }.clickable { onSend(text, drafts.map { it.attachment }); text = ""; drafts.clear() }.testTag("send-button"), contentAlignment = Alignment.Center) {
                        Box(Modifier.size(36.dp).background(colors.accent, CircleShape), contentAlignment = Alignment.Center) { Icon(Icons.Send, contentDescription = null, tint = colors.accentInk, modifier = Modifier.size(20.dp)) }
                    }
                } else {
                    MicButton(
                        onPress = {
                            if (!micAllowedNow) { micPermission.launch(android.Manifest.permission.RECORD_AUDIO); false }
                            else { val ok = recorder.start(); if (!ok) problem = micUnavailable; ok }
                        },
                        onRelease = { if (recorder.isRecording) finishVoice() }, onLock = { recorder.lock() }, onCancel = { recorder.cancel() },
                        onHandsFree = { if (!micAllowedNow) micPermission.launch(android.Manifest.permission.RECORD_AUDIO) else if (!recorder.start()) problem = micUnavailable else recorder.lock() },
                        modifier = Modifier.size(48.dp),
                    )
                }
            }
        }
    }
    // The attachment sheet (iOS `AddToMessageSheet`): Photo and File (there is no camera tool on Android yet).
    if (attaching) @OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class) androidx.compose.material3.ModalBottomSheet(onDismissRequest = { attaching = false }, containerColor = colors.canvas) {
        Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp).padding(bottom = 24.dp).testTag("attach-sheet")) {
            SheetRow(stringResource(R.string.photo_attach), Icons.Photo, "attach-photo") { attaching = false; picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) }
            SheetRow(stringResource(R.string.file_attach), Icons.Attach, "attach-file") { attaching = false; filePicker.launch(arrayOf("*/*")) }
        }
    }
    describing?.let { draft ->
        var alt by remember(draft) { mutableStateOf(draft.attachment.alt) }
        AlertDialog(
            onDismissRequest = { describing = null }, containerColor = colors.canvas,
            title = { Text(stringResource(R.string.photo_description_title), color = colors.text) },
            text = {
                OutlinedTextField(
                    value = alt, onValueChange = { alt = it.take(AttachmentProcessing.MAX_ALT_LENGTH) }, modifier = Modifier.fillMaxWidth().testTag("description-field"),
                    placeholder = { Text(stringResource(R.string.photo_description_hint), color = colors.textSecondary) }, maxLines = 4,
                )
            },
            confirmButton = {
                TextButton({
                    val at = drafts.indexOf(draft)
                    if (at >= 0) drafts[at] = DraftPhoto(draft.attachment.copy(alt = alt.trim()), draft.preview)
                    describing = null
                }, Modifier.heightIn(min = 48.dp).testTag("description-save")) { Text(stringResource(R.string.photo_description_save), color = colors.text, fontWeight = FontWeight.SemiBold) }
            },
            dismissButton = { TextButton({ describing = null }, Modifier.heightIn(min = 48.dp)) { Text(stringResource(R.string.photo_description_cancel), color = colors.text) } },
        )
    }
}

/** A photo in a bubble: the tiny preview first, then the real picture (downloaded and decrypted when this phone does not have it yet). */
@Composable
private fun PhotoThumb(photo: AttachmentInfo, model: ChatModel, onOpen: () -> Unit) {
    val colors = Lime.colors
    LaunchedEffect(photo.id) { model.loadImage(photo) }
    val bitmap = model.images[photo.id]
    val ratio = if ((photo.width ?: 0u) > 0u && (photo.height ?: 0u) > 0u) (photo.width!!.toFloat() / photo.height!!.toFloat()).coerceIn(0.6f, 1.8f) else 1f
    if (photo.mime == "image/gif") {
        // A GIF plays (unless the system's animations are off: then a still with a Play button) and is read by its sticker name or "GIF" (LIME-313).
        val bytes by androidx.compose.runtime.produceState<ByteArray?>(null, photo.id, bitmap) { value = model.localBytes(photo) }
        val context = androidx.compose.ui.platform.LocalContext.current
        val words = remember(photo.name) { uniffi.lime_core.stickerSpokenName(photo.name, com.limemessenger.lime.chats.StickerPack.entries(context)) }
        GifThumb(bytes, bitmap, ratio, if (words == "Sticker" && !photo.name.startsWith(uniffi.lime_core.stickerNamePrefix())) stringResource(R.string.gif_label) else words, "photo-${photo.id}", onOpen)
        return
    }
    Box(Modifier.width(240.dp).aspectRatio(ratio).clip(RoundedCornerShape(14.dp)).background(colors.chip).clickable(onClick = onOpen).testTag("photo-${photo.id}")) {
        if (bitmap != null) Image(bitmap, contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
    }
}

/** A photo full screen: pinch to zoom, drag to pan, swipe between photos; its description is what TalkBack reads. Back or Close leaves. */
@Composable
private fun PhotoViewer(photos: List<AttachmentInfo>, start: Int, model: ChatModel, onClose: () -> Unit) {
    if (photos.isEmpty()) return
    val pager = rememberPagerState(initialPage = start.coerceIn(0, photos.lastIndex)) { photos.size }
    val photoWord = stringResource(R.string.photo_label)
    Box(Modifier.fillMaxSize().background(Color.Black).testTag("photo-viewer")) {
        HorizontalPager(pager, Modifier.fillMaxSize()) { page ->
            val photo = photos[page]
            LaunchedEffect(photo.id) { model.loadImage(photo, userRequested = true) }
            var scale by remember { mutableStateOf(1f) }
            var offset by remember { mutableStateOf(androidx.compose.ui.geometry.Offset.Zero) }
            val bitmap = model.images[photo.id]
            Box(Modifier.fillMaxSize().pointerInput(Unit) { detectTransformGestures { _, pan, zoom, _ -> scale = (scale * zoom).coerceIn(1f, 5f); offset = if (scale == 1f) androidx.compose.ui.geometry.Offset.Zero else offset + pan } }, contentAlignment = Alignment.Center) {
                if (bitmap != null) Image(
                    bitmap, contentDescription = photo.alt.ifEmpty { photoWord }, contentScale = ContentScale.Fit,
                    modifier = Modifier.fillMaxSize().graphicsLayer { scaleX = scale; scaleY = scale; translationX = offset.x; translationY = offset.y },
                )
            }
        }
        IconButton(onClick = onClose, Modifier.align(Alignment.TopStart).systemBarsPadding().padding(8.dp).size(56.dp).testTag("photo-close")) {
            Icon(Icons.Close, contentDescription = stringResource(R.string.photo_viewer_close), tint = Color.White)
        }
        val alt = photos[pager.currentPage].alt
        if (alt.isNotEmpty()) Text(alt, color = Color.White, fontSize = 16.sp, modifier = Modifier.align(Alignment.BottomCenter).systemBarsPadding().background(Color.Black.copy(alpha = 0.6f)).padding(16.dp).fillMaxWidth())
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

/** A group that ended is read-only: "You left this group." or "This group was deleted.", with Remove from my list (as iOS's `endedBar`). */
@Composable
private fun EndedBar(left: Boolean, onRemove: () -> Unit) {
    val colors = Lime.colors
    Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp).background(colors.surface, RoundedCornerShape(22.dp)).padding(horizontal = 20.dp, vertical = 10.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Text(stringResource(if (left) R.string.group_ended_left else R.string.group_ended_deleted), color = colors.textSecondary, fontSize = 15.sp, modifier = Modifier.testTag("group-ended-note"))
        TextButton(onClick = onRemove, Modifier.heightIn(min = 48.dp).testTag("group-ended-remove")) { Text(stringResource(R.string.group_ended_remove), color = colors.danger, fontSize = 17.sp, fontWeight = FontWeight.SemiBold) }
    }
}

/** The words of an action for a custom accessibility action (the same words as the menu rows). */
@Composable
private fun actionTitleText(action: uniffi.lime_core.MessageAction): String = actionTitle(action)

/** A file picked from the system's file picker, checked against the limits. */
private sealed class PickedFile {
    data class Ok(val attachment: OutgoingAttachment) : PickedFile()
    object TooLarge : PickedFile()
    object Unreadable : PickedFile()
}

/** Reads a picked file (no storage permission: the picker hands over this one file): its size is checked against the core's limit before it is read. A picture is sent as a picture. */
private fun readPickedFile(context: Context, uri: android.net.Uri): PickedFile {
    val resolver = context.contentResolver
    var name = "File"; var size = -1L
    resolver.query(uri, arrayOf(android.provider.OpenableColumns.DISPLAY_NAME, android.provider.OpenableColumns.SIZE), null, null, null)?.use { c ->
        if (c.moveToFirst()) { c.getString(0)?.let { name = it }; if (!c.isNull(1)) size = c.getLong(1) }
    }
    if (size >= 0 && uniffi.lime_core.checkFileSize(size.toULong()) == uniffi.lime_core.FileCheck.TOO_LARGE) return PickedFile.TooLarge
    val mime = resolver.getType(uri) ?: "application/octet-stream"
    if (mime.startsWith("image/") && mime != "image/gif") AttachmentProcessing.photo(resolver, uri)?.let { return PickedFile.Ok(it.copy(name = name)) }
    val limit = uniffi.lime_core.attachmentLimits().maxFileBytes.toLong()
    val bytes = try { resolver.openInputStream(uri)?.use { readUpTo(it, (limit + 1).toInt()) } } catch (e: Exception) { null } ?: return PickedFile.Unreadable
    return when (uniffi.lime_core.checkFileSize(bytes.size.toULong())) {
        uniffi.lime_core.FileCheck.TOO_LARGE -> PickedFile.TooLarge
        uniffi.lime_core.FileCheck.EMPTY -> PickedFile.Unreadable
        else -> PickedFile.Ok(OutgoingAttachment(bytes, name, mime, null, null, null, ByteArray(0), ByteArray(0), ""))
    }
}

/** At most `limit` bytes of a stream (`readNBytes` needs API 33). */
private fun readUpTo(stream: java.io.InputStream, limit: Int): ByteArray {
    val out = java.io.ByteArrayOutputStream()
    val buffer = ByteArray(64 * 1024)
    var total = 0
    while (total < limit) {
        val n = stream.read(buffer, 0, minOf(buffer.size, limit - total))
        if (n < 0) break
        out.write(buffer, 0, n); total += n
    }
    return out.toByteArray()
}


/** A 48 dp tool of the composer's row: an icon with its words for TalkBack; `selected` puts a pill behind it (the face while its panel is open, as iOS). */
@Composable
private fun ToolButton(words: String, tag: String, selected: Boolean = false, enabled: Boolean = true, onClick: () -> Unit, icon: @Composable () -> Unit = { Icon(Icons.Plus, null, tint = Lime.colors.text) }) {
    Box(
        Modifier.size(width = 48.dp, height = 48.dp).then(if (selected) Modifier.padding(vertical = 4.dp).background(Lime.colors.pressed, CircleShape) else Modifier)
            .semantics { contentDescription = words; role = Role.Button; this.selected = selected }.clickable(enabled = enabled, onClick = onClick).testTag(tag),
        contentAlignment = Alignment.Center,
    ) { icon() }
}

@Composable
private fun SheetRow(title: String, icon: androidx.compose.ui.graphics.vector.ImageVector, tag: String, onClick: () -> Unit) {
    val colors = Lime.colors
    Row(Modifier.fillMaxWidth().heightIn(min = 56.dp).semantics(mergeDescendants = true) { role = Role.Button }.clickable(onClick = onClick).testTag(tag), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(16.dp)) {
        Icon(icon, null, tint = colors.text)
        Text(title, color = colors.text, fontSize = 17.sp)
    }
}
