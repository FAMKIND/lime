package com.limemessenger.lime.ui.chat

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.net.Uri
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.core.CameraSelector
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.video.FallbackStrategy
import androidx.camera.video.FileOutputOptions
import androidx.camera.video.Quality
import androidx.camera.video.QualitySelector
import androidx.camera.video.Recorder
import androidx.camera.video.Recording
import androidx.camera.video.VideoCapture
import androidx.camera.video.VideoRecordEvent
import androidx.camera.view.PreviewView
import androidx.compose.foundation.Image
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
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTag
import androidx.compose.ui.platform.testTag
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.core.content.ContextCompat
import androidx.media3.common.MediaItem
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView
import com.limemessenger.lime.R
import com.limemessenger.lime.chats.ChatModel
import com.limemessenger.lime.chats.AttachmentFormat
import com.limemessenger.lime.chats.VideoProcessing
import com.limemessenger.lime.ui.shell.Icons
import com.limemessenger.lime.ui.theme.Lime
import java.io.File
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import uniffi.lime_core.AttachmentInfo

/** Who answers "may lime use the camera and the microphone?" (the system, or a test that says no). */
interface VideoPermissions {
    fun granted(context: Context): Boolean
    /** Asks the system (the request dialog) and reports the answer. */
    @Composable fun requester(onResult: (Boolean) -> Unit): () -> Unit
}

object SystemVideoPermissions : VideoPermissions {
    private val needed = arrayOf(Manifest.permission.CAMERA, Manifest.permission.RECORD_AUDIO)
    override fun granted(context: Context) = needed.all { ContextCompat.checkSelfPermission(context, it) == PackageManager.PERMISSION_GRANTED }
    @Composable override fun requester(onResult: (Boolean) -> Unit): () -> Unit {
        val launcher = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { result -> onResult(needed.all { result[it] == true }) }
        return { launcher.launch(needed) }
    }
}

val LocalVideoPermissions = compositionLocalOf<VideoPermissions> { SystemVideoPermissions }

private sealed class Stage {
    object Explain : Stage()
    object Denied : Stage()
    object Camera : Stage()
    class Review(val file: File) : Stage()
    object Preparing : Stage()
    class Problem(val words: String) : Stage()
}

/**
 * Records a video message (LIME-314; iOS records through the system camera): **the camera and microphone are asked for at first use only, after a plain explanation**; refused
 * shows why and a way to the system settings, never a crash. CameraX records (the front camera first, the back one when there is none) up to 3 minutes with a countdown for the last
 * ten seconds; then a preview with Retake and "Add to message". The temporary file is deleted after it is prepared, on Retake and on close; the video carries no place (the recording is made
 * with no location and re-muxed clean, see [VideoProcessing]).
 */
