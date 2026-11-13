package com.limemessenger.lime.ui.moderation

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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.limemessenger.lime.R
import com.limemessenger.lime.chats.ChatsModel
import com.limemessenger.lime.chats.blockedPeople
import com.limemessenger.lime.chats.leaveGroup
import com.limemessenger.lime.chats.sendReport
import com.limemessenger.lime.chats.unblock
import com.limemessenger.lime.ui.settings.Choice
import com.limemessenger.lime.ui.settings.Footnote
import com.limemessenger.lime.ui.settings.SettingsCardColumn
import com.limemessenger.lime.ui.settings.SettingsPage
import com.limemessenger.lime.ui.settings.ToggleRow
import com.limemessenger.lime.ui.theme.Lime
import kotlinx.coroutines.launch
import uniffi.lime_core.ReportGroupMember
import uniffi.lime_core.ReportGroupMessage
import uniffi.lime_core.ReportTargetInfo

/** What a group report can carry (iOS `GroupReportDraft`): the last messages with words, the name and photo, and who is in it. */
class GroupReportDraft(val conversationId: String, val name: String, val hasPhoto: Boolean, val messages: List<ReportGroupMessage>, val members: List<ReportGroupMember>)

/**
 * The Report sheet (iOS `ReportSheet`, LIME-191): a reason, an optional note, what will be sent ("Include this …"), "Also block", Send. A group report lists its recent
 * messages to tick, the name and photo, who is in it, and leaving afterwards. The reported person is never told who reported. After Send: a thank-you.
 */
@Composable
fun ReportDialog(target: ReportTargetInfo, chats: ChatsModel, group: GroupReportDraft? = null, onDismiss: () -> Unit, onLeftGroup: () -> Unit = {}) {
    val colors = Lime.colors
    val scope = rememberCoroutineScope()
    val uri = LocalUriHandler.current
    var reason by remember { mutableStateOf<String?>(null) }
    var note by remember { mutableStateOf("") }
    var include by remember { mutableStateOf(true) }
    var alsoBlock by remember { mutableStateOf(false) }
    var sending by remember { mutableStateOf(false) }
    var sent by remember { mutableStateOf(false) }
    var failed by remember { mutableStateOf(false) }
    var ticked by remember { mutableStateOf(group?.messages?.map { it.id }?.toSet().orEmpty()) }
    var nameAndPhoto by remember { mutableStateOf(true) }
    var withMembers by remember { mutableStateOf(false) }
    var leaveAfter by remember { mutableStateOf(false) }
    var left by remember { mutableStateOf(false) }

    Dialog(onDismissRequest = { if (!sending) onDismiss() }, properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        Column(Modifier.fillMaxSize().background(colors.canvas).systemBarsPadding().imePadding().testTag("report-sheet")) {
            Row(Modifier.fillMaxWidth().heightIn(min = 64.dp), verticalAlignment = Alignment.CenterVertically) {
                if (!sent) TextButton({ onDismiss() }, Modifier.heightIn(min = 48.dp).padding(start = 8.dp).testTag("report-cancel")) { Text(stringResource(R.string.report_cancel), color = colors.text) }
                else Box(Modifier.size(8.dp))
                Text(if (sent) "" else stringResource(R.string.report_title), color = colors.text, fontSize = 20.sp, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center, modifier = Modifier.weight(1f).semantics { heading() })
                if (sent) TextButton({ onDismiss(); if (left) onLeftGroup() }, Modifier.heightIn(min = 48.dp).padding(end = 8.dp).testTag("report-done")) { Text(stringResource(R.string.report_done), color = colors.text, fontWeight = FontWeight.SemiBold) }
                else TextButton(
                    {
                        val chosen = reason ?: return@TextButton
                        scope.launch {
                            sending = true; failed = false
                            var outgoing = target
                            var includeIt = include
                            if (group != null) {
                                val payload = uniffi.lime_core.reportGroupPayload(group.conversationId, group.name, group.hasPhoto, group.messages, group.members, ticked.toList(), nameAndPhoto, withMembers)
                                outgoing = target.copy(ids = payload.ids, included = payload.included)
                                includeIt = true
                            }
                            val ok = chats.sendReport(outgoing, chosen, note, includeIt, alsoBlock)
                            sending = false
                            if (ok && leaveAfter && group != null) { chats.leaveGroup(group.conversationId); left = true }
                            if (ok) sent = true else failed = true
                        }
                    },
                    Modifier.heightIn(min = 48.dp).padding(end = 8.dp).testTag("report-send"), enabled = reason != null && !sending,
                ) { Text(stringResource(if (sending) R.string.report_sending else R.string.report_send), color = if (reason != null && !sending) colors.text else colors.textSecondary, fontWeight = FontWeight.SemiBold) }
            }
            if (sent) {
                Column(Modifier.weight(1f).fillMaxWidth().padding(24.dp), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(
                        stringResource(R.string.report_thanks), color = colors.text, fontSize = 22.sp, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center,
                        modifier = Modifier.semantics { heading(); liveRegion = LiveRegionMode.Polite }.testTag("report-thanks"),
                    )
                }
            } else Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(18.dp)) {
                Text(stringResource(R.string.report_whats_wrong), color = colors.text, fontSize = 18.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.semantics { heading() })
                SettingsCardColumn {
                    uniffi.lime_core.reportReasons().forEach { r -> Choice(uniffi.lime_core.reportReasonTitle(r), reason == r, "report-reason-$r") { reason = r } }
                }
                OutlinedTextField(
                    value = note, onValueChange = { note = it.take(500) }, minLines = 2, maxLines = 5, modifier = Modifier.fillMaxWidth().testTag("report-note"),
                    placeholder = { Text(stringResource(R.string.report_note_hint), color = colors.textSecondary) },
                )
                Text(
                    stringResource(R.string.report_how), color = colors.text, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, textDecoration = TextDecoration.Underline,
                    modifier = Modifier.heightIn(min = 48.dp).semantics { role = Role.Button }.clickable { uri.openUri(uniffi.lime_core.legalLinks().guidelines) }.padding(vertical = 12.dp).testTag("report-how-we-moderate"),
                )
                if (group == null) {
                    Column(Modifier.fillMaxWidth().background(colors.surface, RoundedCornerShape(16.dp)).padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        ToggleRow(stringResource(R.string.report_include, target.noun), include, "report-include") { include = it }
                        if (include && target.preview.isNotEmpty()) Text(target.preview, color = colors.textSecondary, fontSize = 13.sp, maxLines = 4, modifier = Modifier.testTag("report-preview"))
                        Text(uniffi.lime_core.reportIncludeWords(target.noun, target.personName, include), color = colors.textSecondary, fontSize = 13.sp)
                    }
                } else GroupInclude(group, ticked, { ticked = it }, nameAndPhoto, { nameAndPhoto = it }, withMembers, { withMembers = it }, leaveAfter, { leaveAfter = it })
                if (target.blockConversationId != null && target.personName != null) {
                    SettingsCardColumn { ToggleRow(stringResource(R.string.report_also_block, target.personName!!), alsoBlock, "report-also-block") { alsoBlock = it } }
                }
                if (failed) Text(stringResource(R.string.report_failed), color = colors.danger, fontSize = 14.sp, modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite }.testTag("report-failed"))
            }
        }
    }
}

