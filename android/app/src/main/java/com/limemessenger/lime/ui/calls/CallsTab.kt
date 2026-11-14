package com.limemessenger.lime.ui.calls

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.limemessenger.lime.R
import com.limemessenger.lime.calls.CallFilter
import com.limemessenger.lime.calls.CallsModel
import com.limemessenger.lime.chats.ChatsModel
import com.limemessenger.lime.chats.KnownTeachers
import com.limemessenger.lime.ui.chats.Chip
import com.limemessenger.lime.ui.chats.RootHeader
import com.limemessenger.lime.ui.common.Avatar
import com.limemessenger.lime.ui.common.GroupAvatar
import com.limemessenger.lime.ui.shell.Icons
import com.limemessenger.lime.ui.shell.TabIcons
import com.limemessenger.lime.ui.theme.Lime
import com.limemessenger.lime.ui.theme.LimeCircle
import com.limemessenger.lime.ui.theme.LimeShapes
import com.limemessenger.lime.ui.theme.LimeSpacing
import com.limemessenger.lime.ui.theme.LimeTopFade
import com.limemessenger.lime.ui.theme.LimeType
import com.limemessenger.lime.ui.theme.LimeType.style
import java.text.DateFormat
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import kotlinx.coroutines.launch
import uniffi.lime_core.CallBackChoice
import uniffi.lime_core.CallLogEntry
import uniffi.lime_core.CallLogGroup
import uniffi.lime_core.CallTimeLabel
import uniffi.lime_core.CallShortDate
import uniffi.lime_core.callBackChoice
import uniffi.lime_core.callLogGroups
import uniffi.lime_core.callLogOutcomeText
import uniffi.lime_core.callLogRowNote
import uniffi.lime_core.callPeerIsGroup
import uniffi.lime_core.callShortDateKind
import uniffi.lime_core.callTimeLabelKind

/** What the person wants to do with a call: call someone (a person or a group's id) by voice or video. */
typealias PlaceCall = (peerId: String, name: String, video: Boolean) -> Unit

private fun tzOffsetSeconds(now: Long) = TimeZone.getDefault().getOffset(now) / 1000

/** The time at the right of a row: the core says which kind of label, this writes it in the person's locale. */
@Composable
internal fun callTimeLabel(atMs: Long, nowMs: Long): String = when (callTimeLabelKind(atMs, nowMs, tzOffsetSeconds(nowMs))) {
    CallTimeLabel.TIME -> DateFormat.getTimeInstance(DateFormat.SHORT).format(Date(atMs))
    CallTimeLabel.YESTERDAY -> stringResource(R.string.calls_yesterday)
    CallTimeLabel.WEEKDAY -> SimpleDateFormat("EEEE", Locale.getDefault()).format(Date(atMs))
    CallTimeLabel.DATE -> DateFormat.getDateInstance(DateFormat.SHORT).format(Date(atMs))
}

private fun shortDate(atMs: Long, nowMs: Long): String {
    val time = DateFormat.getTimeInstance(DateFormat.SHORT).format(Date(atMs))
    val sameYear = java.util.Calendar.getInstance().apply { timeInMillis = atMs }.get(java.util.Calendar.YEAR) == java.util.Calendar.getInstance().apply { timeInMillis = nowMs }.get(java.util.Calendar.YEAR)
    return when (val kind = callShortDateKind(atMs, nowMs, tzOffsetSeconds(nowMs), sameYear)) {
        CallShortDate.Time -> time
        CallShortDate.YesterdayTime -> "Yesterday $time"
        is CallShortDate.DateTime -> SimpleDateFormat(if (kind.withYear) "MMM d, yyyy" else "MMM d", Locale.getDefault()).format(Date(atMs)) + ", $time"
    }
}

