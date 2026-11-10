package com.limemessenger.lime.ui.chats

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
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
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.limemessenger.lime.R
import com.limemessenger.lime.chats.ChatsModel
import com.limemessenger.lime.chats.GROUP_NAME_LIMIT
import com.limemessenger.lime.chats.GroupModel
import com.limemessenger.lime.chats.KnownTeacher
import com.limemessenger.lime.chats.KnownTeachers
import com.limemessenger.lime.chats.createGroup
import com.limemessenger.lime.chats.suggestedGroupName
import com.limemessenger.lime.ui.common.Avatar
import com.limemessenger.lime.ui.common.GroupAvatar
import com.limemessenger.lime.ui.common.initialsOf
import com.limemessenger.lime.ui.onboarding.PrimaryButton
import com.limemessenger.lime.ui.shell.Icons
import com.limemessenger.lime.ui.theme.Lime
import kotlinx.coroutines.launch

// Group screens, as ios/Lime/Features/Groups/: the picker (New group / Add members), the name, and the group's details. The hero, cover, media/files/links
// tabs and the group photo are not on Android yet (docs/screens/groups.android.md).

@Composable
private fun TopBar(title: String, onBack: () -> Unit, backTag: String, action: @Composable () -> Unit = {}) {
    val colors = Lime.colors
    Row(Modifier.fillMaxWidth().heightIn(min = 64.dp).padding(horizontal = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        IconButton(onClick = onBack, Modifier.size(56.dp).testTag(backTag)) { Icon(Icons.Back, stringResource(R.string.group_back), tint = colors.text) }
        Text(title, color = colors.text, fontSize = 20.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f).semantics { heading() })
        action()
        Box(Modifier.size(8.dp))
    }
}

@Composable
private fun textFieldColors(colors: com.limemessenger.lime.ui.theme.LimeColors) = OutlinedTextFieldDefaults.colors(
    focusedTextColor = colors.text, unfocusedTextColor = colors.text, focusedContainerColor = colors.surface, unfocusedContainerColor = colors.surface,
    focusedBorderColor = colors.text, unfocusedBorderColor = colors.hairline, cursorColor = colors.text,
)

