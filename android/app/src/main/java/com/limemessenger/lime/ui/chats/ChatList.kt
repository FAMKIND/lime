package com.limemessenger.lime.ui.chats

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.limemessenger.lime.R
import com.limemessenger.lime.chats.AttachmentFormat
import com.limemessenger.lime.chats.ChatsModel
import com.limemessenger.lime.chats.ListPreview
import com.limemessenger.lime.chats.MessageFormat
import com.limemessenger.lime.chats.OfflineCopy
import com.limemessenger.lime.chats.badgeText
import com.limemessenger.lime.chats.isUnread
import com.limemessenger.lime.chats.unreadCount
import com.limemessenger.lime.auth.ConnectionProblem
import com.limemessenger.lime.ui.common.Avatar
import com.limemessenger.lime.ui.common.initialsOf
import com.limemessenger.lime.ui.shell.Icons
import com.limemessenger.lime.ui.theme.Lime
import kotlinx.coroutines.launch
import uniffi.lime_core.ConversationSummary
import uniffi.lime_core.messagePlainText

/** The link tab: the Messages list (iOS's `MessagesView`): All | Unread, a banner when something is wrong, the rows, pull to refresh. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ChatListScreen(
    model: ChatsModel,
    myName: String,
    onOpen: (ConversationSummary) -> Unit,
    myTone: Int = 5,
    modifier: Modifier = Modifier,
    onProfile: () -> Unit = {},
    onRequests: () -> Unit = {},
    onNewMessage: () -> Unit = {},
    isMuted: (String) -> Boolean = { false },
) {
    val colors = Lime.colors
    val scope = rememberCoroutineScope()
    var refreshing by remember { mutableStateOf(false) }
    var note by remember { mutableStateOf(false) }
    Box(modifier.fillMaxSize().background(colors.canvas)) {
    Column(Modifier.fillMaxSize()) {
        Header(myName, myTone, onProfile)
        FilterRow(model)
        PullToRefreshBox(
            isRefreshing = refreshing,
            onRefresh = { scope.launch { refreshing = true; try { model.pullToRefresh() } finally { refreshing = false } } },
            modifier = Modifier.weight(1f),
        ) {
            LazyColumn(Modifier.fillMaxSize().testTag("messages-list")) {
                model.problem?.let { problem -> item(key = "problem") { ProblemBanner(problem) } }
                if (model.requests.isNotEmpty()) item(key = "requests") { RequestsRow(model.requests.size, onRequests) }
                if (model.isLoaded && model.chats.isEmpty() && model.requests.isEmpty()) {
                    item(key = "empty") { EmptyChats(note, onNewMessage) { note = true } }
                } else if (model.chats.isNotEmpty() && model.shownChats.isEmpty()) {
                    item(key = "filtered") { FilteredEmpty { model.unreadOnly = false } }
                }
                items(model.shownChats, key = { it.id }) { conversation ->
                    ConversationRow(conversation, isMuted(conversation.id)) { onOpen(conversation) }
                }
            }
        }
    }
    // The one lime action on the list: a new message (iOS's floating plus).
    val newLabel = stringResource(R.string.chats_card_new)
    Box(
        Modifier.align(Alignment.BottomEnd).padding(16.dp).size(56.dp).background(colors.accent, CircleShape)
            .semantics { role = Role.Button; contentDescription = newLabel }.clickable(onClick = onNewMessage).testTag("new-message-button"),
        contentAlignment = Alignment.Center,
    ) { Icon(Icons.Compose, null, tint = colors.accentInk) }
    }
}

@Composable
private fun Header(myName: String, myTone: Int, onProfile: () -> Unit) {
    val colors = Lime.colors
    Row(Modifier.fillMaxWidth().heightIn(min = 64.dp).padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(stringResource(R.string.app_name), color = colors.text, fontSize = 28.sp, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
        val profile = stringResource(R.string.my_profile)
        Box(
            Modifier.size(48.dp).clickable(onClick = onProfile).semantics { contentDescription = "$profile, $myName"; role = Role.Button }.testTag("my-avatar"),
            contentAlignment = Alignment.Center,
        ) { Avatar(initialsOf(myName), tone = myTone, size = 36.dp) }
    }
}

@Composable
private fun FilterRow(model: ChatsModel) {
    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 4.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Chip(stringResource(R.string.chats_all), !model.unreadOnly, "chat-filter-all") { model.unreadOnly = false }
        Chip(stringResource(R.string.chats_unread), model.unreadOnly, "chat-filter-unread") { model.unreadOnly = true }
    }
}

/** A segment: the selected one is filled (ink on a warm neutral; the lime accent is only for the primary action); it says "selected" to TalkBack. */
@Composable
private fun Chip(label: String, selected: Boolean, tag: String, onClick: () -> Unit) {
    val colors = Lime.colors
    Box(
        Modifier.heightIn(min = 48.dp).widthIn(min = 64.dp)
            .semantics(mergeDescendants = true) { this.selected = selected; role = Role.RadioButton }
            .clickable(onClick = onClick).testTag(tag),
        contentAlignment = Alignment.Center,
    ) {
        Box(Modifier.background(if (selected) colors.pressed else colors.surface, RoundedCornerShape(18.dp)).padding(horizontal = 16.dp, vertical = 8.dp)) {
            Text(label, color = colors.text, fontSize = 15.sp, fontWeight = if (selected) FontWeight.Bold else FontWeight.Normal)
        }
    }
}

