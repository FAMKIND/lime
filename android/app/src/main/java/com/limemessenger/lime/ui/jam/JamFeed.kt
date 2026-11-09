package com.limemessenger.lime.ui.jam

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

/** The jam tab: the posts of the jams I follow and my own, newest first, read only (iOS `JamPage`'s feed and `JamPostCard`). Tapping a post reads it. */
@androidx.compose.material3.ExperimentalMaterial3Api
@Composable
fun JamFeedScreen(model: JamModel, modifier: Modifier = Modifier, onOpen: (JamPostInfo) -> Unit) {
    val colors = Lime.colors
    val scope = rememberCoroutineScope()
    var refreshing by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { model.reload() }
    Column(modifier.fillMaxSize().background(colors.canvas)) {
        Row(Modifier.fillMaxWidth().heightIn(min = 64.dp).padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(stringResource(R.string.tab_jam), color = colors.text, fontSize = 28.sp, fontWeight = FontWeight.Bold, modifier = Modifier.semantics { heading() })
        }
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
                }
                items(model.posts, key = { it.postId }) { post -> PostCard(post, model) { onOpen(post) } }
            }
        }
    }
}

/** A post as a card: the byline (avatar, name, "by …", date), then the title and the first words. One TalkBack stop that opens the post. */
@Composable
private fun PostCard(post: JamPostInfo, model: JamModel, onOpen: () -> Unit) {
    val colors = Lime.colors
    val name = model.authorName(post)
    val writer = model.teacherName(post.author)
    val asJam = post.displayAs == "jam"
    val detail = listOfNotNull(model.byline(post), JamDates.short(post.created), if (post.editedAt > 0) "Edited" else null).joinToString(" · ")
    val spoken = listOfNotNull(
        if (asJam) "$name, by $writer" else name, JamDates.spoken(post.created), post.title.ifEmpty { null }, JamModel.excerpt(post, 120).ifEmpty { null },
    ).joinToString(", ")
    Column(
        Modifier.fillMaxWidth().clickable(onClick = onOpen).padding(horizontal = 20.dp, vertical = 14.dp)
            .semantics { contentDescription = spoken; role = Role.Button }.testTag("jam-post-${post.postId}"),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Row(Modifier.clearAndSetSemantics { }, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Avatar(initialsOf(name), AvatarTone.tone(if (asJam) post.jamId else post.author), 40.dp)
            Column(Modifier.weight(1f)) {
                Text(name, color = colors.text, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(if (asJam) "by $writer · $detail" else detail, color = colors.textSecondary, fontSize = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
        Column(Modifier.clearAndSetSemantics { }, verticalArrangement = Arrangement.spacedBy(4.dp)) {
            if (post.title.isNotEmpty()) Text(post.title, color = colors.text, fontSize = 19.sp, fontWeight = FontWeight.Bold, maxLines = 3, overflow = TextOverflow.Ellipsis)
            val excerpt = JamModel.excerpt(post, if (post.kind == "quick") 400 else 200)
            if (excerpt.isNotEmpty()) Text(excerpt, color = if (post.kind == "article") colors.textSecondary else colors.text, fontSize = 16.sp, maxLines = if (post.kind == "quick") 8 else 3, overflow = TextOverflow.Ellipsis)
        }
    }
    Box(Modifier.fillMaxWidth().size(1.dp).background(colors.hairline))
}

/** Reading one post (the core's post Markdown: paragraphs, headings, lists, quotes, code; pictures are not shown yet). */
@Composable
fun JamReaderScreen(post: JamPostInfo, model: JamModel, onBack: () -> Unit) {
    val colors = Lime.colors
    Column(Modifier.fillMaxSize().background(colors.canvas).systemBarsPadding()) {
        Row(Modifier.fillMaxWidth().heightIn(min = 64.dp), verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = onBack, Modifier.size(56.dp).testTag("jam-reader-back")) { Icon(Icons.Back, stringResource(R.string.chat_back), tint = colors.text) }
        }
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 20.dp, vertical = 8.dp).testTag("jam-reader"), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            if (post.title.isNotEmpty()) Text(post.title, color = colors.text, fontSize = 28.sp, lineHeight = 34.sp, fontWeight = FontWeight.Bold, modifier = Modifier.semantics { heading() })
            if (post.subtitle.isNotEmpty()) Text(post.subtitle, color = colors.textSecondary, fontSize = 18.sp)
            val detail = listOfNotNull(model.authorName(post), model.byline(post), JamDates.short(post.created), if (post.editedAt > 0) "Edited" else null).joinToString(" · ")
            Text(detail, color = colors.textSecondary, fontSize = 14.sp, modifier = Modifier.testTag("jam-reader-byline"))
            MessageText(post.markdown, color = colors.text, linkColor = colors.link, post = true, fontSize = 18f)
        }
    }
}