/** Picks people from the teachers I already message: chips on top, "N members", a search, Next (create) or Add (add to a group). */
@Composable
fun GroupPickerScreen(chats: ChatsModel, existing: List<String>, adding: Boolean, onBack: () -> Unit, onNext: (List<String>) -> Unit) {
    val colors = Lime.colors
    var chosen by rememberSaveable { mutableStateOf(listOf<String>()) }
    var query by rememberSaveable { mutableStateOf("") }
    val teachers = KnownTeachers.from(chats.conversations).filter { it.id !in existing }
    val sections = KnownTeachers.sections(teachers, query)
    val count = if (adding) stringResource(R.string.group_selected_count, chosen.size) else if (chosen.size + 1 == 1) stringResource(R.string.group_members_count_one) else stringResource(R.string.group_members_count_create, chosen.size + 1)
    Column(Modifier.fillMaxSize().background(colors.canvas).systemBarsPadding().imePadding()) {
        TopBar(stringResource(if (adding) R.string.group_add_title else R.string.group_pick_title), onBack, "group-back") {
            Box(Modifier.heightIn(min = 48.dp).background(if (chosen.isEmpty()) colors.pressed else colors.accent, RoundedCornerShape(24.dp))
                .then(if (chosen.isEmpty()) Modifier else Modifier.semantics { role = Role.Button }.clickable { onNext(chosen) })
                .padding(horizontal = 18.dp).testTag("group-next"), contentAlignment = Alignment.Center) {
                Text(stringResource(if (adding) R.string.group_add else R.string.group_next), color = if (chosen.isEmpty()) colors.textSecondary else colors.accentInk, fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
            }
        }
        Text(count, color = colors.textSecondary, fontSize = 15.sp, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth().testTag("group-count"))
        if (chosen.isNotEmpty()) {
            Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp).horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                chosen.forEach { id ->
                    val teacher = teachers.firstOrNull { it.id == id } ?: return@forEach
                    val remove = stringResource(R.string.group_remove_chip, teacher.name)
                    Row(
                        Modifier.heightIn(min = 48.dp).background(colors.surface, RoundedCornerShape(24.dp)).semantics { contentDescription = remove; role = Role.Button }
                            .clickable { chosen = chosen - id }.padding(horizontal = 12.dp).testTag("group-chip-$id"),
                        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp),
                    ) {
                        Avatar(teacher.initials.ifEmpty { initialsOf(teacher.name) }, teacher.tone, 26.dp)
                        Text(teacher.name.split(" ").first(), color = colors.text, fontSize = 15.sp)
                        Icon(Icons.Close, null, tint = colors.textSecondary, modifier = Modifier.size(14.dp))
                    }
                }
            }
        }
        LazyColumn(Modifier.weight(1f).testTag("group-people")) {
            if (teachers.isEmpty()) item(key = "none") {
                Text(stringResource(if (adding) R.string.group_no_teachers_add else R.string.group_no_teachers_create), color = colors.textSecondary, fontSize = 17.sp, textAlign = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth().padding(top = 40.dp, start = 32.dp, end = 32.dp).testTag("group-no-teachers"))
            }
            sections.forEach { (letter, people) ->
                item(key = "h-$letter") { Text(letter, color = colors.textSecondary, fontSize = 14.sp, fontWeight = FontWeight.Bold, modifier = Modifier.padding(horizontal = 20.dp, vertical = 6.dp).semantics { heading() }) }
                items(people, key = { it.id }) { teacher ->
                    val on = teacher.id in chosen
                    Row(
                        Modifier.fillMaxWidth().heightIn(min = 60.dp).semantics(mergeDescendants = true) { role = Role.Checkbox; selected = on }
                            .clickable { chosen = if (on) chosen - teacher.id else chosen + teacher.id }.padding(horizontal = 20.dp, vertical = 8.dp).testTag("group-pick-${teacher.id}"),
                        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp),
                    ) {
                        Avatar(teacher.initials.ifEmpty { initialsOf(teacher.name) }, teacher.tone, 44.dp)
                        Text(teacher.name, color = colors.text, fontSize = 17.sp, modifier = Modifier.weight(1f))
                        Icon(if (on) Icons.CheckedBox else Icons.UncheckedBox, null, tint = if (on) colors.text else colors.textSecondary, modifier = Modifier.size(24.dp))
                    }
                }
            }
        }
        OutlinedTextField(
            value = query, onValueChange = { query = it }, singleLine = true, shape = RoundedCornerShape(26.dp), colors = textFieldColors(colors),
            leadingIcon = { Icon(Icons.Search, null, tint = colors.textSecondary) },
            placeholder = { Text(stringResource(R.string.group_search_hint), color = colors.textSecondary) },
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp).heightIn(min = 56.dp).testTag("group-search"),
        )
    }
}