/**
 * The Calls tab (iOS `CallHistoryView`): the history fills the screen and scrolls under the floating header; All | Missed and a filter menu are the first row; rows
 * are grouped by the core's rule with a round call-back button; swipe to delete; the plus is "New call".
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CallsScreen(
    model: CallsModel,
    chats: ChatsModel,
    myName: String,
    myTone: Int,
    onProfile: () -> Unit,
    onSearch: () -> Unit,
    onPlaceCall: PlaceCall,
    modifier: Modifier = Modifier,
) {
    val colors = Lime.colors
    val scope = rememberCoroutineScope()
    var details by remember { mutableStateOf<CallLogGroup?>(null) }
    var newCall by remember { mutableStateOf(false) }
    // Opening the tab marks the missed calls seen (the badge goes).
    LaunchedEffect(Unit) { model.reload(); model.markMissedSeen() }
    val now = System.currentTimeMillis()
    val groups = callLogGroups(model.shown, tzOffsetSeconds(now))
    Box(modifier.fillMaxSize().background(colors.canvas).testTag("calls-screen")) {
        com.limemessenger.lime.ui.theme.FloatingHeaderLayout(
            Modifier.fillMaxSize(),
            header = { RootHeader(myName, myTone, onProfile, onSearch, searchTag = "calls-search-button") },
        ) { headerDp ->
            LazyColumn(Modifier.fillMaxSize().testTag("calls-list"), contentPadding = androidx.compose.foundation.layout.PaddingValues(top = headerDp, bottom = 96.dp)) {
                item(key = "filters") { CallsFilterRow(model) }
                if (groups.isEmpty()) item(key = "empty") { CallsEmpty(model, onNewCall = { newCall = true }) }
                items(groups, key = { it.id }) { group ->
                    CallRow(
                        group, chats, now, onCallBack = { onPlaceCall(it.peerId, it.peerName, it.video) }, onDetails = { details = group },
                        onDelete = { scope.launch { model.delete(group.entries.map { it.id }) } },
                    )
                }
            }
        }
        val label = stringResource(R.string.calls_new_call)
        Box(
            Modifier.align(Alignment.BottomEnd).padding(16.dp).size(LimeCircle.fab).shadow(6.dp, LimeShapes.circle).background(colors.accent, LimeShapes.circle)
                .semantics { role = Role.Button; contentDescription = label }.clickable { newCall = true }.testTag("new-call-button"),
            contentAlignment = Alignment.Center,
        ) { Icon(Icons.Plus, null, tint = colors.accentInk, modifier = Modifier.size(28.dp)) }
    }
    details?.let { group ->
        CallDetailsSheet(group, now, onCall = { video -> details = null; onPlaceCall(group.entries[0].peerId, group.entries[0].peerName, video) }, onDelete = {
            details = null; scope.launch { model.delete(group.entries.map { it.id }) }
        }, onDismiss = { details = null })
    }
    if (newCall) NewCallSheet(chats, onCall = { id, name, video -> newCall = false; onPlaceCall(id, name, video) }, onDismiss = { newCall = false })
}

/** All | Missed and the filter menu (kind, direction): the first row of the list, so it scrolls away with the rows. */
@Composable
private fun CallsFilterRow(model: CallsModel) {
    val colors = Lime.colors
    var menu by remember { mutableStateOf(false) }
    val active = model.filter.activeCount
    Row(Modifier.fillMaxWidth().padding(horizontal = LimeSpacing.l, vertical = LimeSpacing.xs), horizontalArrangement = Arrangement.spacedBy(LimeSpacing.s), verticalAlignment = Alignment.CenterVertically) {
        Chip(stringResource(R.string.calls_filter_all), !model.missedOnly, "calls-filter-all") { model.missedOnly = false }
        Chip(stringResource(R.string.calls_filter_missed), model.missedOnly, "calls-filter-missed") { model.missedOnly = true }
        Box {
            val words = if (active == 0) stringResource(R.string.calls_filter_button) else stringResource(R.string.calls_filter_button_active, active)
            Box(
                Modifier.heightIn(min = LimeCircle.target).widthIn(min = LimeCircle.target).semantics { contentDescription = words; role = Role.Button }.clickable { menu = true }.testTag("calls-filter-menu"),
                contentAlignment = Alignment.Center,
            ) {
                Row(Modifier.background(if (active > 0) colors.pressed else colors.surface, LimeShapes.pill).padding(horizontal = 14.dp, vertical = LimeSpacing.s), verticalAlignment = Alignment.CenterVertically) {
                    Text(stringResource(R.string.filter_label), color = colors.text, style = LimeType.run { secondary.style() }, fontWeight = if (active > 0) FontWeight.Bold else FontWeight.Normal)
                    if (active > 0) Text(" $active", color = colors.text, style = LimeType.run { secondary.style() }, fontWeight = FontWeight.Bold)
                }
            }
            DropdownMenu(expanded = menu, onDismissRequest = { menu = false }, modifier = Modifier.testTag("calls-filter-sheet")) {
                @Composable
                fun toggle(title: String, on: Boolean, tag: String, set: (Boolean) -> Unit) = DropdownMenuItem(
                    text = { Text(title) }, onClick = { set(!on) },
                    modifier = Modifier.semantics { role = Role.Checkbox; selected = on }.testTag(tag),
                    leadingIcon = { Icon(if (on) Icons.CheckedBox else Icons.UncheckedBox, null) },
                )
                val f = model.filter
                Text(stringResource(R.string.calls_filter_kind), color = colors.textSecondary, style = LimeType.run { caption.style() }, modifier = Modifier.padding(horizontal = LimeSpacing.l, vertical = LimeSpacing.xs).semantics { heading() })
                toggle(stringResource(R.string.calls_filter_voice), f.video == false, "calls-filter-voice") { model.filter = f.copy(video = if (it) false else null) }
                toggle(stringResource(R.string.calls_filter_video), f.video == true, "calls-filter-video") { model.filter = f.copy(video = if (it) true else null) }
                Text(stringResource(R.string.calls_filter_direction), color = colors.textSecondary, style = LimeType.run { caption.style() }, modifier = Modifier.padding(horizontal = LimeSpacing.l, vertical = LimeSpacing.xs).semantics { heading() })
                toggle(stringResource(R.string.calls_filter_incoming), f.incoming == true, "calls-filter-incoming") { model.filter = f.copy(incoming = if (it) true else null) }
                toggle(stringResource(R.string.calls_filter_outgoing), f.incoming == false, "calls-filter-outgoing") { model.filter = f.copy(incoming = if (it) false else null) }
                if (f.isOn) DropdownMenuItem(text = { Text(stringResource(R.string.calls_filter_clear), color = colors.danger) }, onClick = { model.filter = CallFilter(); menu = false }, modifier = Modifier.testTag("calls-filter-clear"))
            }
        }
    }
}

