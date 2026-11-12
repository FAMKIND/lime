package com.limemessenger.lime.ui.chat

import android.graphics.Bitmap
import android.graphics.ImageDecoder
import android.graphics.drawable.AnimatedImageDrawable
import android.os.Build
import android.widget.ImageView
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import com.limemessenger.lime.R
import com.limemessenger.lime.chats.ChatsModel
import com.limemessenger.lime.chats.GifFiles
import com.limemessenger.lime.chats.StickerPack
import com.limemessenger.lime.ui.theme.Lime
import java.nio.ByteBuffer
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import uniffi.lime_core.MyGif
import uniffi.lime_core.OutgoingAttachment
import uniffi.lime_core.StickerEntry

/**
 * The GIF panel (iOS `ComposerPanel` GIF part): **My GIFs** (3 columns: added from the system file picker with words the person types, searched by those words, removed) and **lime's
 * stickers** (4 columns, searched). Tapping one sends it as a GIF. Emoji stay the system keyboard's. A still frame in every grid cell (it never animates there).
 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
@Composable
fun GifPanel(chats: ChatsModel, onSend: (OutgoingAttachment) -> Unit, onDismiss: () -> Unit) {
    val colors = Lime.colors
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    val stickersAllowed = remember { StickerPack.shown(context) }
    var stickers by remember { mutableStateOf(stickersAllowed) }
    var query by remember { mutableStateOf("") }
    var version by remember { mutableIntStateOf(0) }
    var adding by remember { mutableStateOf<ByteArray?>(null) }
    var managing by remember { mutableStateOf<MyGif?>(null) }
    var problem by remember { mutableStateOf<String?>(null) }
    val pack = remember { StickerPack.entries(context) }
    val saveFailed = stringResource(R.string.gif_save_failed)
    val mine by produceState(emptyList<MyGif>(), query, version, stickers) {
        val core = chats.core()
        value = if (core == null || stickers) emptyList() else withContext(Dispatchers.IO) {
            runCatching { if (query.isBlank()) core.listMyGifs(200u) else core.searchMyGifs(query, 200u) }.getOrDefault(emptyList())
        }
    }
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.GetContent()) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        scope.launch {
            val bytes = withContext(Dispatchers.IO) { runCatching { context.contentResolver.openInputStream(uri)?.use { it.readBytes() } }.getOrNull() }
            val refused = bytes?.let { uniffi.lime_core.gifProblem(it) } ?: saveFailed
            if (bytes != null && uniffi.lime_core.gifProblem(bytes) == null) adding = bytes else problem = refused
        }
    }
    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = colors.canvas) {
        Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp).padding(bottom = 16.dp).testTag("gif-panel"), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Tab(stringResource(R.string.gif_tab_gifs), !stickers, "gif-tab-gifs") { stickers = false }
                if (stickersAllowed) Tab(stringResource(R.string.gif_tab_stickers), stickers, "gif-tab-stickers") { stickers = true }
            }
            OutlinedTextField(
                value = query, onValueChange = { query = it.take(80) }, singleLine = true, modifier = Modifier.fillMaxWidth().testTag("gif-search"),
                placeholder = { Text(stringResource(R.string.gif_search), color = colors.textSecondary) },
            )
            problem?.let { Text(it, color = colors.danger, fontSize = 14.sp, modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite }.testTag("gif-problem")) }
            if (stickers) {
                val shown = uniffi.lime_core.stickerMatching(query, pack, true)
                if (shown.isEmpty()) Text(stringResource(R.string.gif_sticker_none), color = colors.textSecondary, fontSize = 15.sp, modifier = Modifier.padding(24.dp).testTag("gif-sticker-none"))
                LazyVerticalGrid(GridCells.Fixed(4), Modifier.heightIn(max = 420.dp), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    items(shown, key = { it.file }) { sticker ->
                        val label = uniffi.lime_core.stickerLabel(sticker.words)
                        val still by produceState<Bitmap?>(null, sticker.file) { value = withContext(Dispatchers.IO) { StickerPack.bytes(context, sticker.file)?.let { GifFiles.firstFrame(it, 200) } } }
                        Cell(label, "gif-sticker-${sticker.file}", onClick = { StickerPack.attachment(context, sticker)?.let(onSend) }) { still?.let { Image(it.asImageBitmap(), null, contentScale = ContentScale.Fit, modifier = Modifier.fillMaxSize()) } }
                    }
                }
            } else {
                LazyVerticalGrid(GridCells.Fixed(3), Modifier.heightIn(max = 420.dp), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    item(key = "add") {
                        val words = stringResource(R.string.gif_add)
                        Box(
                            Modifier.aspectRatio(1f).background(colors.chip, RoundedCornerShape(12.dp)).semantics { contentDescription = words; role = Role.Button }.clickable { problem = null; picker.launch("image/gif") }.testTag("gif-add"),
                            contentAlignment = Alignment.Center,
                        ) { Text("+", color = colors.text, fontSize = 32.sp) }
                    }
                    items(mine, key = { it.id }) { gif ->
                        val label = if (gif.words.isNotBlank()) stringResource(R.string.gif_my_gif_label, gif.words) else stringResource(R.string.gif_label)
                        val still by produceState<Bitmap?>(null, gif.id) { value = withContext(Dispatchers.IO) { chats.core()?.myGifBytes(gif.id)?.let { GifFiles.firstFrame(it, 300) } } }
                        val removeWords = stringResource(R.string.gif_remove)
                        Cell(
                            label, "gif-mine-${gif.id}",
                            onClick = {
                                scope.launch {
                                    val bytes = withContext(Dispatchers.IO) { chats.core()?.let { runCatching { it.touchMyGif(gif.id); it.myGifBytes(gif.id) }.getOrNull() } }
                                    bytes?.let { GifFiles.attachment(it, "GIF.gif").getOrNull() }?.let(onSend)
                                }
                            },
                            onLongClick = { managing = gif },
                            actions = listOf(CustomAccessibilityAction(removeWords) { managing = gif; true }),
                        ) { still?.let { Image(it.asImageBitmap(), null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize()) } }
                    }
                }
                if (mine.isEmpty() && version >= 0) Text(stringResource(R.string.gif_none), color = colors.textSecondary, fontSize = 15.sp, modifier = Modifier.testTag("gif-none"))
            }
        }
    }
    adding?.let { bytes ->
        var words by remember { mutableStateOf("") }
        AlertDialog(
            onDismissRequest = { adding = null }, containerColor = colors.canvas,
            title = { Text(stringResource(R.string.gif_words_title), color = colors.text) },
            text = { OutlinedTextField(words, { words = it.take(200) }, modifier = Modifier.fillMaxWidth().testTag("gif-words-field"), placeholder = { Text(stringResource(R.string.gif_words_hint), color = colors.textSecondary) }, maxLines = 3) },
            confirmButton = {
                TextButton({
                    val info = uniffi.lime_core.gifInspect(bytes)
                    adding = null
                    scope.launch {
                        val ok = withContext(Dispatchers.IO) { runCatching { chats.core()!!.addMyGif(bytes, words.trim(), "", "", info?.width, info?.height) }.isSuccess }
                        if (ok) version++ else problem = saveFailed
                    }
                }, Modifier.heightIn(min = 48.dp).testTag("gif-words-save")) { Text(stringResource(R.string.gif_save), color = colors.text, fontWeight = FontWeight.SemiBold) }
            },
            dismissButton = { TextButton({ adding = null }, Modifier.heightIn(min = 48.dp)) { Text(stringResource(R.string.jam_cancel), color = colors.text) } },
        )
    }
    managing?.let { gif ->
        var words by remember(gif.id) { mutableStateOf(gif.words) }
        AlertDialog(
            onDismissRequest = { managing = null }, containerColor = colors.canvas,
            title = { Text(stringResource(R.string.gif_words_title), color = colors.text) },
            text = { OutlinedTextField(words, { words = it.take(200) }, modifier = Modifier.fillMaxWidth().testTag("gif-edit-field"), maxLines = 3) },
            confirmButton = {
                TextButton({ managing = null; scope.launch { withContext(Dispatchers.IO) { runCatching { chats.core()?.setMyGifWords(gif.id, words.trim()) } }; version++ } }, Modifier.heightIn(min = 48.dp).testTag("gif-edit-save")) { Text(stringResource(R.string.gif_save), color = colors.text, fontWeight = FontWeight.SemiBold) }
            },
            dismissButton = {
                TextButton({ managing = null; scope.launch { withContext(Dispatchers.IO) { runCatching { chats.core()?.removeMyGif(gif.id) } }; version++ } }, Modifier.heightIn(min = 48.dp).testTag("gif-remove-${gif.id}")) { Text(stringResource(R.string.gif_remove), color = colors.danger) }
            },
        )
    }
}

@Composable
private fun Tab(title: String, on: Boolean, tag: String, onClick: () -> Unit) {
    val colors = Lime.colors
    Box(
        Modifier.heightIn(min = 48.dp).background(if (on) colors.pressed else colors.chip, RoundedCornerShape(24.dp)).semantics(mergeDescendants = true) { selected = on; role = Role.RadioButton }.clickable(onClick = onClick).padding(horizontal = 18.dp).testTag(tag),
        contentAlignment = Alignment.Center,
    ) { Text(title, color = colors.text, fontSize = 15.sp, fontWeight = if (on) FontWeight.Bold else FontWeight.Normal) }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun Cell(label: String, tag: String, onClick: () -> Unit, onLongClick: (() -> Unit)? = null, actions: List<CustomAccessibilityAction> = emptyList(), content: @Composable () -> Unit) {
    val colors = Lime.colors
    Box(
        Modifier.aspectRatio(1f).clip(RoundedCornerShape(12.dp)).background(colors.chip)
            .semantics { contentDescription = label; role = Role.Button; if (actions.isNotEmpty()) customActions = actions }
            .combinedClickable(onClick = onClick, onLongClick = onLongClick).testTag(tag),
    ) { content() }
}

/** A GIF in a bubble: it plays (API 28+, the platform's own decoder) unless the system's animations are off, then it is its first frame with a Play button; a Stop/Play button always. */
@Composable
fun GifThumb(bytes: ByteArray?, still: androidx.compose.ui.graphics.ImageBitmap?, ratio: Float, description: String, tag: String, onOpen: () -> Unit) {
    val colors = Lime.colors
    val context = LocalContext.current
    val off = remember { GifFiles.animationsOff(context) }
    var playing by remember { mutableStateOf(!off) }
    val canAnimate = Build.VERSION.SDK_INT >= Build.VERSION_CODES.P && bytes != null
    val drawable by produceState<android.graphics.drawable.Drawable?>(null, bytes, canAnimate) {
        value = if (!canAnimate || bytes == null || Build.VERSION.SDK_INT < Build.VERSION_CODES.P) null else withContext(Dispatchers.IO) { runCatching { decodeAnimated(bytes) }.getOrNull() }
    }
    LaunchedEffect(drawable, playing) { if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) setPlaying(drawable, playing) }
    val play = stringResource(R.string.gif_play); val stop = stringResource(R.string.gif_stop)
    Box(Modifier.size(width = 240.dp, height = (240f / ratio).dp).clip(RoundedCornerShape(14.dp)).background(colors.chip)) {
        Box(Modifier.fillMaxSize().semantics { contentDescription = description; role = Role.Image }.clickable(onClick = onOpen).testTag(tag)) {
            val d = drawable
            if (d != null) AndroidView(factory = { ImageView(it).apply { scaleType = ImageView.ScaleType.CENTER_CROP } }, update = { it.setImageDrawable(d) }, modifier = Modifier.fillMaxSize())
            else still?.let { Image(it, null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize()) }
        }
        if (canAnimate) Box(
            Modifier.align(Alignment.BottomEnd).size(48.dp).semantics { contentDescription = if (playing) stop else play; role = Role.Button }.clickable { playing = !playing }.testTag("$tag-toggle"),
            contentAlignment = Alignment.Center,
        ) { Text(if (playing) "❚❚" else "▶", color = androidx.compose.ui.graphics.Color.White, fontSize = 14.sp, modifier = Modifier.background(androidx.compose.ui.graphics.Color(0x99000000), RoundedCornerShape(12.dp)).padding(horizontal = 8.dp, vertical = 4.dp)) }
    }
}

/** The platform's animated-image decoder (API 28+; below it a GIF shows its first frame). */
@androidx.annotation.RequiresApi(Build.VERSION_CODES.P)
private fun decodeAnimated(bytes: ByteArray): android.graphics.drawable.Drawable = ImageDecoder.decodeDrawable(ImageDecoder.createSource(ByteBuffer.wrap(bytes)))

@androidx.annotation.RequiresApi(Build.VERSION_CODES.P)
private fun setPlaying(drawable: android.graphics.drawable.Drawable?, playing: Boolean) {
    (drawable as? AnimatedImageDrawable)?.let { if (playing) { it.repeatCount = AnimatedImageDrawable.REPEAT_INFINITE; it.start() } else it.stop() }
}
