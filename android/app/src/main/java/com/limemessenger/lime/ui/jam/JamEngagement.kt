package com.limemessenger.lime.ui.jam

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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
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
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.limemessenger.lime.R
import com.limemessenger.lime.jam.JamModel
import com.limemessenger.lime.ui.common.Avatar
import com.limemessenger.lime.ui.common.initialsOf
import com.limemessenger.lime.ui.shell.Icons
import com.limemessenger.lime.ui.theme.Lime
import com.limemessenger.lime.chats.AvatarTone
import kotlinx.coroutines.launch
import uniffi.lime_core.JamCommentInfo
import uniffi.lime_core.JamPostInfo

// ♥ and comments on a jam post (iOS `JamEngagement`): a heart with its count (a count of 0 shows no number), a comment count, the post page's response part with the
// comments (one level of replies under their parent; a comment on someone else's post waits "pending" until the writer's phone publishes it), delete my own.

/** The ♥ with its count: a tap toggles it. One button "Like, 12" for TalkBack, selected when on. */
@Composable
fun JamHeartButton(post: JamPostInfo, model: JamModel, modifier: Modifier = Modifier) {
    val colors = Lime.colors
    val scope = rememberCoroutineScope()
    val counts = model.countsOf(post.postId)
    val on = counts.likedByMe
    val words = if (counts.likes > 0u) stringResource(R.string.jam_like_count, counts.likes.toInt()) else stringResource(R.string.jam_like)
    Row(
        modifier.heightIn(min = 48.dp).widthIn48().semantics { contentDescription = words; role = Role.Button; selected = on }
            .clickable { scope.launch { model.toggleLike(post) } }.testTag("jam-like-${post.postId}"),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Icon(if (on) Icons.Heart else Icons.HeartOutline, null, tint = if (on) colors.danger else colors.text, modifier = Modifier.size(22.dp))
        if (counts.likes > 0u) Text("${counts.likes}", color = colors.textSecondary, fontSize = 14.sp)
    }
}

private fun Modifier.widthIn48(): Modifier = this.then(Modifier.heightIn(min = 48.dp)).padding(horizontal = 8.dp)

/** The comment count beside it (opens the post page where the comments are). */
@Composable
fun JamCommentCount(post: JamPostInfo, model: JamModel, onClick: () -> Unit, modifier: Modifier = Modifier) {
    val colors = Lime.colors
    val counts = model.countsOf(post.postId)
    val words = if (counts.comments > 0u) stringResource(R.string.jam_comments_count, counts.comments.toInt()) else stringResource(R.string.jam_comment)
    Row(
        modifier.heightIn(min = 48.dp).padding(horizontal = 8.dp).semantics { contentDescription = words; role = Role.Button }.clickable(onClick = onClick).testTag("jam-comment-${post.postId}"),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Icon(Icons.Comment, null, tint = colors.text, modifier = Modifier.size(22.dp))
        if (counts.comments > 0u) Text("${counts.comments}", color = colors.textSecondary, fontSize = 14.sp)
    }
}

