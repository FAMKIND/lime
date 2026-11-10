package com.limemessenger.lime.ui.chats

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
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
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.limemessenger.lime.R
import com.limemessenger.lime.chats.ChatsModel
import com.limemessenger.lime.chats.KnownTeacher
import com.limemessenger.lime.chats.KnownTeachers
import com.limemessenger.lime.chats.TeacherLookup
import com.limemessenger.lime.chats.find
import com.limemessenger.lime.chats.startChat
import com.limemessenger.lime.ui.common.Avatar
import com.limemessenger.lime.ui.common.initialsOf
import com.limemessenger.lime.ui.onboarding.PrimaryButton
import com.limemessenger.lime.ui.shell.Icons
import com.limemessenger.lime.ui.theme.Lime
import com.limemessenger.lime.chats.AvatarTone
import kotlinx.coroutines.launch
import uniffi.lime_core.FoundUser

/**
 * New message (iOS `NewMessageSheet`): the teachers I already message, A to Z, with a search field. Typing filters them; Next looks up ONE exact
 * username or email on the server (nothing partial is ever listed, and a teacher who chose not to be found is not found). Tapping a result opens
 * the chat, which is mine, so it is accepted and appears in Messages.
 */
@Composable
fun NewMessageScreen(
    model: ChatsModel, onClose: () -> Unit, onOpenChat: (String) -> Unit,
    find: suspend (String) -> FoundUser? = { model.find(it) },
    startChat: suspend (String, String) -> String? = { id, name -> model.startChat(id, name) },
    onNewGroup: (() -> Unit)? = null,
) {
    val colors = Lime.colors
    val scope = rememberCoroutineScope()
    var query by rememberSaveable { mutableStateOf("") }
    val lookup = remember { TeacherLookup() }
    val focus = remember { FocusRequester() }
    LaunchedEffect(Unit) { runCatching { focus.requestFocus() } }
    val canNext = TeacherLookup.accepts(query) && lookup.state !is TeacherLookup.State.Searching
    fun next() { if (canNext) scope.launch { lookup.run(query) { find(it) } } }
    val sections = KnownTeachers.sections(KnownTeachers.from(model.conversations), query)

    Column(Modifier.fillMaxSize().background(colors.canvas).systemBarsPadding().imePadding()) {
        Row(Modifier.fillMaxWidth().heightIn(min = 64.dp).padding(horizontal = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = onClose, Modifier.size(56.dp).testTag("new-message-close")) { Icon(Icons.Close, stringResource(R.string.new_message_close), tint = colors.text) }
            Text(stringResource(R.string.new_message_title), color = colors.text, fontSize = 20.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f).semantics { heading() })
        }
        Text(stringResource(R.string.new_message_hint), color = colors.textSecondary, fontSize = 15.sp, modifier = Modifier.padding(horizontal = 20.dp, vertical = 4.dp))
        OutlinedTextField(
            value = query, onValueChange = { query = it; if (lookup.state !is TeacherLookup.State.Searching) lookup.reset() }, singleLine = true,
            placeholder = { Text(stringResource(R.string.new_message_field), color = colors.textSecondary) },
            keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(keyboardType = KeyboardType.Email, imeAction = ImeAction.Search, autoCorrectEnabled = false),
            keyboardActions = androidx.compose.foundation.text.KeyboardActions(onSearch = { next() }), shape = RoundedCornerShape(14.dp),
            colors = OutlinedTextFieldDefaults.colors(
                focusedTextColor = colors.text, unfocusedTextColor = colors.text, focusedContainerColor = colors.surface, unfocusedContainerColor = colors.surface,
                focusedBorderColor = colors.text, unfocusedBorderColor = colors.hairline, cursorColor = colors.text,
            ),
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp).heightIn(min = 56.dp).focusRequester(focus).testTag("new-message-field"),
        )
        Box(Modifier.padding(horizontal = 16.dp, vertical = 8.dp)) {
            PrimaryButton(stringResource(R.string.new_message_next), { next() }, Modifier.testTag("new-message-next"), enabled = canNext, busy = lookup.state is TeacherLookup.State.Searching)
        }
        // The lookup's words are announced when they appear (the lookup comes with no focus move).
        Box(Modifier.semantics { liveRegion = LiveRegionMode.Polite }) {
            when (val state = lookup.state) {
                TeacherLookup.State.Idle -> {}
                TeacherLookup.State.Searching -> Text(stringResource(R.string.lookup_searching), color = colors.textSecondary, fontSize = 15.sp, modifier = Modifier.padding(horizontal = 20.dp, vertical = 12.dp).testTag("lookup-searching"))
                is TeacherLookup.State.Found -> FoundRow(state.person) { person -> scope.launch { startChat(person.userId, person.displayName)?.let(onOpenChat) } }
                TeacherLookup.State.Nobody -> Text(stringResource(R.string.lookup_none), color = colors.textSecondary, fontSize = 17.sp, modifier = Modifier.padding(horizontal = 20.dp, vertical = 14.dp).testTag("lookup-none"))
                is TeacherLookup.State.Problem -> Text(state.text, color = colors.danger, fontSize = 17.sp, modifier = Modifier.padding(horizontal = 20.dp, vertical = 14.dp).testTag("lookup-problem"))
            }
        }
        LazyColumn(Modifier.weight(1f).testTag("known-teachers")) {
            if (onNewGroup != null) item(key = "new-group") {
                Row(
                    Modifier.fillMaxWidth().heightIn(min = 64.dp).semantics(mergeDescendants = true) { role = Role.Button }.clickable(onClick = onNewGroup).padding(horizontal = 16.dp, vertical = 8.dp).testTag("new-group"),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp),
                ) {
                    Box(Modifier.size(44.dp).background(colors.surface, androidx.compose.foundation.shape.CircleShape), contentAlignment = Alignment.Center) { Icon(Icons.People, null, tint = colors.text) }
                    Text(stringResource(R.string.group_new), color = colors.text, fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
                }
            }
            sections.forEach { (letter, teachers) ->
                item(key = "h-$letter") { Text(letter, color = colors.textSecondary, fontSize = 14.sp, fontWeight = FontWeight.Bold, modifier = Modifier.padding(horizontal = 20.dp, vertical = 6.dp).semantics { heading() }) }
                items(teachers, key = { it.id }) { teacher -> KnownRow(teacher) { scope.launch { startChat(teacher.id, teacher.name)?.let(onOpenChat) } } }
            }
        }
    }
}

