package com.limemessenger.lime.ui.jam

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.compose.ui.semantics.selected
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.ui.draw.clip
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.limemessenger.lime.R
import com.limemessenger.lime.chats.AttachmentProcessing
import com.limemessenger.lime.jam.JamDrafts
import com.limemessenger.lime.jam.JamModel
import com.limemessenger.lime.ui.onboarding.PrimaryButton
import com.limemessenger.lime.ui.shell.Icons
import com.limemessenger.lime.ui.theme.Lime
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import uniffi.lime_core.JamPostInfo
import uniffi.lime_core.OutgoingAttachment

/** Where the writing screens are: the drafts list opens a draft, the buttons start a new one, the reader's Edit edits a post. */
class ComposeRoute(val kind: String, val draftId: String? = null, val editing: JamPostInfo? = null)

/**
 * Your jam (iOS `CreatePublication` and the profile's jam): create it (name, about, topics), then write a post or an article, open a draft, see the subscribers and
 * remove one, edit the jam or end it. One lime button on the screen: Create, or Write a post.
 */
@Composable
fun YourJamScreen(model: JamModel, drafts: JamDrafts, onBack: () -> Unit, onCompose: (ComposeRoute) -> Unit, onOpenBand: ((String) -> Unit)? = null) {
    val colors = Lime.colors
    val scope = rememberCoroutineScope()
    val jam = model.mine()
    var editing by remember { mutableStateOf(false) }
    var confirmEnd by remember { mutableStateOf(false) }
    var removing by remember { mutableStateOf<uniffi.lime_core.JamSubscriberInfo?>(null) }
    var draftList by remember { mutableStateOf(drafts.list()) }
    var subscribers by remember { mutableStateOf(emptyList<uniffi.lime_core.JamSubscriberInfo>()) }
    LaunchedEffect(jam?.jamId, model.reloads) { subscribers = jam?.let { model.subscribers(it.jamId) }.orEmpty().filter { it.status == "active" } }
    LaunchedEffect(Unit) { draftList = drafts.list() }
    Column(Modifier.fillMaxSize().background(colors.canvas).systemBarsPadding().imePadding().testTag("jam-yours")) {
        var switching by remember { mutableStateOf(false) }
        var creatingBand by remember { mutableStateOf(false) }
        Row(Modifier.fillMaxWidth().heightIn(min = 64.dp), verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = onBack, Modifier.size(56.dp).testTag("jam-yours-back")) { Icon(Icons.Back, stringResource(R.string.chat_back), tint = colors.text) }
            Text(stringResource(R.string.jam_yours), color = colors.text, fontSize = 22.sp, fontWeight = FontWeight.Bold, modifier = Modifier.semantics { heading() })
            // Only when there is more than one jam: a pill with the current jam's name that opens the list (LIME-315a).
            if (model.myJams.size > 1 && jam != null) {
                Spacer(Modifier.weight(1f))
                val switchWords = stringResource(R.string.jam_switch_words, jam.title)
                Row(
                    Modifier.padding(end = 12.dp).heightIn(min = 48.dp).clip(RoundedCornerShape(24.dp)).background(colors.surface).clickable { switching = true }
                        .semantics { contentDescription = switchWords; role = Role.Button }.padding(horizontal = 14.dp).testTag("jam-switcher"),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    Text(jam.title, color = colors.text, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, modifier = Modifier.widthIn(max = 160.dp))
                    Text("\u25BE", color = colors.textSecondary, fontSize = 14.sp)
                }
            }
        }
        if (switching) JamSwitcherSheet(model, onDismiss = { switching = false })
        if (creatingBand) CreateBandScreen(model, onClose = { creatingBand = false })
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 20.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            if (jam != null) JamSendProgressLine(jam.jamId, model)
            if (jam != null && !editing) JamPictureSection(jam, model)
            if (jam == null || editing) {
                if (jam == null) Text(stringResource(R.string.jam_create_intro), color = colors.textSecondary, fontSize = 16.sp)
                var title by remember(jam?.jamId) { mutableStateOf(jam?.title.orEmpty()) }
                var about by remember(jam?.jamId) { mutableStateOf(jam?.about.orEmpty()) }
                var topics by remember(jam?.jamId) { mutableStateOf(jam?.topics?.joinToString(", ").orEmpty()) }
                var failed by remember { mutableStateOf(false) }
                Field(title, { title = it.take(60) }, stringResource(R.string.jam_field_title), "jam-create-title", singleLine = true)
                Field(about, { about = it.take(500) }, stringResource(R.string.jam_field_about), "jam-create-about", minLines = 3)
                Field(topics, { topics = it.take(240) }, stringResource(R.string.jam_field_topics), "jam-create-topics", singleLine = true)
                if (failed) Text(stringResource(R.string.jam_post_failed), color = colors.danger, fontSize = 14.sp, modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite })
                PrimaryButton(
                    stringResource(if (jam == null) R.string.jam_create else R.string.jam_save_changes),
                    {
                        scope.launch {
                            val list = topics.split(",").map { it.trim() }.filter { it.isNotEmpty() }.take(8)
                            val ok = if (jam == null) model.createJam(title, about, list) else model.updateJam(jam.jamId, title, about, list)
                            failed = !ok
                            if (ok) editing = false
                        }
                    },
                    Modifier.testTag("jam-create"), enabled = title.isNotBlank(),
                )
            } else {
                Text(jam.title, color = colors.text, fontSize = 24.sp, fontWeight = FontWeight.Bold, modifier = Modifier.semantics { heading() }.testTag("jam-yours-title"))
                if (jam.about.isNotEmpty()) Text(jam.about, color = colors.textSecondary, fontSize = 16.sp)
                if (onOpenBand != null && model.isBand(jam)) OutlineButton(stringResource(R.string.band_open_page), "band-open-page") { onOpenBand(jam.jamId) }
                TextButton({ editing = true }, Modifier.heightIn(min = 48.dp).testTag("jam-yours-edit")) { Text(stringResource(R.string.jam_edit_jam), color = colors.text) }
                PrimaryButton(stringResource(R.string.jam_write_post), { onCompose(ComposeRoute("quick")) }, Modifier.testTag("jam-write-post"))
                OutlineButton(stringResource(R.string.jam_write_article), "jam-write-article") { onCompose(ComposeRoute("article")) }
                OutlineButton(stringResource(R.string.band_create), "band-create-open") { creatingBand = true }
                if (draftList.isNotEmpty()) {
                    Section(stringResource(R.string.jam_drafts))
                    draftList.forEach { d ->
                        Row(Modifier.fillMaxWidth().heightIn(min = 56.dp), verticalAlignment = Alignment.CenterVertically) {
                            val name = d.headline.ifEmpty { stringResource(R.string.jam_draft_untitled) }
                            Text(name, color = colors.text, fontSize = 16.sp, maxLines = 2, modifier = Modifier.weight(1f).heightIn(min = 48.dp).clickable { onCompose(ComposeRoute(d.kind, d.id)) }.padding(vertical = 12.dp).testTag("jam-draft-${d.id}"))
                            val deleteDraft = stringResource(R.string.jam_draft_delete)
                            TextButton({ drafts.delete(d.id); draftList = drafts.list() }, Modifier.heightIn(min = 48.dp).semantics { contentDescription = "$deleteDraft, $name" }) { Text(stringResource(R.string.jam_delete_confirm), color = colors.danger) }
                        }
                    }
                }
                Section(stringResource(R.string.jam_subscribers))
                if (subscribers.isEmpty()) Text(stringResource(R.string.jam_subscribers_none), color = colors.textSecondary, fontSize = 15.sp, modifier = Modifier.testTag("jam-subscribers-none"))
                subscribers.forEach { s ->
                    val name = s.name.ifEmpty { s.userId.take(8) }
                    val removeWords = stringResource(R.string.jam_subscriber_remove)
                    Row(Modifier.fillMaxWidth().heightIn(min = 56.dp).testTag("jam-subscriber-${s.userId}"), verticalAlignment = Alignment.CenterVertically) {
                        Text(name, color = colors.text, fontSize = 16.sp, modifier = Modifier.weight(1f))
                        TextButton({ removing = s }, Modifier.heightIn(min = 48.dp).semantics { contentDescription = "$removeWords $name" }.testTag("jam-sub-remove-${s.userId}")) {
                            Text(stringResource(R.string.jam_subscriber_remove), color = colors.danger)
                        }
                    }
                }
                Spacer(Modifier.size(12.dp))
                TextButton({ confirmEnd = true }, Modifier.heightIn(min = 48.dp).testTag("jam-end")) { Text(stringResource(R.string.jam_end), color = colors.danger) }
            }
        }
    }
    removing?.let { s ->
        val name = s.name.ifEmpty { s.userId.take(8) }
        AlertDialog(
            onDismissRequest = { removing = null }, containerColor = colors.canvas,
            title = { Text(stringResource(R.string.jam_subscriber_remove_title, name), color = colors.text) },
            text = { Text(stringResource(R.string.jam_subscriber_remove_body), color = colors.textSecondary) },
            confirmButton = { TextButton({ val j = jam; removing = null; if (j != null) scope.launch { model.removeSubscriber(j.jamId, s.userId); subscribers = model.subscribers(j.jamId).filter { it.status == "active" } } }, Modifier.heightIn(min = 48.dp).testTag("jam-sub-remove-confirm")) { Text(stringResource(R.string.jam_subscriber_remove), color = colors.danger) } },
            dismissButton = { TextButton({ removing = null }, Modifier.heightIn(min = 48.dp)) { Text(stringResource(R.string.jam_cancel), color = colors.text) } },
        )
    }
    if (confirmEnd && jam != null) AlertDialog(
        onDismissRequest = { confirmEnd = false }, containerColor = colors.canvas,
        title = { Text(stringResource(R.string.jam_end_title), color = colors.text) },
        text = { Text(stringResource(R.string.jam_end_body), color = colors.textSecondary) },
        confirmButton = { TextButton({ confirmEnd = false; scope.launch { model.endJam(jam.jamId) } }, Modifier.heightIn(min = 48.dp).testTag("jam-end-confirm")) { Text(stringResource(R.string.jam_end_confirm), color = colors.danger) } },
        dismissButton = { TextButton({ confirmEnd = false }, Modifier.heightIn(min = 48.dp)) { Text(stringResource(R.string.jam_cancel), color = colors.text) } },
    )
}