@Composable
fun VideoRecorderScreen(onClose: () -> Unit, onUse: (VideoProcessing.Made) -> Unit) {
    val context = LocalContext.current
    val colors = Lime.colors
    val permissions = LocalVideoPermissions.current
    val scope = rememberCoroutineScope()
    var stage by remember { mutableStateOf<Stage>(if (permissions.granted(context)) Stage.Camera else Stage.Explain) }
    val failedWords = stringResource(R.string.video_failed)
    val ask = permissions.requester { ok -> stage = if (ok) Stage.Camera else Stage.Denied }
    fun discard(file: File?) { file?.delete() }
    DisposableEffect(Unit) { onDispose { (stage as? Stage.Review)?.let { discard(it.file) } } }
    Dialog(onDismissRequest = { (stage as? Stage.Review)?.let { discard(it.file) }; onClose() }, properties = DialogProperties(usePlatformDefaultWidth = false, dismissOnBackPress = true)) {
        Box(Modifier.fillMaxSize().background(Color.Black).systemBarsPadding().testTag("video-recorder")) {
            when (val s = stage) {
                Stage.Explain, Stage.Denied -> Column(Modifier.fillMaxSize().padding(24.dp), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
                    if (s == Stage.Explain) {
                        Text(stringResource(R.string.video_explain_title), color = Color.White, fontSize = 22.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.semantics { heading() })
                        Text(stringResource(R.string.video_explain_body), color = Color.White.copy(alpha = 0.85f), fontSize = 16.sp, modifier = Modifier.padding(vertical = 16.dp).testTag("video-explain"))
                        PrimaryButton(stringResource(R.string.video_allow), "video-allow") { ask() }
                    } else {
                        Text(stringResource(R.string.video_denied_body), color = Color.White, fontSize = 17.sp, modifier = Modifier.padding(bottom = 16.dp).testTag("video-denied").semantics { liveRegion = LiveRegionMode.Polite })
                        PrimaryButton(stringResource(R.string.video_open_settings), "video-open-settings") {
                            context.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", context.packageName, null)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                        }
                    }
                }
                Stage.Camera -> CameraStage(
                    onFinished = { file -> stage = Stage.Review(file) },
                    onFailed = { stage = Stage.Problem(failedWords) },
                )
                is Stage.Review -> ReviewStage(
                    file = s.file,
                    onRetake = { discard(s.file); stage = Stage.Camera },
                    onUse = {
                        stage = Stage.Preparing
                        scope.launch {
                            val result = withContext(Dispatchers.IO) { VideoProcessing.prepare(s.file).also { s.file.delete() } }
                            when (result) {
                                is VideoProcessing.Result.Ok -> onUse(result.made)
                                is VideoProcessing.Result.Failed -> stage = Stage.Problem(problemWords(context, result.problem))
                            }
                        }
                    },
                )
                Stage.Preparing -> Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
                    CircularProgressIndicator(color = Color.White)
                    Text(stringResource(R.string.video_preparing), color = Color.White, fontSize = 16.sp, modifier = Modifier.padding(top = 16.dp).testTag("video-preparing").semantics { liveRegion = LiveRegionMode.Polite })
                }
                is Stage.Problem -> Column(Modifier.fillMaxSize().padding(24.dp), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(s.words, color = Color.White, fontSize = 17.sp, modifier = Modifier.padding(bottom = 16.dp).testTag("video-problem").semantics { liveRegion = LiveRegionMode.Polite })
                    PrimaryButton(stringResource(R.string.video_retake), "video-retake") { stage = Stage.Camera }
                }
            }
            CloseButton(Modifier.align(Alignment.TopStart).padding(8.dp)) { (stage as? Stage.Review)?.let { discard(it.file) }; onClose() }
        }
    }
}

private fun problemWords(context: Context, problem: VideoProcessing.Problem): String = when (problem) {
    is VideoProcessing.Problem.TooLong -> context.getString(R.string.video_too_long, AttachmentFormat.voiceClock(problem.seconds.toDouble()))
    VideoProcessing.Problem.TooLarge -> context.getString(R.string.video_too_large)
    VideoProcessing.Problem.Unreadable -> context.getString(R.string.video_unreadable)
}

@Composable
private fun PrimaryButton(words: String, tag: String, onClick: () -> Unit) {
    val colors = Lime.colors
    Box(
        Modifier.heightIn(min = 52.dp).widthIn(min = 200.dp).clip(RoundedCornerShape(26.dp)).background(colors.accent).clickable(onClick = onClick)
            .semantics { role = Role.Button }.testTag(tag).padding(horizontal = 24.dp),
        contentAlignment = Alignment.Center,
    ) { Text(words, color = colors.accentInk, fontSize = 17.sp, fontWeight = FontWeight.SemiBold) }
}

@Composable
private fun CloseButton(modifier: Modifier, onClick: () -> Unit) {
    val words = stringResource(R.string.video_close)
    Box(modifier.size(48.dp).clip(CircleShape).background(Color.Black.copy(alpha = 0.55f)).clickable(onClick = onClick).semantics { contentDescription = words; role = Role.Button }.testTag("video-close"), contentAlignment = Alignment.Center) {
        Icon(Icons.Close, contentDescription = null, tint = Color.White, modifier = Modifier.size(22.dp))
    }
}