/** The group's name (required, at most 50 characters; it starts as the first names of the people picked) and an optional emoji, then Create. */
@Composable
fun GroupNameScreen(chats: ChatsModel, memberIds: List<String>, onBack: () -> Unit, onCreated: (String) -> Unit) {
    val colors = Lime.colors
    val scope = rememberCoroutineScope()
    val people: List<KnownTeacher> = memberIds.mapNotNull { id -> KnownTeachers.from(chats.conversations).firstOrNull { it.id == id } }
    var name by rememberSaveable { mutableStateOf(suggestedGroupName(people)) }
    var emoji by rememberSaveable { mutableStateOf("") }
    var making by remember { mutableStateOf(false) }
    var failed by remember { mutableStateOf(false) }
    val cleaned = name.trim()
    val canCreate = cleaned.isNotEmpty() && cleaned.length <= GROUP_NAME_LIMIT && !making
    fun create() {
        if (!canCreate) return
        making = true; failed = false
        scope.launch {
            val id = chats.createGroup(cleaned, emoji.trim().ifEmpty { null }, memberIds)
            making = false
            if (id != null) onCreated(id) else failed = true
        }
    }
    Column(Modifier.fillMaxSize().background(colors.canvas).systemBarsPadding().imePadding().verticalScroll(rememberScrollState())) {
        TopBar(stringResource(R.string.group_pick_title), onBack, "group-name-back") {
            Box(Modifier.heightIn(min = 48.dp).background(if (canCreate) colors.accent else colors.pressed, RoundedCornerShape(24.dp))
                .then(if (canCreate) Modifier.semantics { role = Role.Button }.clickable { create() } else Modifier).padding(horizontal = 18.dp).testTag("group-create"), contentAlignment = Alignment.Center) {
                Text(stringResource(R.string.group_create), color = if (canCreate) colors.accentInk else colors.textSecondary, fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
            }
        }
        Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            OutlinedTextField(
                value = name, onValueChange = { name = it.take(GROUP_NAME_LIMIT) }, singleLine = true, shape = RoundedCornerShape(14.dp), colors = textFieldColors(colors),
                label = { Text(stringResource(R.string.group_name_field), color = colors.textSecondary) },
                modifier = Modifier.fillMaxWidth().heightIn(min = 56.dp).testTag("group-name-field"),
            )
            Text(stringResource(R.string.group_name_count, cleaned.length.coerceAtMost(GROUP_NAME_LIMIT), GROUP_NAME_LIMIT), color = colors.textSecondary, fontSize = 13.sp, modifier = Modifier.testTag("group-name-count"))
            OutlinedTextField(
                value = emoji, onValueChange = { emoji = it.take(8) }, singleLine = true, shape = RoundedCornerShape(14.dp), colors = textFieldColors(colors),
                label = { Text(stringResource(R.string.group_emoji_field), color = colors.textSecondary) },
                modifier = Modifier.fillMaxWidth().heightIn(min = 56.dp).testTag("group-emoji-field"),
            )
            Text(stringResource(R.string.group_members_count_create, memberIds.size + 1), color = colors.textSecondary, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                people.forEach { p ->
                    Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.size(width = 64.dp, height = 72.dp)) {
                        Avatar(p.initials.ifEmpty { initialsOf(p.name) }, p.tone, 44.dp)
                        Text(p.name.split(" ").first(), color = colors.text, fontSize = 13.sp, maxLines = 1)
                    }
                }
            }
            if (failed) Text("Couldn’t make the group. Try again.", color = colors.danger, fontSize = 15.sp, modifier = Modifier.testTag("group-create-failed"))
        }
    }
}

