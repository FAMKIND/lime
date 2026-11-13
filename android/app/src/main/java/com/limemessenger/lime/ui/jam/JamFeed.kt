package com.limemessenger.lime.ui.jam

import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.background
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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.limemessenger.lime.R
import com.limemessenger.lime.chats.AvatarTone
import com.limemessenger.lime.jam.JamDates
import com.limemessenger.lime.jam.JamModel
import com.limemessenger.lime.ui.chat.MessageText
import com.limemessenger.lime.ui.common.Avatar
import com.limemessenger.lime.ui.common.initialsOf
import com.limemessenger.lime.ui.shell.Icons
import com.limemessenger.lime.ui.theme.Lime
import kotlinx.coroutines.launch
import uniffi.lime_core.JamPostInfo
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.semantics.selected
import uniffi.lime_core.JamFeedSegment

/** The jam tab (iOS `JamPage`'s feed): the segments All · Posts · Articles · Podcasts and Saved, then the posts of the jams I follow and my own, newest first. Tapping a post reads it. */
@androidx.compose.material3.ExperimentalMaterial3Api
@Composable
fun JamFeedScreen(model: JamModel, modifier: Modifier = Modifier, onYours: (() -> Unit)? = null, onOpen: (JamPostInfo) -> Unit) {
    val colors = Lime.colors
    val scope = rememberCoroutineScope()
    val context = androidx.compose.ui.platform.LocalContext.current
    val player = remember { com.limemessenger.lime.chats.VoicePlayer(context.applicationContext) }
    androidx.compose.runtime.DisposableEffect(Unit) { onDispose { player.stop() } }
    var refreshing by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { model.reload() }
    Column(modifier.fillMaxSize().background(colors.canvas)) {
        Row(Modifier.fillMaxWidth().heightIn(min = 64.dp).padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(stringResource(R.string.tab_jam), color = colors.text, fontSize = 28.sp, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f).semantics { heading() })
            var joining by remember { mutableStateOf(false) }
            if (onYours != null) androidx.compose.material3.TextButton({ joining = true }, Modifier.heightIn(min = 48.dp).testTag("band-join-open")) { Text(stringResource(R.string.band_join), color = colors.text) }
            if (joining) com.limemessenger.lime.ui.band.BandJoinDialog(model, onDismiss = { joining = false })
            if (onYours != null) androidx.compose.material3.TextButton(onYours, Modifier.heightIn(min = 48.dp).testTag("jam-yours-open")) { Text(stringResource(R.string.jam_yours), color = colors.text, fontWeight = FontWeight.SemiBold) }
        }
        SegmentRow(model)
        PullToRefreshBox(
            isRefreshing = refreshing, onRefresh = { scope.launch { refreshing = true; try { model.reload() } finally { refreshing = false } } },
            modifier = Modifier.weight(1f),
        ) {
            LazyColumn(Modifier.fillMaxSize().testTag("jam-feed")) {
                if (model.isLoaded && model.posts.isEmpty()) item(key = "empty") {
                    Text(
                        stringResource(R.string.jam_empty), color = colors.textSecondary, fontSize = 17.sp, textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                        modifier = Modifier.fillMaxWidth().padding(horizontal = 40.dp).padding(top = 120.dp).testTag("jam-feed-empty"),
                    )
                } else if (model.isLoaded && model.shown.isEmpty()) item(key = "none") {
                    Text(
                        stringResource(if (model.savedOnly) R.string.jam_empty_saved else R.string.jam_empty), color = colors.textSecondary, fontSize = 17.sp, textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                        modifier = Modifier.fillMaxWidth().padding(horizontal = 40.dp).padding(top = 120.dp).testTag("jam-feed-none"),
                    )
                }
                items(model.shown, key = { it.postId }) { post -> PostCard(post, model, player) { onOpen(post) } }
            }
        }
    }
}

/** All · Posts · Articles · Podcasts (the core's segments) and a Saved pill: one chosen, 48 dp targets, "selected" said to TalkBack. */
@Composable
private fun SegmentRow(model: JamModel) {
    val colors = Lime.colors
    var sheet by remember { mutableStateOf(false) }
    val segments = uniffi.lime_core.jamSegments().filter { it != JamFeedSegment.DRAFTS && it != JamFeedSegment.DISCOVER }
    Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(horizontal = 12.dp, vertical = 4.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        segments.forEach { segment ->
            val on = model.segment == segment && !model.savedOnly
            val title = uniffi.lime_core.jamSegmentTitle(segment)
            Pill(title, on, "jam-segment-$title") { model.segment = segment; model.savedOnly = false }
        }
        Pill(stringResource(R.string.jam_segment_saved), model.savedOnly, "jam-segment-saved") { model.savedOnly = !model.savedOnly }
        val count = model.activeFilters
        Pill(if (count > 0) stringResource(R.string.jam_filter_count, count) else stringResource(R.string.jam_filter), count > 0, "jam-filter-button") { sheet = true }
    }
    if (sheet) JamFilterSheet(model, onDismiss = { sheet = false })
}