/** The camera: the preview, a round Record that becomes Stop, the time and, in the last ten seconds, the countdown. */
@Composable
private fun CameraStage(onFinished: (File) -> Unit, onFailed: () -> Unit) {
    val context = LocalContext.current
    val owner = LocalLifecycleOwner.current
    val colors = Lime.colors
    val previewView = remember { PreviewView(context).apply { implementationMode = PreviewView.ImplementationMode.COMPATIBLE } }
    var capture by remember { mutableStateOf<VideoCapture<Recorder>?>(null) }
    var front by remember { mutableStateOf(true) }
    var hasFront by remember { mutableStateOf(true) }
    var hasBack by remember { mutableStateOf(true) }
    var recording by remember { mutableStateOf<Recording?>(null) }
    var elapsedMs by remember { mutableStateOf(0L) }
    val max = VideoProcessing.MAX_SECONDS.toLong()
    val executor = remember { ContextCompat.getMainExecutor(context) }
    LaunchedEffect(front) {
        val provider = withContext(Dispatchers.IO) { ProcessCameraProvider.getInstance(context).get() }
        withContext(Dispatchers.Main) {   // CameraX wants the main thread for binding and for the preview's surface
            hasFront = provider.hasCamera(CameraSelector.DEFAULT_FRONT_CAMERA)
            hasBack = provider.hasCamera(CameraSelector.DEFAULT_BACK_CAMERA)
            val selector = when {
                front && hasFront -> CameraSelector.DEFAULT_FRONT_CAMERA
                hasBack -> CameraSelector.DEFAULT_BACK_CAMERA
                hasFront -> CameraSelector.DEFAULT_FRONT_CAMERA
                else -> { onFailed(); return@withContext }
            }
            val recorder = Recorder.Builder().setQualitySelector(QualitySelector.from(Quality.HD, FallbackStrategy.lowerQualityOrHigherThan(Quality.SD))).build()
            val video = VideoCapture.withOutput(recorder)
            val preview = Preview.Builder().build().also { it.surfaceProvider = previewView.surfaceProvider }
            try {
                provider.unbindAll()
                provider.bindToLifecycle(owner, selector, preview, video)
                capture = video
            } catch (e: Exception) { onFailed() }
        }
    }
    DisposableEffect(Unit) { onDispose { recording?.stop(); runCatching { ProcessCameraProvider.getInstance(context).get().unbindAll() } } }
    Box(Modifier.fillMaxSize()) {
        AndroidView({ previewView }, Modifier.fillMaxSize())
        val remaining = (max - elapsedMs / 1000).toInt()
        val clock = AttachmentFormat.voiceClock(elapsedMs / 1000.0)
        val timerWords = if (recording != null && remaining <= 10) stringResource(R.string.video_last_seconds, remaining.coerceAtLeast(0)) else stringResource(R.string.video_timer, clock, AttachmentFormat.voiceClock(max.toDouble()))
        Text(
            timerWords, color = Color.White, fontSize = 16.sp, fontWeight = FontWeight.SemiBold,
            modifier = Modifier.align(Alignment.TopCenter).padding(top = 16.dp).background(Color.Black.copy(alpha = 0.55f), RoundedCornerShape(14.dp)).padding(horizontal = 12.dp, vertical = 6.dp).testTag("video-timer"),
        )
        Row(Modifier.align(Alignment.BottomCenter).fillMaxWidth().padding(bottom = 32.dp), horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
            val recordWords = stringResource(R.string.video_record)
            val stopWords = stringResource(R.string.video_stop)
            Box(
                Modifier.size(72.dp).clip(CircleShape).background(Color.White).padding(6.dp).clip(CircleShape).background(if (recording != null) Color(0xFFD93A3A) else Color.White)
                    .semantics { contentDescription = if (recording != null) stopWords else recordWords; role = Role.Button }
                    .clickable(enabled = capture != null) {
                        val active = recording
                        if (active != null) { active.stop() } else {
                            val file = File(context.cacheDir, "lime-video-${UUID.randomUUID()}.mp4")
                            // No setLocation: the recording carries no place. A size and a time limit stop it by itself.
                            val options = FileOutputOptions.Builder(file).setFileSizeLimit(VideoProcessing.MAX_BYTES.toLong()).setDurationLimitMillis(max * 1000).build()
                            val prepared = capture!!.output.prepareRecording(context, options)
                            val micOk = ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
                            recording = (if (micOk) prepared.withAudioEnabled() else prepared).start(executor) { event ->
                                when (event) {
                                    is VideoRecordEvent.Status -> elapsedMs = event.recordingStats.recordedDurationNanos / 1_000_000
                                    is VideoRecordEvent.Finalize -> {
                                        recording = null
                                        val tolerated = event.error == VideoRecordEvent.Finalize.ERROR_NONE || event.error == VideoRecordEvent.Finalize.ERROR_DURATION_LIMIT_REACHED || event.error == VideoRecordEvent.Finalize.ERROR_FILE_SIZE_LIMIT_REACHED
                                        if (tolerated && file.exists() && file.length() > 0) onFinished(file) else { file.delete(); onFailed() }
                                    }
                                    else -> {}
                                }
                            }
                        }
                    }.testTag(if (recording != null) "video-stop" else "video-record"),
            )
            if (recording == null && hasFront && hasBack) {
                val flip = stringResource(R.string.video_flip)
                Box(Modifier.padding(start = 24.dp).size(48.dp).clip(CircleShape).background(Color.Black.copy(alpha = 0.55f)).clickable { front = !front }.semantics { contentDescription = flip; role = Role.Button }.testTag("video-flip"), contentAlignment = Alignment.Center) {
                    Icon(Icons.Play, null, tint = Color.White, modifier = Modifier.size(0.dp))
                    Text("⇄", color = Color.White, fontSize = 22.sp)
                }
            }
        }
    }
}