@Composable
private fun Section(title: String) {
    Text(title, color = Lime.colors.text, fontSize = 18.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(top = 8.dp).semantics { heading() })
}

@Composable
private fun Field(value: String, onChange: (String) -> Unit, label: String, tag: String, singleLine: Boolean = false, minLines: Int = 1) {
    val colors = Lime.colors
    OutlinedTextField(
        value = value, onValueChange = onChange, label = { Text(label, color = colors.textSecondary) }, singleLine = singleLine, minLines = minLines,
        modifier = Modifier.fillMaxWidth().heightIn(min = 56.dp).testTag(tag),
    )
}

/** A quiet second button (not lime): the lime one is the screen's one main action. */
@Composable
private fun OutlineButton(title: String, tag: String, onClick: () -> Unit) {
    val colors = Lime.colors
    Box(
        Modifier.fillMaxWidth().heightIn(min = 52.dp).background(colors.chip, RoundedCornerShape(26.dp)).clickable(role = Role.Button, onClick = onClick).testTag(tag),
        contentAlignment = Alignment.Center,
    ) { Text(title, color = colors.text, fontSize = 17.sp, fontWeight = FontWeight.SemiBold) }
}

private class PhotoDraft(var attachment: OutgoingAttachment, val preview: ImageBitmap?)