@Composable
private fun KnownRow(teacher: KnownTeacher, onClick: () -> Unit) {
    val colors = Lime.colors
    Row(
        Modifier.fillMaxWidth().heightIn(min = 64.dp).semantics(mergeDescendants = true) { role = Role.Button }.clickable(onClick = onClick).padding(horizontal = 16.dp, vertical = 8.dp).testTag("known-${teacher.id}"),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Avatar(teacher.initials.ifEmpty { initialsOf(teacher.name) }, teacher.tone, 44.dp)
        Text(teacher.name, color = colors.text, fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
    }
}

/** A found teacher as one row: tap it to message them. */
@Composable
private fun FoundRow(person: FoundUser, onStart: (FoundUser) -> Unit) {
    val colors = Lime.colors
    if (person.isSelf) {
        Text(stringResource(R.string.lookup_self), color = colors.textSecondary, fontSize = 17.sp, modifier = Modifier.padding(horizontal = 20.dp, vertical = 14.dp).testTag("lookup-self"))
        return
    }
    val detail = listOfNotNull(person.username?.let { "@$it" }, person.school).joinToString(" · ")
    val about = listOfNotNull(person.aboutEmoji, person.aboutText).filter { it.isNotEmpty() }.joinToString(" ")
    Row(
        Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp).background(colors.surface, RoundedCornerShape(20.dp))
            .semantics(mergeDescendants = true) { role = Role.Button }.clickable { onStart(person) }.padding(horizontal = 16.dp, vertical = 12.dp).testTag("lookup-result"),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Avatar(initialsOf(person.displayName), AvatarTone.tone(person.userId), 48.dp)
        Column {
            Text(person.displayName, color = colors.text, fontSize = 17.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.testTag("lookup-name"))
            if (detail.isNotEmpty()) Text(detail, color = colors.textSecondary, fontSize = 15.sp)
            if (about.isNotEmpty()) Text(about, color = colors.textSecondary, fontSize = 15.sp, maxLines = 2)
        }
    }
}