@Composable
private fun GroupInclude(
    group: GroupReportDraft, ticked: Set<String>, onTicked: (Set<String>) -> Unit, nameAndPhoto: Boolean, onNameAndPhoto: (Boolean) -> Unit,
    withMembers: Boolean, onWithMembers: (Boolean) -> Unit, leaveAfter: Boolean, onLeaveAfter: (Boolean) -> Unit,
) {
    val colors = Lime.colors
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(stringResource(R.string.report_group_include), color = colors.text, fontSize = 18.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.semantics { heading() })
        Text(stringResource(R.string.report_recent), color = colors.textSecondary, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.semantics { heading() })
        if (group.messages.isEmpty()) Text(stringResource(R.string.report_no_messages), color = colors.textSecondary, fontSize = 14.sp)
        else SettingsCardColumn {
            group.messages.forEach { m ->
                val on = m.id in ticked
                val first = m.text.lineSequence().firstOrNull().orEmpty()
                val words = stringResource(if (on) R.string.report_include_message_on else R.string.report_include_message_off, m.senderName, first.take(80))
                Row(
                    Modifier.fillMaxWidth().heightIn(min = 52.dp).semantics(mergeDescendants = true) { contentDescription = words; role = Role.Checkbox }
                        .clickable { onTicked(if (on) ticked - m.id else ticked + m.id) }.padding(horizontal = 14.dp).testTag("report-message-${m.id}"),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    Text(if (on) "☑" else "☐", color = if (on) colors.text else colors.textSecondary, fontSize = 22.sp)
                    Column(Modifier.weight(1f)) {
                        Text(m.senderName, color = colors.textSecondary, fontSize = 13.sp)
                        Text(first, color = colors.text, fontSize = 16.sp, maxLines = 1)
                        if (m.attachments > 0u) Text(stringResource(R.string.report_attachments_not_sent, m.attachments.toInt()), color = colors.textSecondary, fontSize = 13.sp)
                    }
                }
            }
        }
        SettingsCardColumn {
            ToggleRow(stringResource(R.string.report_group_name), nameAndPhoto, "report-group-name", onNameAndPhoto)
            ToggleRow(stringResource(R.string.report_group_members), withMembers, "report-group-members", onWithMembers)
            ToggleRow(stringResource(R.string.report_group_leave), leaveAfter, "report-group-leave", onLeaveAfter)
        }
        Footnote(stringResource(R.string.report_group_footer))
    }
}