/** The feed's filter sheet (iOS's, LIME-412): a media kind, Co-authored, Subscribed, Bands and Saved, with Clear; the rule is the core's `jam_filter_matches`. */
@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
private fun JamFilterSheet(model: JamModel, onDismiss: () -> Unit) {
    val colors = Lime.colors
    androidx.compose.material3.ModalBottomSheet(onDismissRequest = onDismiss, containerColor = colors.canvas) {
        Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp).padding(bottom = 24.dp).testTag("jam-filter-sheet"), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(stringResource(R.string.jam_filter), color = colors.text, fontSize = 20.sp, fontWeight = FontWeight.Bold, modifier = Modifier.semantics { heading() })
            Text(stringResource(R.string.jam_filter_media), color = colors.textSecondary, fontSize = 14.sp)
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Pill(stringResource(R.string.jam_filter_any), model.mediaFilter == null, "jam-filter-media-any") { model.mediaFilter = null }
                listOf(uniffi.lime_core.JamFeedMedia.PHOTOS, uniffi.lime_core.JamFeedMedia.VIDEO, uniffi.lime_core.JamFeedMedia.AUDIO).forEach { media ->
                    val title = uniffi.lime_core.jamMediaTitle(media)
                    Pill(title, model.mediaFilter == media, "jam-filter-media-$title") { model.mediaFilter = if (model.mediaFilter == media) null else media }
                }
            }
            FilterToggle(stringResource(R.string.jam_filter_coauthored), model.coauthoredOnly, "jam-filter-coauthored") { model.coauthoredOnly = it }
            FilterToggle(stringResource(R.string.jam_filter_subscribed), model.subscribedOnly, "jam-filter-subscribed") { model.subscribedOnly = it }
            FilterToggle(stringResource(R.string.jam_filter_bands), model.bandsOnly, "jam-filter-bands") { model.bandsOnly = it }
            FilterToggle(stringResource(R.string.jam_segment_saved), model.savedOnly, "jam-filter-saved") { model.savedOnly = it }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                androidx.compose.material3.TextButton({ model.clearFilters() }, Modifier.heightIn(min = 48.dp).testTag("jam-filter-clear"), enabled = model.activeFilters > 0) { Text(stringResource(R.string.jam_filter_clear), color = colors.text) }
                androidx.compose.material3.TextButton(onDismiss, Modifier.heightIn(min = 48.dp).testTag("jam-filter-done")) { Text(stringResource(R.string.jam_filter_done), color = colors.text, fontWeight = FontWeight.SemiBold) }
            }
        }
    }
}

@Composable
private fun FilterToggle(title: String, on: Boolean, tag: String, onChange: (Boolean) -> Unit) {
    val colors = Lime.colors
    Row(
        Modifier.fillMaxWidth().heightIn(min = 52.dp).toggleable(on, role = Role.Switch, onValueChange = onChange).testTag(tag),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(title, color = colors.text, fontSize = 17.sp, modifier = Modifier.weight(1f))
        androidx.compose.material3.Switch(checked = on, onCheckedChange = null)
    }
}

@Composable
private fun Pill(title: String, on: Boolean, tag: String, onClick: () -> Unit) {
    val colors = Lime.colors
    Box(Modifier.heightIn(min = 48.dp).widthIn(min = 56.dp).semantics(mergeDescendants = true) { selected = on; role = Role.RadioButton }.clickable(onClick = onClick).testTag(tag), contentAlignment = Alignment.Center) {
        Box(Modifier.background(if (on) colors.pressed else colors.surface, RoundedCornerShape(18.dp)).padding(horizontal = 14.dp, vertical = 8.dp)) {
            Text(title, color = colors.text, fontSize = 15.sp, fontWeight = if (on) FontWeight.Bold else FontWeight.Normal)
        }
    }
}