@Composable
private fun CallsEmpty(model: CallsModel, onNewCall: () -> Unit) {
    val colors = Lime.colors
    Column(Modifier.fillMaxWidth().padding(top = 80.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp)) {
        if (model.records.isNotEmpty() && model.filter.isOn) {
            Text(stringResource(R.string.calls_no_match), color = colors.textSecondary, style = LimeType.run { body.style() }, modifier = Modifier.testTag("calls-no-match"))
            Box(Modifier.heightIn(min = LimeCircle.target).clickable { model.filter = CallFilter() }.padding(LimeSpacing.m), contentAlignment = Alignment.Center) {
                Text(stringResource(R.string.chats_clear_filter), color = colors.text, style = LimeType.run { title.style() })
            }
        } else if (model.missedOnly) {
            Text(stringResource(R.string.calls_empty_missed), color = colors.textSecondary, style = LimeType.run { body.style() }, modifier = Modifier.testTag("calls-empty-missed"))
        } else {
            Text(stringResource(R.string.calls_empty), color = colors.textSecondary, style = LimeType.run { body.style() }, modifier = Modifier.testTag("calls-empty"))
            Box(
                Modifier.heightIn(min = LimeCircle.target).background(colors.accent, LimeShapes.pill).semantics { role = Role.Button }.clickable(onClick = onNewCall).padding(horizontal = 22.dp).testTag("calls-empty-new-call"),
                contentAlignment = Alignment.Center,
            ) { Text(stringResource(R.string.calls_new_call), color = colors.accentInk, style = LimeType.run { title.style() }) }
        }
    }
}