/**
 * Writing a post or an article (iOS `JamComposeSheet`), then step 2, "Before you post / publish" (iOS `BeforePublish`): who can read it (subscribers: the choices for open posts
 * are not on Android), then Post, Publish or Update with a working state. A post is words and up to 10 photos each with an Alt description; an article has a title, a
 * subtitle and a body with a toolbar (bold, italic, heading, list, link, photo). Going back keeps a draft on this phone; editing changes the words of a sent post.
 */
@Composable
fun JamComposeScreen(model: JamModel, drafts: JamDrafts, route: ComposeRoute, onDone: () -> Unit) {
    val colors = Lime.colors
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    val article = route.kind == "article"
    val editing = route.editing
    val start = remember { route.draftId?.let { drafts.read(it) } }
    val draftId = remember { route.draftId ?: java.util.UUID.randomUUID().toString() }
    var title by remember { mutableStateOf(editing?.title ?: start?.title.orEmpty()) }
    var subtitle by remember { mutableStateOf(editing?.subtitle ?: start?.subtitle.orEmpty()) }
    var body by remember { mutableStateOf(TextFieldValue(editing?.markdown ?: start?.words.orEmpty())) }
    val photos = remember { mutableStateListOf<PhotoDraft>() }
    var step by remember { mutableStateOf(1) }
    var postAsId by remember { mutableStateOf<String?>(null) }
    var working by remember { mutableStateOf(false) }
    var problem by remember { mutableStateOf<String?>(null) }
    var describing by remember { mutableStateOf<PhotoDraft?>(null) }
    LaunchedEffect(Unit) {
        start?.let { d -> drafts.photos(d).forEach { a -> photos.add(PhotoDraft(a, withContext(Dispatchers.Default) { AttachmentProcessing.decodeForDisplay(a.bytes, 400) }?.asImageBitmap())) } }
    }
    val failed = stringResource(R.string.jam_post_failed)
    val maxPhotos = 10

    fun hasContent() = body.text.isNotBlank() || photos.isNotEmpty() || title.isNotBlank()
    fun keepDraftAndLeave() {
        if (editing == null) { if (hasContent()) drafts.save(draftId, route.kind, title, subtitle, body.text, photos.map { it.attachment }) else drafts.delete(draftId) }
        onDone()
    }
    androidx.activity.compose.BackHandler(enabled = !working) { if (step == 2) step = 1 else keepDraftAndLeave() }

    val picker = rememberLauncherForActivityResult(ActivityResultContracts.PickMultipleVisualMedia(maxPhotos)) { uris ->
        scope.launch {
            for (uri in uris) {
                if (photos.size >= maxPhotos) break
                val made = withContext(Dispatchers.IO) { AttachmentProcessing.photo(context.contentResolver, uri) } ?: continue
                val preview = withContext(Dispatchers.Default) { AttachmentProcessing.decodeForDisplay(made.bytes, 400) }?.asImageBitmap()
                photos.add(PhotoDraft(made, preview))
                if (article) {   // an article puts the photo in its text, where the cursor is
                    val at = body.selection.start.coerceIn(0, body.text.length)
                    val ref = "\n\n![](attachment:${photos.size - 1})\n\n"
                    body = TextFieldValue(body.text.substring(0, at) + ref + body.text.substring(at), TextRange(at + ref.length))
                }
            }
        }
    }

    Column(Modifier.fillMaxSize().background(colors.canvas).systemBarsPadding().imePadding().testTag("jam-compose")) {
        Row(Modifier.fillMaxWidth().heightIn(min = 64.dp), verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = { if (step == 2) step = 1 else keepDraftAndLeave() }, Modifier.size(56.dp).testTag("jam-compose-back"), enabled = !working) { Icon(Icons.Back, stringResource(R.string.chat_back), tint = colors.text) }
            Text(
                stringResource(if (editing != null) R.string.jam_compose_edit else if (article) R.string.jam_compose_article else R.string.jam_compose_post), color = colors.text, fontSize = 20.sp,
                fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f).semantics { heading() },
            )
            if (step == 1) {
                val ready = if (article) title.isNotBlank() && body.text.isNotBlank() else body.text.isNotBlank() || photos.isNotEmpty()
                TextButton({ step = 2 }, Modifier.heightIn(min = 48.dp).padding(end = 8.dp).testTag("jam-compose-next"), enabled = ready) { Text(stringResource(R.string.jam_next), color = if (ready) colors.text else colors.textSecondary, fontWeight = FontWeight.SemiBold) }
            }
        }
        if (step == 1) {
            Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 20.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                if (article) {
                    Field(title, { title = it.take(120) }, stringResource(R.string.jam_hint_title), "jam-compose-title", singleLine = true)
                    Field(subtitle, { subtitle = it.take(160) }, stringResource(R.string.jam_hint_subtitle), "jam-compose-subtitle", singleLine = true)
                    Toolbar(body, { body = it }, canPhoto = photos.size < maxPhotos && editing == null) { picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) }
                }
                OutlinedTextField(
                    value = body, onValueChange = { body = it },
                    placeholder = { Text(stringResource(if (article) R.string.jam_hint_body else R.string.jam_hint_post), color = colors.textSecondary) },
                    minLines = if (article) 10 else 5, modifier = Modifier.fillMaxWidth().testTag("jam-compose-body"),
                )
                if (!article && editing == null) {
                    Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                        photos.forEachIndexed { index, photo -> PhotoTile(photo, index, onAlt = { describing = photo }, onRemove = { photos.remove(photo) }) }
                        if (photos.size < maxPhotos) {
                            val add = stringResource(R.string.jam_add_photo)
                            Box(
                                Modifier.size(88.dp).background(colors.chip, RoundedCornerShape(12.dp)).semantics { contentDescription = add; role = Role.Button }
                                    .clickable { picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) }.testTag("jam-add-photo"),
                                contentAlignment = Alignment.Center,
                            ) { Icon(Icons.Attach, null, tint = colors.text) }
                        }
                    }
                }
            }
        } else {
            val kindWords = stringResource(if (article) R.string.jam_publish else R.string.jam_post)
            val buttonTitle = if (editing != null) stringResource(R.string.jam_update) else kindWords
            val workingTitle = stringResource(if (editing != null) R.string.jam_updating else if (article) R.string.jam_publishing else R.string.jam_posting)
            val stepWords = stringResource(R.string.jam_step_two)
            val beforeWords = stringResource(if (article) R.string.jam_before_publish else R.string.jam_before_post)
            Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(20.dp), verticalArrangement = Arrangement.spacedBy(20.dp)) {
                Text(stepWords, color = colors.textSecondary, fontSize = 14.sp, modifier = Modifier.semantics { heading(); contentDescription = "$stepWords, $beforeWords" })
                val summary = title.trim().ifEmpty { body.text.lineSequence().firstOrNull { it.isNotBlank() }.orEmpty() }
                Column(Modifier.testTag("jam-before-summary").semantics(mergeDescendants = true) {}) {
                    Text(summary, color = colors.text, fontSize = 18.sp, fontWeight = FontWeight.SemiBold, maxLines = 3)
                    if (subtitle.isNotBlank()) Text(subtitle, color = colors.textSecondary, fontSize = 15.sp)
                }
                // Post as (LIME-315a; iOS beside Audience): only when there is more than one place to post: my own space, or a band of mine.
                val places = model.myJams
                if (places.size > 1 && editing == null) {
                    Text(stringResource(R.string.jam_post_as), color = colors.textSecondary, fontSize = 14.sp)
                    places.forEach { place ->
                        val on = (postAsId ?: model.mine()?.jamId) == place.jamId
                        val label = if (model.isBand(place)) place.title else stringResource(R.string.jam_post_as_me)
                        Row(
                            Modifier.fillMaxWidth().heightIn(min = 52.dp).semantics(mergeDescendants = true) { role = Role.RadioButton; selected = on; contentDescription = label }
                                .clickable { postAsId = place.jamId }.testTag("jam-postas-${place.jamId}"),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Text(label, color = colors.text, fontSize = 17.sp, modifier = Modifier.weight(1f))
                            if (on) Icon(Icons.Check, null, tint = colors.text)
                        }
                    }
                }
                val audience = stringResource(R.string.jam_audience); val subs = stringResource(R.string.jam_audience_subscribers)
                Row(Modifier.fillMaxWidth().heightIn(min = 52.dp).semantics(mergeDescendants = true) { contentDescription = "$audience, $subs" }.testTag("jam-before-audience"), verticalAlignment = Alignment.CenterVertically) {
                    Text(audience, color = colors.text, fontSize = 17.sp, modifier = Modifier.weight(1f))
                    Text(subs, color = colors.textSecondary, fontSize = 17.sp)
                }
                problem?.let { Text(it, color = colors.danger, fontSize = 14.sp, modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite }.testTag("jam-before-problem")) }
                PrimaryButton(
                    if (working) workingTitle else buttonTitle,
                    {
                        scope.launch {
                            working = true; problem = null
                            val jam = model.myJams.firstOrNull { it.jamId == postAsId } ?: model.mine()
                            val ok = when {
                                editing != null -> model.editPost(editing, title, subtitle, body.text)
                                jam == null -> false
                                else -> model.publish(jam.jamId, route.kind, title, subtitle, body.text, photos.map { it.attachment }, displayAs = if (model.isBand(jam)) "jam" else "person") != null
                            }
                            working = false
                            if (ok) { drafts.delete(draftId); onDone() } else problem = failed
                        }
                    },
                    Modifier.testTag("jam-post"), busy = working,
                )
            }
        }
    }
    describing?.let { photo ->
        var alt by remember(photo) { mutableStateOf(photo.attachment.alt) }
        AlertDialog(
            onDismissRequest = { describing = null }, containerColor = colors.canvas,
            title = { Text(stringResource(R.string.photo_description_title), color = colors.text) },
            text = {
                OutlinedTextField(
                    value = alt, onValueChange = { alt = it.take(AttachmentProcessing.MAX_ALT_LENGTH) }, modifier = Modifier.fillMaxWidth().testTag("description-field"),
                    placeholder = { Text(stringResource(R.string.photo_description_hint), color = colors.textSecondary) }, maxLines = 4,
                )
            },
            confirmButton = {
                TextButton({
                    val at = photos.indexOf(photo)
                    if (at >= 0) photos[at] = PhotoDraft(photo.attachment.copy(alt = alt.trim()), photo.preview)
                    describing = null
                }, Modifier.heightIn(min = 48.dp).testTag("description-save")) { Text(stringResource(R.string.photo_description_save), color = colors.text, fontWeight = FontWeight.SemiBold) }
            },
            dismissButton = { TextButton({ describing = null }, Modifier.heightIn(min = 48.dp)) { Text(stringResource(R.string.photo_description_cancel), color = colors.text) } },
        )
    }
}