/** The post page's response part: "20 likes · 3 comments", a place to leave a comment, and the comments. */
@Composable
fun JamEngagementSection(post: JamPostInfo, model: JamModel, myId: String?, onReportComment: ((JamCommentInfo) -> Unit)? = null) {
    val colors = Lime.colors
    val scope = rememberCoroutineScope()
    var comments by remember { mutableStateOf<List<JamCommentInfo>>(emptyList()) }
    var text by remember { mutableStateOf("") }
    var replyingTo by remember { mutableStateOf<JamCommentInfo?>(null) }
    var failed by remember { mutableStateOf(false) }
    val counts = model.countsOf(post.postId)
    LaunchedEffect(post.postId, counts.comments, counts.likes) { comments = model.comments(post.postId) }
    LaunchedEffect(post.postId) { if (model.isMine(post)) model.markSeen(post.postId) }
    Column(Modifier.fillMaxWidth().testTag("jam-engagement"), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Box(Modifier.fillMaxWidth().size(1.dp).background(colors.hairline))
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            JamHeartButton(post, model)
            val likes = stringResource(R.string.jam_likes_line, counts.likes.toInt()); val cs = stringResource(R.string.jam_comments_line, counts.comments.toInt())
            Text("$likes · $cs", color = colors.textSecondary, fontSize = 14.sp, modifier = Modifier.testTag("jam-counts-line-${post.postId}"))
        }
        replyingTo?.let { target ->
            Row(Modifier.fillMaxWidth().background(colors.surface, RoundedCornerShape(12.dp)).padding(start = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(R.string.jam_replying_to, model.teacherName(target.author)), color = colors.text, fontSize = 13.sp, modifier = Modifier.weight(1f).testTag("jam-reply-bar"))
                TextButton(onClick = { replyingTo = null }, Modifier.heightIn(min = 48.dp)) { Text(stringResource(R.string.group_cancel), color = colors.text) }
            }
        }
        Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedTextField(
                value = text, onValueChange = { text = it.take(2000); failed = false }, modifier = Modifier.weight(1f).heightIn(min = 56.dp).testTag("jam-comment-field"),
                placeholder = { Text(stringResource(R.string.jam_comment_hint), color = colors.textSecondary) }, maxLines = 4, shape = RoundedCornerShape(24.dp),
                colors = OutlinedTextFieldDefaults.colors(focusedTextColor = colors.text, unfocusedTextColor = colors.text, focusedContainerColor = colors.surface, unfocusedContainerColor = colors.surface, focusedBorderColor = colors.text, unfocusedBorderColor = colors.hairline, cursorColor = colors.text),
            )
            val canSend = text.isNotBlank()
            val sendWords = stringResource(R.string.jam_comment_send)
            Box(
                Modifier.size(56.dp).background(if (canSend) colors.accent else colors.pressed, CircleShape)
                    .then(if (canSend) Modifier.clickable(role = Role.Button) {
                        val words = text; val parent = replyingTo?.commentId
                        scope.launch { if (model.comment(post.postId, words, parent)) { text = ""; replyingTo = null; comments = model.comments(post.postId) } else failed = true }
                    } else Modifier)
                    .semantics { contentDescription = sendWords }.testTag("jam-comment-send"),
                contentAlignment = Alignment.Center,
            ) { Icon(Icons.Send, null, tint = if (canSend) colors.accentInk else colors.textSecondary) }
        }
        if (failed) Text(stringResource(R.string.jam_comment_failed), color = colors.danger, fontSize = 14.sp, modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite }.testTag("jam-comment-failed"))
        val tops = comments.filter { it.parentId == null }
        tops.forEach { top ->
            CommentRow(top, model, myId, indent = false, onReply = { replyingTo = top }, onReport = onReportComment) { scope.launch { model.deleteComment(post.postId, it); comments = model.comments(post.postId) } }
            comments.filter { it.parentId == top.commentId }.forEach { reply ->
                CommentRow(reply, model, myId, indent = true, onReply = { replyingTo = top }, onReport = onReportComment) { scope.launch { model.deleteComment(post.postId, it); comments = model.comments(post.postId) } }
            }
        }
    }
}

@Composable
private fun CommentRow(comment: JamCommentInfo, model: JamModel, myId: String?, indent: Boolean, onReply: () -> Unit, onReport: ((JamCommentInfo) -> Unit)?, onDelete: (String) -> Unit) {
    val colors = Lime.colors
    val name = if (comment.mine) stringResource(R.string.jam_you) else model.teacherName(comment.author)
    val pending = comment.state == "pending"
    val spoken = listOfNotNull(name, comment.text, if (pending) stringResource(R.string.jam_pending_words) else null).joinToString(", ")
    Row(
        Modifier.fillMaxWidth().padding(start = if (indent) 32.dp else 0.dp).testTag("jam-comment-row-${comment.commentId}"),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Avatar(initialsOf(name), AvatarTone.tone(comment.author), 32.dp)
        Column(Modifier.weight(1f).semantics(mergeDescendants = true) { contentDescription = spoken }, verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(name, color = colors.text, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
            Text(comment.text, color = if (pending) colors.textSecondary else colors.text, fontSize = 16.sp, modifier = Modifier.testTag("jam-comment-text-${comment.commentId}"))
            if (pending) Text(stringResource(R.string.jam_pending), color = colors.textSecondary, fontSize = 12.sp)
        }
        Column(horizontalAlignment = Alignment.End) {
            if (!pending) TextButton(onClick = onReply, Modifier.heightIn(min = 48.dp).testTag("jam-comment-reply-${comment.commentId}")) { Text(stringResource(R.string.chat_reply), color = colors.text, fontSize = 14.sp) }
            if (!comment.mine && !pending && onReport != null) TextButton(onClick = { onReport(comment) }, Modifier.heightIn(min = 48.dp).testTag("jam-comment-report-${comment.commentId}")) { Text(stringResource(R.string.report_title), color = colors.textSecondary, fontSize = 14.sp) }
            if (comment.mine) TextButton(onClick = { onDelete(comment.commentId) }, Modifier.heightIn(min = 48.dp).testTag("jam-comment-delete-${comment.commentId}")) { Text(stringResource(R.string.message_action_delete), color = colors.danger, fontSize = 14.sp) }
        }
    }
}