/** "Block <name>?" with Block and Cancel (iOS's confirm sheet; the words under it differ between the profile and the request bar). */
@Composable
fun BlockConfirm(name: String, body: String, confirmTag: String, onConfirm: () -> Unit, onDismiss: () -> Unit) {
    val colors = Lime.colors
    AlertDialog(
        onDismissRequest = onDismiss, containerColor = colors.canvas,
        title = { Text(stringResource(R.string.block_title, name), color = colors.text) },
        text = { Text(body, color = colors.textSecondary) },
        confirmButton = { TextButton(onConfirm, Modifier.heightIn(min = 48.dp).testTag(confirmTag)) { Text(stringResource(R.string.block_confirm), color = colors.danger, fontWeight = FontWeight.SemiBold) } },
        dismissButton = { TextButton(onDismiss, Modifier.heightIn(min = 48.dp)) { Text(stringResource(R.string.report_cancel), color = colors.text) } },
    )
}

/** Settings → Blocked (iOS `BlockedScreen`): the people I blocked, each one TalkBack stop "<name>, blocked" with Unblock as its action. */
@Composable
fun BlockedScreen(chats: ChatsModel, onBack: () -> Unit) {
    val colors = Lime.colors
    val scope = rememberCoroutineScope()
    var blocked by remember { mutableStateOf<List<uniffi.lime_core.BlockedPerson>?>(null) }
    var said by remember { mutableStateOf("") }
    val reads = remember { com.limemessenger.lime.ui.common.NewestRead() }   // the newest read wins (LIME-417): the first load and the read after an Unblock can overlap
    LaunchedEffect(Unit) { reads.read({ chats.blockedPeople() }) { blocked = it } }
    val unblockedWords = stringResource(R.string.blocked_unblocked, "%s")
    SettingsPage(stringResource(R.string.blocked_title), onBack, "blocked-screen") {
        val list = blocked
        if (list != null) {
            if (list.isEmpty()) Text(stringResource(R.string.blocked_none), color = colors.textSecondary, fontSize = 17.sp, modifier = Modifier.padding(top = 40.dp).testTag("blocked-empty"))
            else {
                SettingsCardColumn {
                    list.forEach { person ->
                        val unblock = {
                            scope.launch {
                                chats.unblock(person.conversationId)
                                reads.read({ chats.blockedPeople() }) { blocked = it }
                                said = unblockedWords.replace("%s", person.name)
                            }
                            Unit
                        }
                        val rowWords = stringResource(R.string.blocked_person_row, person.name)
                        val actionWords = stringResource(R.string.blocked_unblock_person, person.name)
                        Row(
                            Modifier.fillMaxWidth().heightIn(min = 66.dp).padding(horizontal = 18.dp).semantics(mergeDescendants = true) {
                                contentDescription = rowWords
                                customActions = listOf(CustomAccessibilityAction(actionWords) { unblock(); true })
                            }.testTag("blocked-row-${person.conversationId}"),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Text(person.name, color = colors.text, fontSize = 17.sp, modifier = Modifier.weight(1f))
                            // For touch: a button; TalkBack uses the row's action instead (one stop per row).
                            Box(
                                Modifier.heightIn(min = 48.dp).testTag("unblock-${person.conversationId}").clearAndSetSemantics {}.background(colors.chip, RoundedCornerShape(24.dp)).clickable { unblock() }.padding(horizontal = 16.dp),
                                contentAlignment = Alignment.Center,
                            ) { Text(stringResource(R.string.blocked_unblock), color = colors.text, fontSize = 15.sp, fontWeight = FontWeight.SemiBold) }
                        }
                    }
                }
                Footnote(stringResource(R.string.blocked_note))
            }
            if (said.isNotEmpty()) Text(said, color = colors.textSecondary, fontSize = 14.sp, modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite }.testTag("blocked-said"))
        }
    }
}