/** A photo of a post: its picture, an Alt chip (opens the description) and a remove button; TalkBack reads "Photo 1, <description>". */
@Composable
private fun PhotoTile(photo: PhotoDraft, index: Int, onAlt: () -> Unit, onRemove: () -> Unit) {
    val colors = Lime.colors
    val described = photo.attachment.alt.isNotEmpty()
    val label = stringResource(R.string.photo_alt_chip) + (if (described) "" else "")
    Box(Modifier.size(88.dp)) {
        photo.preview?.let { Image(it, contentDescription = if (described) photo.attachment.alt else stringResource(R.string.jam_photo_label), contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize()) }
        Box(
            Modifier.align(Alignment.BottomStart).heightIn(min = 48.dp).widthIn(min = 48.dp).clickable(role = Role.Button, onClick = onAlt).testTag("jam-photo-alt-$index"),
            contentAlignment = Alignment.Center,
        ) {
            Text(if (described) label else stringResource(R.string.photo_alt_chip_add), color = androidx.compose.ui.graphics.Color.White, fontSize = 12.sp, fontWeight = FontWeight.Bold, modifier = Modifier.background(androidx.compose.ui.graphics.Color(0x99000000), RoundedCornerShape(8.dp)).padding(horizontal = 6.dp, vertical = 2.dp))
        }
        val remove = stringResource(R.string.jam_photo_remove)
        Box(Modifier.align(Alignment.TopEnd).size(48.dp).semantics { contentDescription = remove; role = Role.Button }.clickable(onClick = onRemove).testTag("jam-photo-remove-$index"), contentAlignment = Alignment.TopEnd) {
            Text("×", color = androidx.compose.ui.graphics.Color.White, fontSize = 18.sp, modifier = Modifier.background(androidx.compose.ui.graphics.Color(0x99000000), RoundedCornerShape(12.dp)).padding(horizontal = 8.dp))
        }
    }
}

