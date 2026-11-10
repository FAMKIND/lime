package com.limemessenger.lime.ui.chats

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
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
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.limemessenger.lime.R
import com.limemessenger.lime.chats.ChatsModel
import com.limemessenger.lime.chats.MessageFormat
import com.limemessenger.lime.ui.common.Avatar
import com.limemessenger.lime.ui.common.GroupAvatar
import com.limemessenger.lime.ui.common.initialsOf
import com.limemessenger.lime.ui.shell.Icons
import com.limemessenger.lime.ui.theme.Lime
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import uniffi.lime_core.ConversationMatch
import uniffi.lime_core.SearchHit

// Search from Messages (iOS MessageSearchScreen): one field, then Chats (a name or title matches) and Messages (the words in them). It runs on this phone
// over the core's search (`search_conversations`, `search_messages`); nothing typed is sent anywhere. People (the exact lookup) is New message; jam search comes later.

private const val START_MARK = ''
private const val END_MARK = ''

/** The snippet as styled text: the marks removed, the matched words bold. */
fun markedSnippet(marked: String): AnnotatedString = buildAnnotatedString {
    var bold = false
    var run = StringBuilder()
    fun flush() {
        if (run.isEmpty()) return
        if (bold) withStyle(SpanStyle(fontWeight = FontWeight.Bold)) { append(run.toString()) } else append(run.toString())
        run = StringBuilder()
    }
    for (c in marked) when (c) {
        START_MARK -> { flush(); bold = true }
        END_MARK -> { flush(); bold = false }
        else -> run.append(c)
    }
    flush()
}

/** The snippet with the marks removed (what TalkBack reads). */
fun plainSnippet(marked: String): String = marked.filter { it != START_MARK && it != END_MARK }

private class Results(val chats: List<ConversationMatch>, val messages: List<SearchHit>, val query: String)

/** Search: the field, then the results. Tapping a chat opens it; tapping a message opens its chat at that message. */
@Composable
fun SearchScreen(chats: ChatsModel, onBack: () -> Unit, onOpenChat: (String) -> Unit, onOpenMessage: (conversationId: String, messageId: String) -> Unit) {
    val colors = Lime.colors
    var query by rememberSaveable { mutableStateOf("") }
    var results by remember { mutableStateOf<Results?>(null) }
    val focus = remember { FocusRequester() }
    LaunchedEffect(Unit) { runCatching { focus.requestFocus() } }
    LaunchedEffect(query) {
        val typed = query.trim()
        if (typed.isEmpty()) { results = null; return@LaunchedEffect }
        delay(150)
        val core = chats.core() ?: return@LaunchedEffect
        val found = withContext(Dispatchers.IO) {
            runCatching { Results(core.searchConversations(typed), core.searchMessages(typed, null, 50u), typed) }.getOrNull()
        }
        results = found
    }
    fun titleOf(id: String) = chats.conversations.firstOrNull { it.id == id }?.title.orEmpty()

    Column(Modifier.fillMaxSize().background(colors.canvas).systemBarsPadding().imePadding()) {
        Row(Modifier.fillMaxWidth().heightIn(min = 64.dp).padding(horizontal = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = onBack, Modifier.size(56.dp).testTag("search-back")) { Icon(Icons.Back, stringResource(R.string.chat_back), tint = colors.text) }
            OutlinedTextField(
                value = query, onValueChange = { query = it }, singleLine = true, shape = RoundedCornerShape(26.dp),
                placeholder = { Text(stringResource(R.string.search_placeholder), color = colors.textSecondary) },
                colors = OutlinedTextFieldDefaults.colors(
                    focusedTextColor = colors.text, unfocusedTextColor = colors.text, focusedContainerColor = colors.surface, unfocusedContainerColor = colors.surface,
                    focusedBorderColor = colors.text, unfocusedBorderColor = colors.hairline, cursorColor = colors.text,
                ),
                modifier = Modifier.weight(1f).heightIn(min = 56.dp).padding(end = 12.dp).focusRequester(focus).testTag("search-field"),
            )
        }
        val shown = results
        if (query.isBlank()) {
            Column(Modifier.fillMaxWidth().padding(32.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(stringResource(R.string.search_hint), color = colors.text, fontSize = 17.sp, modifier = Modifier.testTag("search-hint"))
                Text(stringResource(R.string.search_private), color = colors.textSecondary, fontSize = 15.sp)
            }
        } else if (shown != null && shown.query == query.trim() && shown.chats.isEmpty() && shown.messages.isEmpty()) {
            Text(stringResource(R.string.search_none, query.trim()), color = colors.textSecondary, fontSize = 17.sp, modifier = Modifier.padding(32.dp).testTag("search-none"))
        } else if (shown != null) {
            LazyColumn(Modifier.fillMaxSize().testTag("search-results")) {
                if (shown.chats.isNotEmpty()) {
                    item(key = "h-chats") { Text(stringResource(R.string.search_chats), color = colors.textSecondary, fontSize = 14.sp, fontWeight = FontWeight.Bold, modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp).semantics { heading() }) }
                    items(shown.chats, key = { "c-" + it.conversationId }) { match ->
                        val chat = chats.conversations.firstOrNull { it.id == match.conversationId }
                        Row(
                            Modifier.fillMaxWidth().heightIn(min = 64.dp).semantics(mergeDescendants = true) { role = Role.Button }.clickable { onOpenChat(match.conversationId) }.padding(horizontal = 16.dp, vertical = 8.dp).testTag("search-chat-${match.conversationId}"),
                            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
                        ) {
                            if (chat != null) {
                                val first = chat.members.firstOrNull()
                                if (!chat.isGroup && first != null) Avatar(first.initials.ifEmpty { initialsOf(first.name) }, first.tone.toInt(), 44.dp) else GroupAvatar(chat, chats.myName, chats.myTone, 44.dp)
                            }
                            Text(match.title, color = colors.text, fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
                        }
                    }
                }
                if (shown.messages.isNotEmpty()) {
                    item(key = "h-messages") { Text(stringResource(R.string.search_messages), color = colors.textSecondary, fontSize = 14.sp, fontWeight = FontWeight.Bold, modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp).semantics { heading() }) }
                    items(shown.messages, key = { "m-" + it.messageId }) { hit ->
                        val title = titleOf(hit.conversationId)
                        val words = "$title, ${if (hit.fromMe) stringResource(R.string.search_you) + ", " else ""}${plainSnippet(hit.snippet)}, ${MessageFormat.listTime(hit.time)}"
                        Column(
                            Modifier.fillMaxWidth().heightIn(min = 64.dp)
                                .semantics(mergeDescendants = true) { role = Role.Button; contentDescription = words }
                                .clickable { onOpenMessage(hit.conversationId, hit.threadRoot ?: hit.messageId) }.padding(horizontal = 20.dp, vertical = 10.dp).testTag("search-message-${hit.messageId}"),
                            verticalArrangement = Arrangement.spacedBy(2.dp),
                        ) {
                            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                                Text(title, color = colors.text, fontSize = 16.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                                Text(MessageFormat.listTime(hit.time), color = colors.textSecondary, fontSize = 14.sp)
                            }
                            Text(markedSnippet(hit.snippet), color = colors.textSecondary, fontSize = 15.sp, maxLines = 2, overflow = TextOverflow.Ellipsis)
                        }
                    }
                }
            }
        }
    }
}