/** One history row (iOS `CallRowView`): avatar, name (red when missed, "(3)" when grouped), the time, the kind and direction, a note, a round call-back button. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun CallRow(group: CallLogGroup, chats: ChatsModel, nowMs: Long, onCallBack: (CallLogEntry) -> Unit, onDetails: () -> Unit, onDelete: (() -> Unit)?) {
    val colors = Lime.colors
    val call = group.entries[0]
    val missed = group.isMissedIncoming
    val time = callTimeLabel(call.atMs, nowMs)
    val kind = stringResource(if (call.video) R.string.calls_kind_video else R.string.calls_kind_voice)
    val note = callLogRowNote(call.result)
    // The name as the chats know it now (a call can be logged before the person's name has reached this phone: the row then says the name it learns).
    val person = peerDisplayName(call.peerId, call.peerName, chats)
    val name = person + if (group.entries.size > 1) " (${group.entries.size})" else ""
    val label = stringResource(R.string.calls_row_label, name, kind.lowercase(), time) + (if (missed) stringResource(R.string.calls_row_missed) else "") + (note?.let { ", $it" } ?: "")
    val detailsWords = stringResource(R.string.calls_row_details)
    val deleteWords = stringResource(R.string.calls_row_delete)
    val actions = buildList {
        add(CustomAccessibilityAction(detailsWords) { onDetails(); true })
        if (onDelete != null) add(CustomAccessibilityAction(deleteWords) { onDelete(); true })
    }
    val state = rememberSwipeToDismissBoxState(confirmValueChange = { value ->
        if (value == SwipeToDismissBoxValue.EndToStart && onDelete != null) { onDelete(); true } else false
    })
    val content: @Composable () -> Unit = {
        Row(
            Modifier.fillMaxWidth().background(colors.canvas).padding(horizontal = LimeSpacing.l, vertical = LimeSpacing.s),
            horizontalArrangement = Arrangement.spacedBy(LimeSpacing.m), verticalAlignment = Alignment.CenterVertically,
        ) {
            // The picture opens the details; the rest of the row calls back (one TalkBack stop: the row, with Details and Delete as actions).
            Box(Modifier.size(LimeCircle.target + 4.dp).clickable(onClick = onDetails).clearAndSetSemantics { testTag = "call-row-avatar" }, contentAlignment = Alignment.Center) { CallAvatar(call, chats) }
            Column(
                Modifier.weight(1f).heightIn(min = LimeCircle.target)
                    .semantics(mergeDescendants = false) { contentDescription = label; role = Role.Button; customActions = actions; onClick(label = null) { false } }
                    .clickable(onClickLabel = stringResource(R.string.calls_row_hint)) { onCallBack(call) }.testTag("call-history-row"),
                verticalArrangement = Arrangement.spacedBy(3.dp),
            ) {
                Row(horizontalArrangement = Arrangement.spacedBy(LimeSpacing.s), verticalAlignment = Alignment.CenterVertically) {
                    Text(name, color = if (missed) colors.danger else colors.text, style = LimeType.run { title.style() }, modifier = Modifier.weight(1f).clearAndSetSemantics { testTag = "call-row-name" })
                    Text(time, color = colors.textSecondary, style = LimeType.run { secondary.style() }, maxLines = 1, modifier = Modifier.clearAndSetSemantics { })
                }
                Row(horizontalArrangement = Arrangement.spacedBy(5.dp), verticalAlignment = Alignment.CenterVertically) {
                    Icon(if (call.outgoing) Icons.ArrowUpRight else Icons.ArrowDownLeft, null, tint = colors.textSecondary, modifier = Modifier.size(14.dp))
                    Text(kind, color = colors.textSecondary, style = LimeType.run { secondary.style() })
                    if (missed) Text("· ${stringResource(R.string.calls_missed_word)}", color = colors.textSecondary, style = LimeType.run { secondary.style() }, fontWeight = FontWeight.SemiBold, modifier = Modifier.testTag("call-row-missed"))
                }
                if (note != null) Text(note, color = colors.textSecondary, style = LimeType.run { caption.style() }, maxLines = 2, modifier = Modifier.testTag("call-row-note"))
            }
            Box(
                Modifier.size(LimeCircle.target).background(colors.surface, LimeShapes.circle).clickable { onCallBack(call) }.clearAndSetSemantics { testTag = "call-row-callback" },
                contentAlignment = Alignment.Center,
            ) { Icon(if (call.video) Icons.Video else Icons.Phone, null, tint = colors.text, modifier = Modifier.size(22.dp)) }
        }
    }
    if (onDelete == null) content() else SwipeToDismissBox(
        state = state, enableDismissFromStartToEnd = false,
        backgroundContent = {
            Box(Modifier.fillMaxSize().background(colors.danger).padding(horizontal = LimeSpacing.xl), contentAlignment = Alignment.CenterEnd) {
                Icon(Icons.Trash, null, tint = androidx.compose.ui.graphics.Color.White)
            }
        },
        content = { content() }, modifier = Modifier.testTag("call-swipe-${group.id}"),
    )
}

internal fun peerDisplayName(peerId: String, logged: String, chats: ChatsModel): String =
    chats.conversations.firstOrNull { it.id == peerId || (!it.isGroup && it.members.firstOrNull()?.id == peerId) }?.title?.takeIf { it.isNotBlank() } ?: logged

@Composable
private fun CallAvatar(call: CallLogEntry, chats: ChatsModel) {
    val size = 52.dp
    if (callPeerIsGroup(call.peerId)) {
        val chat = chats.conversations.firstOrNull { it.id == call.peerId }
        if (chat != null) { GroupAvatar(chat, chats.myName, chats.myTone, size); return }
        Avatar(initialsOf(call.peerName), 0, size)
        return
    }
    val member = chats.conversations.firstOrNull { !it.isGroup && it.members.firstOrNull()?.id == call.peerId }?.members?.firstOrNull()
    if (member != null) Avatar(member.initials.ifEmpty { initialsOf(member.name) }, member.tone.toInt(), size)
    else Avatar(initialsOf(call.peerName), com.limemessenger.lime.chats.AvatarTone.tone(call.peerId), size)
}

private fun initialsOf(name: String): String = name.trim().split(' ').filter { it.isNotEmpty() }.take(2).joinToString("") { it.first().uppercase() }

/** The details a tap on the picture opens: the person and these calls listed, with Voice, Video and Delete. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun CallDetailsSheet(group: CallLogGroup, nowMs: Long, onCall: (Boolean) -> Unit, onDelete: () -> Unit, onDismiss: () -> Unit) {
    val colors = Lime.colors
    val first = group.entries[0]
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true), shape = LimeShapes.sheetTop, containerColor = colors.canvas, modifier = Modifier.testTag("call-details")) {
        Column(Modifier.fillMaxWidth().padding(horizontal = LimeSpacing.xl).padding(bottom = LimeSpacing.xxl), verticalArrangement = Arrangement.spacedBy(LimeSpacing.m)) {
            Text(first.peerName, color = colors.text, style = LimeType.run { sectionTitle.style() }, modifier = Modifier.semantics { heading() }.testTag("call-details-name"))
            Column(Modifier.fillMaxWidth().background(colors.surface, LimeShapes.card)) {
                group.entries.forEach { entry ->
                    Row(Modifier.fillMaxWidth().heightIn(min = 56.dp).padding(horizontal = 18.dp).semantics(mergeDescendants = true) { }, verticalAlignment = Alignment.CenterVertically) {
                        Icon(if (entry.outgoing) Icons.ArrowUpRight else Icons.ArrowDownLeft, null, tint = colors.textSecondary, modifier = Modifier.size(16.dp))
                        Column(Modifier.weight(1f).padding(start = LimeSpacing.m)) {
                            Text(stringResource(if (entry.video) R.string.calls_details_video else R.string.calls_details_voice), color = colors.text, style = LimeType.run { body.style() })
                            Text(shortDate(entry.atMs, nowMs), color = colors.textSecondary, style = LimeType.run { caption.style() })
                        }
                        Text(callLogOutcomeText(entry), color = colors.textSecondary, style = LimeType.run { secondary.style() }, modifier = Modifier.testTag("call-detail-outcome"))
                    }
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(LimeSpacing.m)) {
                SheetPill(stringResource(R.string.calls_details_voice), "call-details-voice", Modifier.weight(1f)) { onCall(false) }
                SheetPill(stringResource(R.string.calls_details_video), "call-details-video", Modifier.weight(1f)) { onCall(true) }
            }
            Box(Modifier.fillMaxWidth().heightIn(min = LimeCircle.target).clickable(onClick = onDelete).semantics { role = Role.Button }.testTag("call-details-delete"), contentAlignment = Alignment.Center) {
                Text(stringResource(R.string.calls_row_delete), color = colors.danger, style = LimeType.run { title.style() })
            }
        }
    }
}

@Composable
private fun SheetPill(text: String, tag: String, modifier: Modifier, onClick: () -> Unit) {
    val colors = Lime.colors
    Box(modifier.heightIn(min = 52.dp).background(colors.pressed, LimeShapes.pill).semantics { role = Role.Button }.clickable(onClick = onClick).testTag(tag), contentAlignment = Alignment.Center) {
        Text(text, color = colors.text, style = LimeType.run { title.style() })
    }
}

/** New Call (iOS `NewCallSheet`): the people I message, A to Z, with a voice and a video button each. (Groups arrive with group calls.) */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun NewCallSheet(chats: ChatsModel, onCall: PlaceCall, onDismiss: () -> Unit) {
    val colors = Lime.colors
    val people = KnownTeachers.from(chats.conversations).sortedBy { KnownTeachers.fold(it.name) }
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true), shape = LimeShapes.sheetTop, containerColor = colors.canvas, modifier = Modifier.testTag("new-call-sheet")) {
        Column(Modifier.fillMaxWidth().padding(bottom = LimeSpacing.xxl)) {
            Text(stringResource(R.string.calls_new_call_title), color = colors.text, style = LimeType.run { sectionTitle.style() }, modifier = Modifier.padding(horizontal = LimeSpacing.xl, vertical = LimeSpacing.m).semantics { heading() })
            if (people.isEmpty()) Text(stringResource(R.string.calls_new_call_none), color = colors.textSecondary, style = LimeType.run { secondary.style() }, modifier = Modifier.padding(horizontal = LimeSpacing.xl).testTag("new-call-empty"))
            LazyColumn(Modifier.heightIn(max = 480.dp)) {
                items(people, key = { it.id }) { person ->
                    Row(Modifier.fillMaxWidth().heightIn(min = 56.dp).padding(horizontal = LimeSpacing.l), horizontalArrangement = Arrangement.spacedBy(LimeSpacing.m), verticalAlignment = Alignment.CenterVertically) {
                        Avatar(person.initials.ifEmpty { initialsOf(person.name) }, person.tone, 40.dp)
                        Text(person.name, color = colors.text, style = LimeType.run { body.style() }, maxLines = 1, modifier = Modifier.weight(1f))
                        val voice = stringResource(R.string.calls_call_voice, person.name)
                        val video = stringResource(R.string.calls_call_video, person.name)
                        Box(Modifier.size(LimeCircle.target).background(colors.surface, LimeShapes.circle).semantics { contentDescription = voice; role = Role.Button }.clickable { onCall(person.id, person.name, false) }.testTag("new-call-${person.id}"), contentAlignment = Alignment.Center) {
                            Icon(Icons.Phone, null, tint = colors.text, modifier = Modifier.size(22.dp))
                        }
                        Box(Modifier.size(LimeCircle.target).background(colors.surface, LimeShapes.circle).semantics { contentDescription = video; role = Role.Button }.clickable { onCall(person.id, person.name, true) }.testTag("new-call-video-${person.id}"), contentAlignment = Alignment.Center) {
                            Icon(Icons.Video, null, tint = colors.text, modifier = Modifier.size(22.dp))
                        }
                    }
                }
            }
        }
    }
}

