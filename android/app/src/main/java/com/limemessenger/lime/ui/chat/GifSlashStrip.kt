package com.limemessenger.lime.ui.chat

import android.graphics.Bitmap
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.limemessenger.lime.R
import com.limemessenger.lime.chats.ChatsModel
import com.limemessenger.lime.chats.GifFiles
import com.limemessenger.lime.chats.StickerPack
import com.limemessenger.lime.ui.theme.Lime
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import uniffi.lime_core.MyGif
import uniffi.lime_core.OutgoingAttachment
import uniffi.lime_core.StickerEntry

/**
 * The "/" strip (iOS `GIFSlashStrip`, LIME-208): a message that starts with "/" shows, above the field, the GIFs and lime stickers that match the words after it (at most 12 in all):
 * for words typed the stickers come first, for a bare "/" the recent GIFs do. Tapping one sends it and clears the field. Chats only (the composer of a chat).
 */
@Composable
fun GifSlashStrip(chats: ChatsModel, query: String, onPick: (OutgoingAttachment) -> Unit) {
    val colors = Lime.colors
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    val pack = androidx.compose.runtime.remember { StickerPack.entries(context) }
    val stickers = if (StickerPack.shown(context)) uniffi.lime_core.stickerMatching(query, pack, true) else emptyList()
    val gifs by produceState<List<MyGif>?>(null, query) {
        val core = chats.core()
        val keep = if (query.isEmpty()) 12 else maxOf(0, 12 - minOf(12, stickers.size))
        value = if (core == null) emptyList() else withContext(Dispatchers.IO) {
            runCatching { if (query.isEmpty()) core.listMyGifs(12u) else core.searchMyGifs(query, 12u) }.getOrDefault(emptyList()).take(keep)
        }
    }
    val shownStickers = stickers.take(if (query.isEmpty()) maxOf(0, 12 - (gifs?.size ?: 0)) else 12)
    val loaded = gifs
    if (loaded == null) return
    if (loaded.isEmpty() && shownStickers.isEmpty()) {
        Text(
            if (query.isEmpty()) stringResource(R.string.gif_slash_none) else stringResource(R.string.gif_slash_none_for, query), color = colors.textSecondary, fontSize = 14.sp,
            modifier = Modifier.fillMaxWidth().padding(horizontal = 6.dp, vertical = 8.dp).testTag("gif-slash-empty"),
        )
        return
    }
    val stickerCells: List<Any> = shownStickers
    val gifCells: List<Any> = loaded
    val cells = if (query.isNotEmpty()) stickerCells + gifCells else gifCells + stickerCells
    LazyRow(Modifier.fillMaxWidth().padding(top = 8.dp).testTag("gif-slash-strip"), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        items(cells, key = { if (it is MyGif) "g-${it.id}" else "s-${(it as StickerEntry).file}" }) { cell ->
            when (cell) {
                is StickerEntry -> {
                    val label = uniffi.lime_core.stickerLabel(cell.words)
                    val still by produceState<Bitmap?>(null, cell.file) { value = withContext(Dispatchers.IO) { StickerPack.bytes(context, cell.file)?.let { GifFiles.firstFrame(it, 200) } } }
                    Thumb(label, "gif-slash-sticker-${cell.file}", still) { StickerPack.attachment(context, cell)?.let(onPick) }
                }
                is MyGif -> {
                    val words = listOf(cell.words, cell.frameText, cell.messageText).firstOrNull { it.isNotEmpty() }
                    val label = words?.let { stringResource(R.string.gif_my_gif_label, it) } ?: stringResource(R.string.gif_label)
                    val still by produceState<Bitmap?>(null, cell.id) { value = withContext(Dispatchers.IO) { chats.core()?.myGifBytes(cell.id)?.let { GifFiles.firstFrame(it, 200) } } }
                    Thumb(label, "gif-slash-${cell.id}", still) {
                        scope.launch {
                            val bytes = withContext(Dispatchers.IO) { chats.core()?.let { runCatching { it.touchMyGif(cell.id); it.myGifBytes(cell.id) }.getOrNull() } }
                            bytes?.let { GifFiles.attachment(it, "GIF.gif").getOrNull() }?.let(onPick)
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun Thumb(label: String, tag: String, still: Bitmap?, onClick: () -> Unit) {
    val colors = Lime.colors
    Box(
        Modifier.size(72.dp).clip(RoundedCornerShape(12.dp)).background(colors.chip).semantics { contentDescription = label; role = Role.Button }.clickable(onClick = onClick).testTag(tag),
    ) { still?.let { Image(it.asImageBitmap(), null, contentScale = ContentScale.Crop, modifier = Modifier.size(72.dp)) } }
}