/** A post as a card: the byline (avatar, name, "by …", date), then the title and the first words; a recording shows its play pill; then ♥ and comments. */
@Composable
private fun PostCard(post: JamPostInfo, model: JamModel, player: com.limemessenger.lime.chats.VoicePlayer, onOpen: () -> Unit) {
    val colors = Lime.colors
    val name = model.authorName(post)
    val writer = model.teacherName(post.author)
    val asJam = post.displayAs == "jam"
    val detail = listOfNotNull(model.byline(post), JamDates.short(post.created), if (post.editedAt > 0) "Edited" else null).joinToString(" · ")
    val files by androidx.compose.runtime.produceState(emptyList<uniffi.lime_core.JamAttachmentInfo>(), post.postId, post.state) { value = model.attachments(post.postId) }
    val audio = files.firstOrNull { it.kind == "audio" }
    val card = uniffi.lime_core.jamCardKind(post.kind == "record", post.state == "ready", audio != null, files.any { it.kind == "video" })
    val counts = model.countsOf(post.postId)
    val spoken = listOfNotNull(
        if (asJam) "$name, by $writer" else name, JamDates.spoken(post.created), if (card == uniffi.lime_core.JamCardKind.SMALL_PODCAST) "Podcast" else null,
        post.title.ifEmpty { null }, JamModel.excerpt(post, 120).ifEmpty { null },
        if (counts.likes > 0u) "${counts.likes} likes" else null, if (counts.comments > 0u) "${counts.comments} comments" else null, if (counts.unseen) "new comments" else null,
    ).joinToString(", ")
    Column(Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 14.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Column(
            Modifier.fillMaxWidth().clickable(onClick = onOpen).semantics { contentDescription = spoken; role = Role.Button }.testTag("jam-post-${post.postId}"),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Row(Modifier.clearAndSetSemantics { }, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Avatar(initialsOf(name), AvatarTone.tone(if (asJam) post.jamId else post.author), 40.dp)
                Column(Modifier.weight(1f)) {
                    Text(name, color = colors.text, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Text(if (asJam) "by $writer · $detail" else detail, color = colors.textSecondary, fontSize = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
                if (counts.unseen) Box(Modifier.size(10.dp).background(colors.accent, CircleShape).testTag("jam-unseen-${post.postId}"))
            }
            Column(Modifier.clearAndSetSemantics { }, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                if (post.title.isNotEmpty()) Text(post.title, color = colors.text, fontSize = 19.sp, fontWeight = FontWeight.Bold, maxLines = 3, overflow = TextOverflow.Ellipsis)
                val excerpt = JamModel.excerpt(post, if (post.kind == "quick") 400 else 200)
                if (excerpt.isNotEmpty()) Text(excerpt, color = if (post.kind == "article") colors.textSecondary else colors.text, fontSize = 16.sp, maxLines = if (post.kind == "quick") 8 else 3, overflow = TextOverflow.Ellipsis)
            }
        }
        if (card == uniffi.lime_core.JamCardKind.SMALL_PODCAST && audio != null) JamPodcastPill(post, audio, model, player)
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            JamHeartButton(post, model)
            JamCommentCount(post, model, onOpen)
            Spacer(Modifier.weight(1f))
            val saved = post.postId in model.saved
            val saveWords = stringResource(if (saved) R.string.jam_saved else R.string.jam_save)
            Box(Modifier.size(48.dp).semantics { contentDescription = saveWords; role = Role.Button; selected = saved }.clickable { model.toggleSaved(post.postId) }.testTag("jam-save-${post.postId}"), contentAlignment = Alignment.Center) {
                Icon(if (saved) Icons.BookmarkFilled else Icons.Bookmark, null, tint = colors.text, modifier = Modifier.size(22.dp))
            }
        }
    }
    Box(Modifier.fillMaxWidth().size(1.dp).background(colors.hairline))
}

/** Reading one post: the title, subtitle and byline, the post's Markdown with its photos in place (the writer's descriptions for TalkBack), a recording's player, then ♥ and the comments. */
@Composable
fun JamReaderScreen(post: JamPostInfo, model: JamModel, myId: String? = null, onEdit: ((JamPostInfo) -> Unit)? = null, chats: com.limemessenger.lime.chats.ChatsModel? = null, onViewBand: ((String) -> Unit)? = null, onBack: () -> Unit) {
    val colors = Lime.colors
    val context = androidx.compose.ui.platform.LocalContext.current
    val player = remember { com.limemessenger.lime.chats.VoicePlayer(context.applicationContext) }
    androidx.compose.runtime.DisposableEffect(Unit) { onDispose { player.stop() } }
    val files by androidx.compose.runtime.produceState(emptyList<uniffi.lime_core.JamAttachmentInfo>(), post.postId) { value = model.attachments(post.postId) }
    val saved = post.postId in model.saved
    val scope = rememberCoroutineScope()
    var confirmDelete by remember { mutableStateOf(false) }
    // Report a post or a comment (LIME-412; LIME-401's sheet and reasons; the core makes the target: `report_target_post`, `report_target_comment`).
    var reporting by remember { mutableStateOf<uniffi.lime_core.ReportTargetInfo?>(null) }
    val hasChat = { author: String -> chats?.conversations?.any { it.id == "dm:$author" } == true }
    Column(Modifier.fillMaxSize().background(colors.canvas).systemBarsPadding().imePadding()) {
        Row(Modifier.fillMaxWidth().heightIn(min = 64.dp), verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = onBack, Modifier.size(56.dp).testTag("jam-reader-back")) { Icon(Icons.Back, stringResource(R.string.chat_back), tint = colors.text) }
            Spacer(Modifier.weight(1f))
            // My own post: Edit and Delete (iOS's post menu).
            if (model.isMine(post)) {
                if (onEdit != null) androidx.compose.material3.TextButton({ onEdit(post) }, Modifier.heightIn(min = 48.dp).testTag("jam-reader-edit")) { Text(stringResource(R.string.jam_post_menu_edit), color = colors.text) }
                androidx.compose.material3.TextButton({ confirmDelete = true }, Modifier.heightIn(min = 48.dp).testTag("jam-reader-delete")) { Text(stringResource(R.string.jam_post_menu_delete), color = colors.danger) }
            }
            if (!model.isMine(post) && chats != null) androidx.compose.material3.TextButton({
                val blob = runCatching { model.blobIdOf(post.postId) }.getOrNull().orEmpty()
                reporting = uniffi.lime_core.reportTargetPost(post, model.authorName(post) ?: "", blob, hasChat(post.author))
            }, Modifier.heightIn(min = 48.dp).testTag("jam-reader-report")) { Text(stringResource(R.string.report_title), color = colors.text) }
            val saveWords = stringResource(if (saved) R.string.jam_saved else R.string.jam_save)
            Box(Modifier.size(56.dp).semantics { contentDescription = saveWords; role = Role.Button; selected = saved }.clickable { model.toggleSaved(post.postId) }.testTag("jam-reader-save"), contentAlignment = Alignment.Center) {
                Icon(if (saved) Icons.BookmarkFilled else Icons.Bookmark, null, tint = colors.text)
            }
        }
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 20.dp, vertical = 8.dp).testTag("jam-reader"), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            if (post.title.isNotEmpty()) Text(post.title, color = colors.text, fontSize = 28.sp, lineHeight = 34.sp, fontWeight = FontWeight.Bold, modifier = Modifier.semantics { heading() }.testTag("jam-reader-title"))
            if (post.subtitle.isNotEmpty()) Text(post.subtitle, color = colors.textSecondary, fontSize = 18.sp)
            val detail = listOfNotNull(model.authorName(post), model.byline(post), JamDates.short(post.created), if (post.editedAt > 0) "Edited" else null).joinToString(" · ")
            Text(detail, color = colors.textSecondary, fontSize = 14.sp, modifier = Modifier.testTag("jam-reader-byline"))
            // A post made as a band: its byline names the band, and View band opens its page (iOS: "View band" among the post's options).
            if (post.displayAs == "jam" && onViewBand != null) androidx.compose.material3.TextButton({ onViewBand(post.jamId) }, Modifier.heightIn(min = 48.dp).testTag("jam-reader-view-band")) { Text(stringResource(R.string.band_view), color = colors.text, fontWeight = FontWeight.SemiBold) }
            val images = files.filter { it.kind == "image" }
            files.firstOrNull { it.kind == "audio" }?.let { JamPodcastPill(post, it, model, player) }
            MessageText(
                post.markdown, color = colors.text, linkColor = colors.link, post = true, fontSize = 18f,
                image = { index, caption -> files.getOrNull(index)?.takeIf { it.kind == "image" }?.let { JamPhoto(post, it, caption, model) } },
            )
            // A quick post keeps its photos as a row under the words (an article puts them in the text).
            if (post.kind == "quick") images.forEach { JamPhoto(post, it, "", model) }
            JamEngagementSection(post, model, myId, onReportComment = if (chats == null) null else { c -> reporting = uniffi.lime_core.reportTargetComment(c, model.teacherName(c.author), hasChat(c.author)) })
        }
    }
    reporting?.let { target -> if (chats != null) com.limemessenger.lime.ui.moderation.ReportDialog(target, chats, onDismiss = { reporting = null }) }
    if (confirmDelete) androidx.compose.material3.AlertDialog(
        onDismissRequest = { confirmDelete = false }, containerColor = colors.canvas,
        title = { Text(stringResource(R.string.jam_delete_title), color = colors.text) },
        text = { Text(stringResource(R.string.jam_delete_body), color = colors.textSecondary) },
        confirmButton = { androidx.compose.material3.TextButton({ confirmDelete = false; scope.launch { if (model.deletePost(post.postId)) onBack() } }, Modifier.heightIn(min = 48.dp).testTag("jam-delete-confirm")) { Text(stringResource(R.string.jam_delete_confirm), color = colors.danger) } },
        dismissButton = { androidx.compose.material3.TextButton({ confirmDelete = false }, Modifier.heightIn(min = 48.dp)) { Text(stringResource(R.string.jam_cancel), color = colors.text) } },
    )
}