@Composable
private fun ProblemBanner(problem: ConnectionProblem) {
    val words = if (problem == ConnectionProblem.Offline) OfflineCopy.banner(meshOn = false) else problem.message
    Text(
        words, color = Lime.colors.text, fontSize = 15.sp,
        modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 4.dp).background(Lime.colors.surface, RoundedCornerShape(14.dp))
            .padding(14.dp).heightIn(min = 44.dp).testTag("problem-message"),
    )
}

/** "Requests": strangers' first messages wait here until you accept (iOS `RequestsRow`). */
@Composable
private fun RequestsRow(count: Int, onClick: () -> Unit) {
    val colors = Lime.colors
    val words = if (count == 1) stringResource(R.string.requests_one) else stringResource(R.string.requests_many, count)
    val title = stringResource(R.string.requests_title)
    Row(
        Modifier.fillMaxWidth().heightIn(min = 72.dp).semantics(mergeDescendants = true) { role = Role.Button; contentDescription = "$title, $words" }
            .clickable(onClick = onClick).padding(horizontal = 16.dp, vertical = 12.dp).testTag("requests-row"),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Box(Modifier.size(52.dp).background(colors.accent, CircleShape), contentAlignment = Alignment.Center) { Icon(Icons.Mail, null, tint = colors.accentInk) }
        Column(Modifier.weight(1f)) {
            Text(title, color = colors.text, fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
            Text(words, color = colors.textSecondary, fontSize = 15.sp)
        }
        CountBadge(count)
    }
}

/** The Requests list (iOS `RequestsView`): open one to read it, then Accept. */
@Composable
fun RequestsScreen(model: ChatsModel, onOpen: (ConversationSummary) -> Unit, onBack: () -> Unit) {
    val colors = Lime.colors
    androidx.compose.foundation.layout.Column(Modifier.fillMaxSize().background(colors.canvas).androidx_systemBars()) {
        Row(Modifier.fillMaxWidth().heightIn(min = 64.dp), verticalAlignment = Alignment.CenterVertically) {
            androidx.compose.material3.IconButton(onClick = onBack, Modifier.size(56.dp).testTag("requests-back")) { Icon(Icons.Back, stringResource(R.string.chat_back), tint = colors.text) }
            Text(stringResource(R.string.requests_title), color = colors.text, fontSize = 20.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.semantics { heading() })
        }
        LazyColumn(Modifier.testTag("requests-list")) {
            item { Text(stringResource(R.string.requests_explainer), color = colors.textSecondary, fontSize = 15.sp, modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp)) }
            items(model.requests, key = { it.id }) { c -> ConversationRow(c, false) { onOpen(c) } }
        }
    }
}