/** Bold, italic, heading, list, link and photo for an article (Markdown around the selection or at the cursor). */
@Composable
private fun Toolbar(value: TextFieldValue, onChange: (TextFieldValue) -> Unit, canPhoto: Boolean, onPhoto: () -> Unit) {
    val colors = Lime.colors
    fun wrap(before: String, after: String, placeholder: String) {
        val a = value.selection.min; val b = value.selection.max
        val chosen = value.text.substring(a, b).ifEmpty { placeholder }
        val text = value.text.substring(0, a) + before + chosen + after + value.text.substring(b)
        onChange(TextFieldValue(text, TextRange(a + before.length, a + before.length + chosen.length)))
    }
    fun linePrefix(prefix: String) {
        val a = value.selection.min
        val lineStart = value.text.lastIndexOf('\n', (a - 1).coerceAtLeast(0)).let { if (a == 0 || it < 0) 0 else it + 1 }
        onChange(TextFieldValue(value.text.substring(0, lineStart) + prefix + value.text.substring(lineStart), TextRange(value.selection.start + prefix.length, value.selection.end + prefix.length)))
    }
    Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        Tool(stringResource(R.string.jam_tool_bold), "B", "jam-tool-bold") { wrap("**", "**", "bold") }
        Tool(stringResource(R.string.jam_tool_italic), "I", "jam-tool-italic") { wrap("*", "*", "italic") }
        Tool(stringResource(R.string.jam_tool_heading), "H", "jam-tool-heading") { linePrefix("## ") }
        Tool(stringResource(R.string.jam_tool_list), "•", "jam-tool-list") { linePrefix("- ") }
        Tool(stringResource(R.string.jam_tool_link), "🔗", "jam-tool-link") { wrap("[", "](https://)", "link") }
        if (canPhoto) Tool(stringResource(R.string.jam_tool_photo), "🖼", "jam-tool-photo", onPhoto)
    }
}