/** The recording played back, with Retake and "Add to message". */
@Composable
private fun ReviewStage(file: File, onRetake: () -> Unit, onUse: () -> Unit) {
    Box(Modifier.fillMaxSize()) {
        VideoPlayerView(file, Modifier.fillMaxSize().testTag("video-review"))
        Row(Modifier.align(Alignment.BottomCenter).fillMaxWidth().padding(bottom = 96.dp, start = 16.dp, end = 16.dp), horizontalArrangement = Arrangement.spacedBy(12.dp, Alignment.CenterHorizontally)) {
            PrimaryButton(stringResource(R.string.video_retake), "video-retake") { onRetake() }
            PrimaryButton(stringResource(R.string.video_send), "video-send") { onUse() }
        }
    }
}

/** A Media3 player on a local file: it plays from the start and is released when it leaves. */
@Composable
fun VideoPlayerView(file: File, modifier: Modifier = Modifier, autoplay: Boolean = true) {
    val context = LocalContext.current
    val player = remember(file) { ExoPlayer.Builder(context).build().apply { setMediaItem(MediaItem.fromUri(Uri.fromFile(file))); prepare(); playWhenReady = autoplay } }
    DisposableEffect(player) { onDispose { player.release() } }
    AndroidView({ ctx -> PlayerView(ctx).apply { this.player = player; useController = true } }, modifier)
}

// ---------------------------------------------------------------- in a bubble