private fun Modifier.androidx_systemBars(): Modifier = this.then(Modifier.systemBarsPadding())

@Composable
private fun EmptyChats(showNote: Boolean, onNewMessage: () -> Unit, onCard: () -> Unit) {
    val colors = Lime.colors
    Column(Modifier.fillMaxWidth().padding(top = 48.dp, start = 12.dp, end = 12.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(20.dp)) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(stringResource(R.string.chats_empty_title), color = colors.text, fontSize = 24.sp, fontWeight = FontWeight.Bold, modifier = Modifier.testTag("empty-title"))
            Text(stringResource(R.string.chats_empty_subtitle), color = colors.textSecondary, fontSize = 16.sp)
        }
        Card(Icons.Search, stringResource(R.string.chats_card_find), stringResource(R.string.chats_card_find_detail), "card-find", onNewMessage)
        Card(Icons.Compose, stringResource(R.string.chats_card_new), stringResource(R.string.chats_card_new_detail), "card-new-message", onNewMessage)
        Card(Icons.PersonAdd, stringResource(R.string.chats_card_invite), stringResource(R.string.chats_card_invite_detail), "card-invite", onCard)
        if (showNote) Text(stringResource(R.string.coming_soon_android), color = colors.textSecondary, fontSize = 15.sp, modifier = Modifier.testTag("coming-soon-note"))
    }
}