@Composable
private fun Tool(words: String, glyph: String, tag: String, onClick: () -> Unit) {
    val colors = Lime.colors
    Box(Modifier.size(48.dp).background(colors.chip, RoundedCornerShape(12.dp)).semantics { contentDescription = words; role = Role.Button }.clickable(onClick = onClick).testTag(tag), contentAlignment = Alignment.Center) {
        Text(glyph, color = colors.text, fontSize = 18.sp, fontWeight = FontWeight.Bold)
    }
}


/** My jam's picture (LIME-412; iOS `OrgEdit` "Add picture"/"Change picture"/"Remove"): shown on the jam's page; chosen with the Photo Picker, scaled to a JPEG under 1 MiB by this phone. Public like the title. */
@Composable
private fun JamPictureSection(jam: uniffi.lime_core.JamInfo, model: JamModel) {
    val colors = Lime.colors
    val scope = rememberCoroutineScope()
    val context = androidx.compose.ui.platform.LocalContext.current
    var version by remember(jam.jamId) { mutableStateOf(0) }
    var failed by remember { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }
    val bytes = remember(jam.jamId, version, model.reloads) { model.picture(jam.jamId) }
    val bitmap = remember(bytes) { bytes?.let { com.limemessenger.lime.chats.AttachmentProcessing.decodeForDisplay(it, 640) }?.asImageBitmap() }
    val picker = androidx.activity.compose.rememberLauncherForActivityResult(androidx.activity.result.contract.ActivityResultContracts.PickVisualMedia()) { uri ->
        if (uri != null) scope.launch {
            busy = true; failed = false
            val jpeg = withContext(Dispatchers.IO) { com.limemessenger.lime.chats.AttachmentProcessing.decodeUpright(context.contentResolver, uri)?.let { jamPictureJpeg(it) } }
            failed = jpeg == null || !model.setPicture(jam.jamId, jpeg)
            version++; busy = false
        }
    }
    val pictureWords = stringResource(if (bitmap != null) R.string.jam_picture_set else R.string.jam_picture_none)
    Column(Modifier.fillMaxWidth().testTag("jam-picture-section"), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Box(
            Modifier.fillMaxWidth().aspectRatio(1.9f).clip(RoundedCornerShape(16.dp)).background(colors.surface).semantics { contentDescription = pictureWords }.testTag("jam-picture"),
            contentAlignment = Alignment.Center,
        ) {
            if (bitmap != null) androidx.compose.foundation.Image(bitmap, null, contentScale = androidx.compose.ui.layout.ContentScale.Crop, modifier = Modifier.fillMaxSize())
            else Text(stringResource(R.string.jam_picture_none), color = colors.textSecondary, fontSize = 14.sp)
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            androidx.compose.material3.TextButton({ picker.launch(androidx.activity.result.PickVisualMediaRequest(androidx.activity.result.contract.ActivityResultContracts.PickVisualMedia.ImageOnly)) }, Modifier.heightIn(min = 48.dp).testTag("jam-picture-add"), enabled = !busy) {
                Text(stringResource(if (bitmap != null) R.string.jam_picture_change else R.string.jam_picture_add), color = colors.text, fontWeight = FontWeight.SemiBold)
            }
            if (bitmap != null) androidx.compose.material3.TextButton({ scope.launch { busy = true; failed = !model.removePicture(jam.jamId); version++; busy = false } }, Modifier.heightIn(min = 48.dp).testTag("jam-picture-remove"), enabled = !busy) {
                Text(stringResource(R.string.jam_picture_remove), color = colors.danger)
            }
        }
        if (failed) Text(stringResource(R.string.jam_picture_failed), color = colors.danger, fontSize = 14.sp, modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite }.testTag("jam-picture-failed"))
    }
}