/** A group's details: its picture, name and member count, the members (with Remove where I may), Rename and Add members where I may, and Leave. */
@Composable
fun GroupDetailsScreen(chats: ChatsModel, model: GroupModel, myName: String, myTone: Int, onBack: () -> Unit, onLeft: () -> Unit) {
    val colors = Lime.colors
    val scope = rememberCoroutineScope()
    LaunchedEffect(model.conversationId, chats.revision) { model.refresh() }
    val details = model.details
    val summary = chats.conversations.firstOrNull { it.id == model.conversationId }
    var renaming by remember { mutableStateOf(false) }
    var newName by remember { mutableStateOf("") }
    var removing by remember { mutableStateOf<uniffi.lime_core.GroupMemberInfo?>(null) }
    var leaving by remember { mutableStateOf(false) }
    var adding by remember { mutableStateOf(false) }
    if (adding && details != null) {
        GroupPickerScreen(chats, existing = details.members.map { it.userId }, adding = true, onBack = { adding = false }, onNext = { ids -> scope.launch { model.add(ids); adding = false } })
        androidx.activity.compose.BackHandler { adding = false }
        return
    }
    Column(Modifier.fillMaxSize().background(colors.canvas).systemBarsPadding().verticalScroll(rememberScrollState())) {
        TopBar(stringResource(R.string.group_info_title), onBack, "group-details-back")
        if (details == null) return@Column
        Column(Modifier.fillMaxWidth().padding(16.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
            if (summary != null) GroupAvatar(summary, myName, myTone, 104.dp)
            Text(details.name, color = colors.text, fontSize = 24.sp, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center, modifier = Modifier.semantics { heading() }.testTag("group-details-name"))
            val n = details.members.size
            Text(if (n == 1) stringResource(R.string.group_members_count_one) else stringResource(R.string.group_members_count_create, n), color = colors.textSecondary, fontSize = 15.sp, modifier = Modifier.testTag("group-details-count"))
        }
        if (details.canRename) {
            DetailRow(stringResource(R.string.group_rename), "group-rename") { newName = details.name; renaming = true }
        }
        if (details.canAdd) DetailRow(stringResource(R.string.group_add_members), "group-add-members") { adding = true }
        Text(stringResource(R.string.group_members_heading), color = colors.textSecondary, fontSize = 14.sp, fontWeight = FontWeight.Bold, modifier = Modifier.padding(horizontal = 20.dp, vertical = 10.dp).semantics { heading() })
        details.members.forEach { m ->
            val role = when (m.role) { "owner" -> stringResource(R.string.group_role_owner); "admin" -> stringResource(R.string.group_role_admin); else -> null }
            Row(
                Modifier.fillMaxWidth().heightIn(min = 60.dp).padding(horizontal = 20.dp, vertical = 6.dp).testTag("group-member-${m.userId}"),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp),
            ) {
                Avatar(initialsOf(if (m.isMe) myName else m.name), if (m.isMe) myTone else m.tone.toInt(), 44.dp)
                Column(Modifier.weight(1f)) {
                    Text(m.name, color = colors.text, fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
                    role?.let { Text(it, color = colors.textSecondary, fontSize = 14.sp) }
                }
                if (m.canRemove) TextButton(onClick = { removing = m }, Modifier.heightIn(min = 48.dp).testTag("group-remove-${m.userId}")) { Text(stringResource(R.string.group_remove), color = colors.danger, fontSize = 15.sp) }
            }
        }
        Text(stringResource(R.string.group_name_note), color = colors.textSecondary, fontSize = 13.sp, modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp))
        DetailRow(stringResource(R.string.group_leave), "group-leave", danger = true) { leaving = true }
        if (model.failed) Text("That didn’t work. Try again.", color = colors.danger, fontSize = 15.sp, modifier = Modifier.padding(20.dp).testTag("group-failed"))
    }
    if (renaming) {
        AlertDialog(
            onDismissRequest = { renaming = false },
            title = { Text(stringResource(R.string.group_rename_title)) },
            text = {
                OutlinedTextField(value = newName, onValueChange = { newName = it.take(GROUP_NAME_LIMIT) }, singleLine = true, modifier = Modifier.testTag("group-rename-field"))
            },
            confirmButton = { TextButton(onClick = { val name = newName; renaming = false; scope.launch { model.rename(name) } }, enabled = newName.trim().isNotEmpty(), modifier = Modifier.testTag("group-rename-save")) { Text(stringResource(R.string.group_save)) } },
            dismissButton = { TextButton(onClick = { renaming = false }) { Text(stringResource(R.string.group_cancel)) } },
        )
    }
    removing?.let { m ->
        AlertDialog(
            onDismissRequest = { removing = null },
            title = { Text(stringResource(R.string.group_remove_title, m.name)) },
            text = { Text(stringResource(R.string.group_remove_body)) },
            confirmButton = { TextButton(onClick = { removing = null; scope.launch { model.remove(m.userId) } }, modifier = Modifier.testTag("group-remove-confirm")) { Text(stringResource(R.string.group_remove), color = colors.danger) } },
            dismissButton = { TextButton(onClick = { removing = null }) { Text(stringResource(R.string.group_cancel)) } },
        )
    }
    if (leaving) {
        AlertDialog(
            onDismissRequest = { leaving = false },
            title = { Text(stringResource(R.string.group_leave_confirm_title, details?.name.orEmpty())) },
            text = { Text(stringResource(R.string.group_leave_confirm_body)) },
            confirmButton = { TextButton(onClick = { leaving = false; scope.launch { if (model.leave()) onLeft() } }, modifier = Modifier.testTag("group-leave-confirm")) { Text(stringResource(R.string.group_leave), color = colors.danger) } },
            dismissButton = { TextButton(onClick = { leaving = false }) { Text(stringResource(R.string.group_cancel)) } },
        )
    }
}

@Composable
private fun DetailRow(title: String, tag: String, danger: Boolean = false, onClick: () -> Unit) {
    val colors = Lime.colors
    Row(
        Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 4.dp).background(colors.surface, RoundedCornerShape(16.dp)).heightIn(min = 56.dp)
            .semantics { role = Role.Button }.clickable(onClick = onClick).padding(horizontal = 16.dp).testTag(tag),
        verticalAlignment = Alignment.CenterVertically,
    ) { Text(title, color = if (danger) colors.danger else colors.text, fontSize = 17.sp) }
}