/** The call tab's search (iOS `CallSearchRoute`): the history narrowed to the names that match. */
@Composable
fun CallSearchScreen(model: CallsModel, chats: ChatsModel, onBack: () -> Unit, onPlaceCall: PlaceCall) {
    val colors = Lime.colors
    var query by remember { mutableStateOf("") }
    val now = System.currentTimeMillis()
    val typed = query.trim()
    val matches = model.records.filter { typed.isEmpty() || it.peerName.contains(typed, ignoreCase = true) }
    val groups = callLogGroups(matches, tzOffsetSeconds(now))
    androidx.activity.compose.BackHandler(onBack = onBack)
    Column(Modifier.fillMaxSize().background(colors.canvas).systemBarsPadding().testTag("call-search")) {
        Row(Modifier.fillMaxWidth().padding(horizontal = LimeSpacing.s, vertical = LimeSpacing.xs), horizontalArrangement = Arrangement.spacedBy(LimeSpacing.s), verticalAlignment = Alignment.CenterVertically) {
            com.limemessenger.lime.ui.theme.LimeCircleButton(Icons.Back, stringResource(R.string.group_back), onBack, Modifier.testTag("call-search-back"))
            Box(Modifier.weight(1f).heightIn(min = 52.dp).background(colors.surface, LimeShapes.pill).border(BorderStroke(0.5.dp, colors.hairline), LimeShapes.pill).padding(horizontal = LimeSpacing.l), contentAlignment = Alignment.CenterStart) {
                if (query.isEmpty()) Text(stringResource(R.string.calls_search_hint), color = colors.textSecondary, style = LimeType.run { body.style() })
                BasicTextField(
                    value = query, onValueChange = { query = it }, singleLine = true, textStyle = LimeType.run { body.style() }.copy(color = colors.text), cursorBrush = SolidColor(colors.text),
                    modifier = Modifier.fillMaxWidth().semantics { contentDescription = "" }.testTag("call-search-field"),
                )
            }
        }
        LazyColumn(Modifier.fillMaxSize()) {
            if (groups.isEmpty()) item { Text(stringResource(R.string.calls_search_none), color = colors.textSecondary, style = LimeType.run { secondary.style() }, modifier = Modifier.padding(LimeSpacing.xl).testTag("call-search-none")) }
            items(groups, key = { it.id }) { group ->
                CallRow(group, chats, now, onCallBack = { onPlaceCall(it.peerId, it.peerName, it.video) }, onDetails = { onPlaceCall(group.entries[0].peerId, group.entries[0].peerName, group.entries[0].video) }, onDelete = null)
            }
        }
    }
}

/** A call as the person is told what it does when tapped from the chat: a person is called back after asking. */
fun callBackFor(entryPeerId: String, liveCallId: String?): CallBackChoice = callBackChoice(callPeerIsGroup(entryPeerId), liveCallId)