/** A jam picture as a JPEG of at most 1 MiB (the core's limit): 1600 px on the long edge, the quality stepped down until it fits. */
internal fun jamPictureJpeg(source: android.graphics.Bitmap): ByteArray? {
    val drawn = com.limemessenger.lime.chats.AttachmentProcessing.redraw(source, 1600)
    var quality = 85
    while (quality >= 35) {
        val data = com.limemessenger.lime.chats.AttachmentProcessing.jpeg(drawn, quality)
        if (data.size <= 1024 * 1024) return data
        quality -= 10
    }
    return null
}


/** "Sending to 412 of 1,000" while a post is still going out to subscribers (LIME-412; the core's `jam_send_progress`), read again every two seconds while this screen is open. */
@Composable
private fun JamSendProgressLine(jamId: String, model: JamModel) {
    val colors = Lime.colors
    var progress by remember(jamId) { mutableStateOf<uniffi.lime_core.JamSendProgress?>(null) }
    LaunchedEffect(jamId) {
        while (true) { progress = model.sendProgress(jamId); kotlinx.coroutines.delay(2_000) }
    }
    val p = progress
    if (p != null && p.pending > 0u) {
        val words = stringResource(R.string.jam_sending_progress, (p.total - p.pending).toInt(), p.total.toInt())
        Text(words, color = colors.textSecondary, fontSize = 14.sp, modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite }.testTag("jam-send-progress"))
    }
}


/** The list of my jams (LIME-315a): my own space and each band, the current one ticked; choosing one makes the Your jam page and the next post about it. */
@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
private fun JamSwitcherSheet(model: JamModel, onDismiss: () -> Unit) {
    val colors = Lime.colors
    val current = model.mine()?.jamId
    androidx.compose.material3.ModalBottomSheet(onDismissRequest = onDismiss, containerColor = colors.canvas) {
        Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp).padding(bottom = 24.dp).testTag("jam-switcher-sheet")) {
            Text(stringResource(R.string.jam_switch_title), color = colors.text, fontSize = 20.sp, fontWeight = FontWeight.Bold, modifier = Modifier.padding(bottom = 8.dp).semantics { heading() })
            model.myJams.forEach { jam ->
                val on = jam.jamId == current
                val kind = stringResource(if (model.isBand(jam)) R.string.jam_kind_band else R.string.jam_kind_yours)
                Row(
                    Modifier.fillMaxWidth().heightIn(min = 56.dp).semantics(mergeDescendants = true) { role = Role.RadioButton; selected = on; contentDescription = "${jam.title}, $kind" }
                        .clickable { model.chosenJamId = jam.jamId; onDismiss() }.testTag("jam-switch-${jam.jamId}"),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Column(Modifier.weight(1f)) {
                        Text(jam.title, color = colors.text, fontSize = 17.sp)
                        Text(kind, color = colors.textSecondary, fontSize = 13.sp)
                    }
                    if (on) Icon(Icons.Check, null, tint = colors.text)
                }
            }
        }
    }
}