@Composable
private fun Card(icon: ImageVector, title: String, detail: String, tag: String, onClick: () -> Unit) {
    val colors = Lime.colors
    Row(
        Modifier.fillMaxWidth().heightIn(min = 72.dp).background(colors.surface, RoundedCornerShape(16.dp))
            .semantics(mergeDescendants = true) { role = Role.Button }.clickable(onClick = onClick).padding(14.dp).testTag(tag),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Box(Modifier.size(48.dp).background(colors.accent, CircleShape), contentAlignment = Alignment.Center) { Icon(icon, null, tint = colors.accentInk) }
        Column {
            Text(title, color = colors.text, fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
            Text(detail, color = colors.textSecondary, fontSize = 15.sp)
        }
    }
}

@Composable
private fun FilteredEmpty(onClear: () -> Unit) {
    val colors = Lime.colors
    Column(Modifier.fillMaxWidth().padding(top = 48.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(stringResource(R.string.chats_no_unread), color = colors.textSecondary, fontSize = 17.sp, modifier = Modifier.testTag("filtered-empty"))
        Box(Modifier.heightIn(min = 48.dp).clickable(onClick = onClear).padding(12.dp), contentAlignment = Alignment.Center) {
            Text(stringResource(R.string.chats_clear_filter), color = colors.text, fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
        }
    }
}

/** One conversation: avatar, name (bold when unread), pinned/muted marks, time, the preview (two lines), the unread count. One TalkBack stop. */
@Composable
fun ConversationRow(conversation: ConversationSummary, muted: Boolean, onClick: () -> Unit) {
    val colors = Lime.colors
    val preview = ListPreview.make(conversation, plainText = ::messagePlainText)
    val time = MessageFormat.listTime(if (conversation.activityAt > 0) conversation.activityAt else conversation.lastMessage?.sentAt)
    val unread = conversation.isUnread
    val label = if (conversation.isGroup) null else conversation.members.firstOrNull()?.label
    val first = conversation.members.firstOrNull()
    val pinned = stringResource(R.string.chat_row_pinned)
    val mutedWord = stringResource(R.string.chat_row_muted)
    val unreadWords = if (unread) stringResource(R.string.chat_row_unread, conversation.unreadCount) else null
    val description = buildString {
        append(conversation.title)
        label?.let { append(" ($it)") }
        if (conversation.isPinned) append(", $pinned")
        if (muted) append(", $mutedWord")
        append(", ").append(preview.plain.replace("\n", ", ").ifEmpty { "" })
        if (time.isNotEmpty()) append(", $time")
        unreadWords?.let { append(", $it") }
    }
    Row(
        Modifier.fillMaxWidth().heightIn(min = 72.dp)
            .semantics(mergeDescendants = false) { contentDescription = description; role = Role.Button }
            .clickable(onClick = onClick).padding(horizontal = 16.dp, vertical = 15.dp).testTag("conversation-row-${conversation.id}"),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        if (!conversation.isGroup && first != null) Avatar(first.initials.ifEmpty { initialsOf(first.name) }, first.tone.toInt(), 52.dp)
        else Avatar(initialsOf(conversation.title), 0, 52.dp, emoji = conversation.groupEmoji)
        Column(Modifier.weight(1f).clearAndSetSemantics { }, verticalArrangement = Arrangement.spacedBy(3.dp)) {
            // At the large text sizes the time goes under the name instead of squeezing it (as iOS does at the accessibility sizes).
            val large = androidx.compose.ui.platform.LocalDensity.current.fontScale >= 1.5f
            val title: @Composable (Modifier) -> Unit = { m ->
                Text(
                    conversation.title, color = colors.text, fontSize = 17.sp, fontWeight = if (unread) FontWeight.Bold else FontWeight.SemiBold,
                    maxLines = if (large) 3 else 1, overflow = TextOverflow.Ellipsis, modifier = m.testTag("row-title-${conversation.id}"),
                )
            }
            val marks: @Composable () -> Unit = {
                label?.let { Text(it, color = colors.textSecondary, fontSize = 12.sp, modifier = Modifier.background(colors.surface, RoundedCornerShape(8.dp)).padding(horizontal = 6.dp, vertical = 2.dp)) }
                if (muted) Icon(Icons.Muted, null, tint = colors.textSecondary, modifier = Modifier.size(14.dp).testTag("muted-${conversation.id}"))
                if (conversation.isPinned) Icon(Icons.Pinned, null, tint = colors.textSecondary, modifier = Modifier.size(14.dp).testTag("pinned-${conversation.id}"))
            }
            val timeText: @Composable () -> Unit = { Text(time, color = colors.textSecondary, fontSize = 14.sp, maxLines = 1, modifier = Modifier.testTag("row-time-${conversation.id}")) }
            if (large) {
                Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    title(Modifier)
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) { marks(); timeText() }
                }
            } else {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    title(Modifier.weight(1f, fill = false))
                    marks()
                    Spacer(Modifier.weight(1f))
                    timeText()
                }
            }
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Column(Modifier.weight(1f)) {
                    preview.quote?.let { Text(it, color = colors.textSecondary, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis) }
                    Text(
                        preview.body.ifEmpty { stringResource(R.string.chat_row_no_messages) },
                        color = if (unread) colors.text else colors.textSecondary, fontSize = 15.sp,
                        fontWeight = if (unread) FontWeight.SemiBold else FontWeight.Normal,
                        maxLines = if (preview.quote != null) 1 else 2, overflow = TextOverflow.Ellipsis, modifier = Modifier.testTag("row-preview-${conversation.id}"),
                    )
                }
                if (unread) CountBadge(conversation.unreadCount, Modifier.testTag("count-badge-${conversation.id}"))
            }
        }
    }
}

/** The unread count: ink on the lime accent (the one lime thing on a row), "99+" past 99. */
@Composable
fun CountBadge(count: Int, modifier: Modifier = Modifier) {
    val colors = Lime.colors
    val text = badgeText(count)
    Box(
        modifier.heightIn(min = 22.dp).widthIn(min = 22.dp).background(colors.accent, CircleShape).padding(horizontal = if (text.length == 1) 0.dp else 7.dp),
        contentAlignment = Alignment.Center,
    ) { Text(text, color = colors.accentInk, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, maxLines = 1) }
}