/** A video in a bubble (iOS `VideoTile`): its poster (the sender's frame; the tiny blurred preview until it is known), a play button and the length; tapping downloads it when needed and opens the player. */
@Composable
fun VideoTile(attachment: AttachmentInfo, model: ChatModel, modifier: Modifier = Modifier) {
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    val colors = Lime.colors
    var opening by remember(attachment.id) { mutableStateOf(false) }
    var playing by remember(attachment.id) { mutableStateOf<File?>(null) }
    var failed by remember(attachment.id) { mutableStateOf(false) }
    val picture = remember(attachment.id) {
        val bytes = if (attachment.poster.isNotEmpty()) attachment.poster else attachment.thumb
        if (bytes.isNotEmpty()) com.limemessenger.lime.chats.AttachmentProcessing.decodeForDisplay(bytes, 480)?.asImageBitmap() else null
    }
    val seconds = (attachment.durationMs ?: 0u).toDouble() / 1000.0
    val clock = AttachmentFormat.voiceClock(seconds)
    val words = stringResource(R.string.video_label, clock)
    val playWords = stringResource(R.string.video_play)
    val aspect = ((attachment.width?.toFloat() ?: 16f) / (attachment.height?.toFloat() ?: 9f)).coerceIn(0.6f, 1.8f)
    val open: () -> Unit = {
        if (!opening && !attachment.removed) scope.launch {
            opening = true; failed = false
            val bytes = model.attachmentBytes(attachment)
            if (bytes == null) failed = true else {
                val file = withContext(Dispatchers.IO) { File(context.cacheDir, "lime-play-${UUID.randomUUID()}.mp4").also { it.writeBytes(bytes) } }
                playing = file
            }
            opening = false
        }
    }
    Box(
        modifier.width(248.dp).aspectRatio(aspect).clip(RoundedCornerShape(18.dp)).background(colors.surface).clickable(onClick = open)
            .clearAndSetSemantics {
                contentDescription = words; role = Role.Button; testTag = "video-${attachment.id}"
                customActions = listOf(CustomAccessibilityAction(playWords) { open(); true })
            },
        contentAlignment = Alignment.Center,
    ) {
        if (picture != null) Image(picture, null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
        Box(Modifier.size(52.dp).background(Color.Black.copy(alpha = 0.45f), CircleShape), contentAlignment = Alignment.Center) {
            if (opening) CircularProgressIndicator(color = Color.White, modifier = Modifier.size(28.dp), strokeWidth = 3.dp)
            else Icon(Icons.Play, contentDescription = null, tint = Color.White, modifier = Modifier.size(26.dp))
        }
        Text(clock, color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.align(Alignment.BottomEnd).padding(8.dp).background(Color.Black.copy(alpha = 0.5f), CircleShape).padding(horizontal = 7.dp, vertical = 3.dp))
        if (failed) Text(stringResource(R.string.video_unavailable), color = Color.White, fontSize = 12.sp, modifier = Modifier.align(Alignment.BottomStart).padding(8.dp).background(Color.Black.copy(alpha = 0.6f), RoundedCornerShape(8.dp)).padding(6.dp).testTag("video-failed"))
        if (!attachment.downloaded && !opening && !failed) Text(
            com.limemessenger.lime.chats.AttachmentProcessing.let { friendlyBytes(attachment.size.toLong()) }, color = Color.White, fontSize = 12.sp,
            modifier = Modifier.align(Alignment.BottomStart).padding(8.dp).background(Color.Black.copy(alpha = 0.5f), RoundedCornerShape(10.dp)).padding(horizontal = 7.dp, vertical = 3.dp),
        )
    }
    playing?.let { file ->
        Dialog(onDismissRequest = { file.delete(); playing = null }, properties = DialogProperties(usePlatformDefaultWidth = false)) {
            Box(Modifier.fillMaxSize().background(Color.Black).systemBarsPadding().testTag("video-player")) {
                VideoPlayerView(file, Modifier.fillMaxSize())
                val close = stringResource(R.string.video_player_close)
                Box(Modifier.align(Alignment.TopStart).padding(8.dp).size(48.dp).clip(CircleShape).background(Color.Black.copy(alpha = 0.55f)).clickable { file.delete(); playing = null }.semantics { contentDescription = close; role = Role.Button }.testTag("video-player-close"), contentAlignment = Alignment.Center) {
                    Icon(Icons.Close, null, tint = Color.White, modifier = Modifier.size(22.dp))
                }
            }
        }
    }
}

private fun friendlyBytes(bytes: Long): String = when {
    bytes >= 1024 * 1024 -> "%.1f MB".format(bytes / (1024.0 * 1024.0))
    bytes >= 1024 -> "${bytes / 1024} KB"
    else -> "$bytes B"
}

/** A recorded video waiting in the draft strip: its poster with a play mark (no description chip: a video has none). */
@Composable
fun VideoDraftThumb(poster: Bitmap?, seconds: Double, onRemove: () -> Unit, removeWords: String) {
    val words = stringResource(R.string.video_draft_label, AttachmentFormat.voiceClock(seconds))
    Box(Modifier.size(88.dp).clip(RoundedCornerShape(12.dp)).background(Lime.colors.surface).semantics { contentDescription = words }.testTag("draft-video")) {
        if (poster != null) Image(poster.asImageBitmap(), null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
        Icon(Icons.Play, null, tint = Color.White, modifier = Modifier.align(Alignment.Center).size(30.dp).background(Color.Black.copy(alpha = 0.45f), CircleShape).padding(5.dp))
        Box(Modifier.align(Alignment.TopEnd).size(48.dp).clickable(onClick = onRemove).semantics { contentDescription = removeWords; role = Role.Button }.testTag("draft-remove"), contentAlignment = Alignment.TopEnd) {
            Icon(Icons.Close, null, tint = Color.White, modifier = Modifier.padding(4.dp).background(Color.Black.copy(alpha = 0.6f), CircleShape).padding(4.dp).size(16.dp))
        }
    }
}
