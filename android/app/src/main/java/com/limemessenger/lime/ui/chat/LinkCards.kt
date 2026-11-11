package com.limemessenger.lime.ui.chat

import android.graphics.BitmapFactory
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.testTag
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.limemessenger.lime.R
import com.limemessenger.lime.chats.ChatModel
import com.limemessenger.lime.chats.LinkPreviewFetcher
import com.limemessenger.lime.ui.shell.Icons
import com.limemessenger.lime.ui.theme.Lime
import uniffi.lime_core.LinkPreview
import uniffi.lime_core.OutgoingPreview

/** The fetcher the composer uses to make a card (tests provide a fake one: no real internet in the automated tests). */
val LocalLinkPreviewFetcher = staticCompositionLocalOf { LinkPreviewFetcher() }

/** The card being made for the link in the message, above the field inside the composer's card: the picture, the title, the site, and a ✕ that drops it (iOS's draft card). */
@Composable
fun LinkDraftCard(preview: OutgoingPreview, onRemove: () -> Unit) {
    val colors = Lime.colors
    val picture = remember(preview.image) { preview.image.takeIf { it.isNotEmpty() }?.let { BitmapFactory.decodeByteArray(it, 0, it.size)?.asImageBitmap() } }
    val remove = stringResource(R.string.link_draft_remove)
    val label = stringResource(R.string.link_card_label, preview.title, preview.site)
    Row(
        Modifier.fillMaxWidth().padding(top = 8.dp).background(colors.chip, RoundedCornerShape(14.dp)).padding(start = 8.dp).testTag("link-draft"),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Row(Modifier.weight(1f).padding(vertical = 8.dp).semantics(mergeDescendants = true) { contentDescription = label }, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            if (picture != null) Image(picture, null, contentScale = ContentScale.Crop, modifier = Modifier.size(56.dp).clip(RoundedCornerShape(10.dp)))
            Column(Modifier.weight(1f)) {
                Text(preview.title, color = colors.text, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, maxLines = 2, modifier = Modifier.testTag("link-draft-title"))
                Text(preview.site, color = colors.textSecondary, fontSize = 13.sp, maxLines = 1, modifier = Modifier.testTag("link-draft-site"))
            }
        }
        Box(Modifier.size(48.dp).semantics { contentDescription = remove; role = Role.Button }.clickable(onClick = onRemove).testTag("link-draft-remove"), contentAlignment = Alignment.Center) {
            Icon(Icons.Close, null, tint = colors.text, modifier = Modifier.size(20.dp))
        }
    }
}

/**
 * A card in a message bubble (iOS `MessageLinkCard`): the picture (an encrypted attachment, fetched like a photo: **this phone never visits the link or the site to draw it**), the page's
 * title and the site. One TalkBack stop, "Link: <title>, <site>". Tapping opens the link: an https one at once; any other (a card made by another app) asks first, as iOS.
 */
@Composable
fun LinkCard(messageId: String, preview: LinkPreview, own: Boolean, model: ChatModel, modifier: Modifier = Modifier) {
    val colors = Lime.colors
    val uri = LocalUriHandler.current
    var asking by remember { mutableStateOf(false) }
    val image = preview.image
    LaunchedEffect(image?.id) { if (image != null) model.loadImage(image) }
    val bitmap = image?.let { model.images[it.id] }
    val label = stringResource(R.string.link_card_label, preview.title, preview.site)
    val shape = RoundedCornerShape(16.dp)
    Column(
        modifier.width(248.dp).clip(shape).background(colors.surface).border(0.8.dp, colors.hairline, shape)
            .clickable { if (preview.url.startsWith("https://", ignoreCase = true)) uri.openUri(preview.url) else asking = true }
            .clearAndSetSemantics { contentDescription = label; role = Role.Button; testTag = "link-card-$messageId" },
    ) {
        if (bitmap != null) Image(bitmap, null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxWidth().aspectRatio(1.9f))
        Column(Modifier.padding(horizontal = 12.dp, vertical = 9.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(preview.title, color = colors.text, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, maxLines = 2)
            Text(preview.site, color = colors.textSecondary, fontSize = 13.sp, maxLines = 1)
        }
    }
    if (asking) AlertDialog(
        onDismissRequest = { asking = false }, containerColor = colors.canvas,
        title = { Text(stringResource(R.string.link_open_title), color = colors.text) },
        text = { Text(stringResource(R.string.link_open_body, preview.url), color = colors.textSecondary) },
        confirmButton = { TextButton({ asking = false; uri.openUri(preview.url) }, Modifier.heightIn(min = 48.dp).testTag("link-open-confirm")) { Text(stringResource(R.string.link_open), color = colors.text, fontWeight = FontWeight.SemiBold) } },
        dismissButton = { TextButton({ asking = false }, Modifier.heightIn(min = 48.dp)) { Text(stringResource(R.string.report_cancel), color = colors.text) } },
    )
}