/**
 * Making a band (LIME-315a; iOS `CreatePublicationSheet`): a picture (Photo Picker, optional), the name (required, 60), an optional about (500) and the tags; "The picture, name and about are public."
 * The core makes it a second jam of mine (`create_jam`) with its members group opened (`org_start`), so it can be posted as at once; it ends on the new band's page.
 */
@Composable
fun CreateBandScreen(model: JamModel, onClose: () -> Unit) {
    val colors = Lime.colors
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    var name by remember { mutableStateOf("") }
    var about by remember { mutableStateOf("") }
    var topics by remember { mutableStateOf("") }
    var picture by remember { mutableStateOf<ByteArray?>(null) }
    var preview by remember { mutableStateOf<androidx.compose.ui.graphics.ImageBitmap?>(null) }
    var making by remember { mutableStateOf(false) }
    var failed by remember { mutableStateOf(false) }
    val picker = rememberLauncherForActivityResult(androidx.activity.result.contract.ActivityResultContracts.PickVisualMedia()) { uri ->
        if (uri != null) scope.launch {
            val jpeg = withContext(Dispatchers.IO) { AttachmentProcessing.decodeUpright(context.contentResolver, uri)?.let { jamPictureJpeg(it) } }
            picture = jpeg
            preview = jpeg?.let { AttachmentProcessing.decodeForDisplay(it, 400) }?.asImageBitmap()
        }
    }
    androidx.compose.ui.window.Dialog(onDismissRequest = { if (!making) onClose() }, properties = androidx.compose.ui.window.DialogProperties(usePlatformDefaultWidth = false)) {
        Column(Modifier.fillMaxSize().background(colors.canvas).systemBarsPadding().imePadding().testTag("band-create")) {
            Row(Modifier.fillMaxWidth().heightIn(min = 64.dp), verticalAlignment = Alignment.CenterVertically) {
                IconButton(onClick = { if (!making) onClose() }, Modifier.size(56.dp).testTag("band-create-close")) { Icon(Icons.Close, stringResource(R.string.settings_close), tint = colors.text) }
                Text(stringResource(R.string.band_create), color = colors.text, fontSize = 22.sp, fontWeight = FontWeight.Bold, modifier = Modifier.semantics { heading() })
            }
            Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 20.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                Box(
                    Modifier.size(104.dp).align(Alignment.CenterHorizontally).clip(RoundedCornerShape(29.dp)).background(colors.surface).clickable { picker.launch(androidx.activity.result.PickVisualMediaRequest(androidx.activity.result.contract.ActivityResultContracts.PickVisualMedia.ImageOnly)) }
                        .semantics { role = Role.Button; contentDescription = "Band picture" }.testTag("band-picture"),
                    contentAlignment = Alignment.Center,
                ) {
                    val shown = preview
                    if (shown != null) androidx.compose.foundation.Image(shown, null, contentScale = androidx.compose.ui.layout.ContentScale.Crop, modifier = Modifier.fillMaxSize())
                    else Text(name.trim().take(1).uppercase().ifEmpty { "B" }, color = colors.textSecondary, fontSize = 40.sp, fontWeight = FontWeight.Bold)
                }
                Field(name, { name = it.take(60) }, stringResource(R.string.band_name_hint), "band-name", singleLine = true)
                Text("${name.trim().length}/60", color = colors.textSecondary, fontSize = 12.sp)
                Field(about, { about = it.take(500) }, stringResource(R.string.band_about_hint), "band-about", minLines = 3)
                Field(topics, { topics = it.take(240) }, stringResource(R.string.jam_field_topics), "band-topics", singleLine = true)
                Text(stringResource(R.string.band_public_note), color = colors.textSecondary, fontSize = 13.sp, modifier = Modifier.testTag("band-public-note"))
                Text(stringResource(R.string.band_explainer_title), color = colors.text, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
                Text(stringResource(R.string.band_explainer), color = colors.textSecondary, fontSize = 13.sp, modifier = Modifier.testTag("band-explainer"))
                if (failed) Text(stringResource(R.string.band_failed), color = colors.danger, fontSize = 14.sp, modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite }.testTag("band-failed"))
                PrimaryButton(
                    stringResource(if (making) R.string.band_creating else R.string.band_make),
                    {
                        scope.launch {
                            making = true; failed = false
                            val list = topics.split(",").map { it.trim() }.filter { it.isNotEmpty() }.take(8)
                            val id = model.createBand(name, about, list, picture)
                            making = false
                            if (id != null) onClose() else failed = true
                        }
                    },
                    Modifier.testTag("band-make"), enabled = name.isNotBlank() && !making,
                )
            }
        }
    }
}
