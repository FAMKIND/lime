package com.limemessenger.lime

import android.Manifest
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.down
import androidx.compose.ui.test.moveBy
import androidx.compose.ui.test.up
import androidx.compose.ui.geometry.Offset
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.limemessenger.lime.chats.ChatModel
import com.limemessenger.lime.chats.ChatsModel
import com.limemessenger.lime.chats.VoiceCapture
import com.limemessenger.lime.chats.VoiceRecorder
import com.limemessenger.lime.keys.KeyWrapper
import com.limemessenger.lime.keys.KeystoreKey
import com.limemessenger.lime.keys.SecureBlobStore
import com.limemessenger.lime.storage.StorageBootstrap
import com.limemessenger.lime.ui.chat.ChatScreen
import com.limemessenger.lime.ui.chat.LocalVoiceCapture
import com.limemessenger.lime.ui.theme.LimeTheme
import java.io.File
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import uniffi.lime_core.FileCheck
import uniffi.lime_core.LimeStore
import uniffi.lime_core.OutgoingAttachment
import uniffi.lime_core.attachmentLimits
import uniffi.lime_core.checkFileSize
import uniffi.lime_core.fileTooLargeWords

/** A made-up microphone: a short blob each time (the emulator may have no microphone; the real recorder has its own smoke test). */
private class FakeCapture(var startsOk: Boolean = true) : VoiceCapture {
    var stopped = 0; var cancelled = 0
    override fun start(podcast: Boolean) = startsOk
    override fun level() = 0.5f
    override fun stop(): ByteArray? { stopped++; return ByteArray(4_000) { 7 } }
    override fun cancel() { cancelled++ }
}

/** LIME-308: recording (hold, lock, cancel, too short), the voice card, the file card, the limits: against a real core store. */
@RunWith(AndroidJUnit4::class)
class VoiceFilesUiTest {
    @get:Rule val rule = createComposeRule()
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private lateinit var dir: File
    private lateinit var store: LimeStore
    private lateinit var chats: ChatsModel
    private lateinit var chat: ChatModel
    private val capture = FakeCapture()
    private val alias = "lime.test.voice"

    @Before fun setUp() {
        // The microphone permission is granted to the app under test (the real prompt is the system's).
        InstrumentationRegistry.getInstrumentation().uiAutomation.executeShellCommand("pm grant ${context.packageName} android.permission.RECORD_AUDIO").use { java.io.FileInputStream(it.fileDescriptor).readBytes() }   // (UiAutomation.grantRuntimePermission needs API 28)
        dir = File(context.cacheDir, "voice-${System.nanoTime()}").also { it.mkdirs() }
        val secrets = SecureBlobStore(File(dir, "secrets"), KeyWrapper(KeystoreKey.getOrCreate(alias)))
        val storage = StorageBootstrap(File(dir, "data"), secrets)
        store = storage.open(storage.space("voice-user")).store
        chats = ChatsModel(store = { store }, transport = { null }, token = { "t" }, staleToken = { "t" })
        runBlocking { chats.reload() }
        val id = store.startDm("ben-test", "Ben Test")
        runBlocking { chats.reload() }
        chat = ChatModel(id, chats, accountSignedIn = false)
    }

    @After fun tearDown() { if (::store.isInitialized) store.close(); dir.deleteRecursively(); KeystoreKey.delete(alias) }

    private fun show() = rule.setContent { LimeTheme { CompositionLocalProvider(LocalVoiceCapture provides { capture }) { ChatScreen(chat, chats, onBack = {}) } } }
    private fun count(tag: String) = rule.onAllNodes(hasTestTag(tag), useUnmergedTree = true).fetchSemanticsNodes().size

    /** What the composer handed to the model (a test store has no account to send from). */
    private val sent = mutableListOf<OutgoingAttachment>()
    private fun hook() { chat.outgoingHook = { items, _ -> sent += items; true } }

    @Test fun holdingTheMicrophoneRecordsAndLiftingSendsAVoiceMessage() {
        hook(); show()
        rule.onNodeWithTag("voice-mic", useUnmergedTree = true).performTouchInput { down(center) }
        rule.waitUntil(5_000) { count("recording-bar") > 0 }
        Thread.sleep(900)   // longer than the 0.6 s a voice message needs
        rule.onNodeWithTag("voice-mic", useUnmergedTree = true).performTouchInput { up() }
        rule.waitUntil(10_000) { sent.isNotEmpty() }
        val note = sent.single()
        assertEquals("audio/mp4", note.mime); assertEquals("Voice message.m4a", note.name)
        assertEquals(64, note.thumb.size)   // the loudness bars travel as its preview
        assertTrue((note.durationMs ?: 0u) >= 600u)
        assertEquals(4_000, note.bytes.size)
        assertEquals(0, count("recording-bar"))
        assertEquals("Voice message (0:01)", com.limemessenger.lime.chats.AttachmentFormat.summary(listOf(infoOf(note.copy(durationMs = 1_000u)))))
    }

    @Test fun aTapIsNotAVoiceMessageAndSlidingLeftCancels() {
        hook(); show()
        rule.onNodeWithTag("voice-mic", useUnmergedTree = true).performTouchInput { down(center); up() }   // a tap (no hold)
        rule.waitForIdle(); Thread.sleep(400); rule.waitForIdle()
        assertTrue("a tap is not a voice message", sent.isEmpty())
        // Slide left: cancelled; nothing is sent, and the microphone was told to stop without keeping anything.
        val before = capture.cancelled
        rule.onNodeWithTag("voice-mic", useUnmergedTree = true).performTouchInput { down(center) }
        rule.waitUntil(5_000) { count("recording-bar") > 0 }
        rule.onNodeWithTag("voice-mic", useUnmergedTree = true).performTouchInput { moveBy(Offset(-400f, 0f)); up() }
        rule.waitUntil(5_000) { count("recording-bar") == 0 }
        assertTrue(capture.cancelled > before)
        assertTrue(sent.isEmpty())
    }

    @Test fun slidingUpLocksItHandsFreeAndSendOrCancelFinishIt() {
        hook(); show()
        rule.onNodeWithTag("voice-mic", useUnmergedTree = true).performTouchInput { down(center) }
        rule.waitUntil(5_000) { count("recording-bar") > 0 }
        rule.onNodeWithTag("voice-mic", useUnmergedTree = true).performTouchInput { moveBy(Offset(0f, -300f)); up() }
        rule.waitUntil(5_000) { count("voice-send") > 0 }   // locked: it goes on after the finger is lifted, with Send and Cancel
        assertTrue(count("recording-bar") > 0)
        Thread.sleep(900)
        rule.onNodeWithTag("voice-send", useUnmergedTree = true).performClick()
        rule.waitUntil(10_000) { sent.isNotEmpty() }
        // Locked again and cancelled: nothing more is sent.
        rule.onNodeWithTag("voice-mic", useUnmergedTree = true).performTouchInput { down(center) }
        rule.waitUntil(5_000) { count("recording-bar") > 0 }
        rule.onNodeWithTag("voice-mic", useUnmergedTree = true).performTouchInput { moveBy(Offset(0f, -300f)); up() }
        rule.waitUntil(5_000) { count("voice-cancel") > 0 }
        rule.onNodeWithTag("voice-cancel", useUnmergedTree = true).performClick()
        rule.waitUntil(5_000) { count("recording-bar") == 0 }
        assertEquals(1, sent.size)
    }

    @Test fun aMicrophoneThatCannotStartSaysSoAndSendsNothing() {
        capture.startsOk = false
        hook(); show()
        rule.onNodeWithTag("voice-mic", useUnmergedTree = true).performTouchInput { down(center); up() }
        rule.waitUntil(5_000) { count("photo-problem") > 0 }
        assertEquals(0, count("recording-bar")); assertTrue(sent.isEmpty())
    }

    private fun infoOf(o: OutgoingAttachment) = uniffi.lime_core.AttachmentInfo(
        id = "x", mime = o.mime, name = o.name, size = o.bytes.size.toULong(), width = null, height = null, durationMs = o.durationMs, thumb = o.thumb, poster = ByteArray(0),
        alt = "", transcript = "", downloaded = true, removed = false,
    )

    @Test fun aFileShowsItsNameAndSizeAndTheLimitsAreTheCores() {
        val file = infoOf(OutgoingAttachment(ByteArray(2_048) { 1 }, "Plan.pdf", "application/pdf", null, null, null, ByteArray(0), ByteArray(0), "")).copy(id = "f1")
        rule.setContent { LimeTheme { com.limemessenger.lime.ui.chat.FileCard(file.copy(downloaded = false), chat, androidx.compose.ui.graphics.Color.Black) } }
        rule.waitUntil(5_000) { count("file-f1") > 0 }
        rule.onNodeWithTag("file-f1", useUnmergedTree = true).assertIsDisplayed()
        val words = rule.onNodeWithTag("file-f1", useUnmergedTree = true).fetchSemanticsNode().config[SemanticsProperties.ContentDescription].joinToString()
        assertTrue(words, words.contains("Plan.pdf") && words.contains("KB"))
        assertEquals("2 KB · Tap to download", rule.onNodeWithTag("file-state-f1", useUnmergedTree = true).fetchSemanticsNode().config[SemanticsProperties.Text].joinToString("") { it.text })
        // The limits: 50 MB, 10 a message, 15 minutes of voice; the too-large words as iOS says them.
        val limits = attachmentLimits()
        assertEquals(50L * 1024 * 1024, limits.maxFileBytes.toLong()); assertEquals(10u, limits.maxPerMessage); assertEquals(900.0, limits.maxVoiceSeconds, 0.0)
        assertEquals(FileCheck.TOO_LARGE, checkFileSize(limits.maxFileBytes + 1u)); assertEquals(FileCheck.OK, checkFileSize(limits.maxFileBytes))
        assertEquals(listOf("That file is too large", "Files can be up to 50 MB."), fileTooLargeWords())
    }

    @Test fun aVoiceCardShowsItsLengthAndPlaysWhereTheEmulatorCanPlayIt() {
        val wav = tone()
        val voice = infoOf(OutgoingAttachment(wav, "Voice message.wav", "audio/wav", null, null, 1_000u, ByteArray(64) { 120.toByte() }, ByteArray(0), "")).copy(id = "v1")
        val player = com.limemessenger.lime.chats.VoicePlayer(context)
        rule.setContent { LimeTheme { com.limemessenger.lime.ui.chat.VoiceCard(voice, player, nextAfter = { null }, dataFor = { wav }, ink = androidx.compose.ui.graphics.Color.Black) } }
        rule.waitUntil(5_000) { count("voice-card-v1") > 0 }
        assertEquals("0:01", rule.onNodeWithTag("voice-clock-v1", useUnmergedTree = true).fetchSemanticsNode().config[SemanticsProperties.Text].joinToString("") { it.text })
        rule.onNodeWithTag("voice-play-v1", useUnmergedTree = true).performClick()
        // Where the emulator has no audio output the player cannot start: then this part is skipped (the card is checked above).
        val playing = try { rule.waitUntil(8_000) { count("voice-speed-v1") > 0 }; true } catch (e: Throwable) { false }
        assumeTrue("the emulator could not play audio", playing)
        rule.onNodeWithTag("voice-speed-v1", useUnmergedTree = true).performClick()
        rule.waitUntil(5_000) { rule.onNodeWithTag("voice-speed-v1", useUnmergedTree = true).fetchSemanticsNode().config[SemanticsProperties.ContentDescription].joinToString() == "Speed 1.5 times" }
        player.stop()
    }

    /** One second of a 440 Hz tone as a WAV, 16-bit mono at 22.05 kHz. */
    private fun tone(): ByteArray {
        val rate = 22_050
        val pcm = java.io.ByteArrayOutputStream()
        for (i in 0 until rate) { val v = (Math.sin(2 * Math.PI * 440.0 * i / rate) * 0.4 * Short.MAX_VALUE).toInt(); pcm.write(v and 0xFF); pcm.write((v shr 8) and 0xFF) }
        val data = pcm.toByteArray()
        fun le(n: Int, bytes: Int) = ByteArray(bytes) { ((n shr (8 * it)) and 0xFF).toByte() }
        return "RIFF".toByteArray() + le(36 + data.size, 4) + "WAVEfmt ".toByteArray() + le(16, 4) + le(1, 2) + le(1, 2) + le(rate, 4) + le(rate * 2, 4) + le(2, 2) + le(16, 2) + "data".toByteArray() + le(data.size, 4) + data
    }

    /** The real recorder (`MediaRecorder`): where the emulator has a microphone it records a short clip; where it has none this is skipped. */
    @Test fun theRealMicrophoneRecordsAShortClipWhereThereIsOne() {
        val real = com.limemessenger.lime.chats.MediaRecorderCapture(context)
        val recorder = VoiceRecorder(real)
        assumeTrue("no microphone on this emulator", recorder.start())
        Thread.sleep(1_200); recorder.tick()
        val note = recorder.finish()
        assertTrue("a recording of about a second", note != null && note.bytes.isNotEmpty() && note.durationMs >= 1_000 && note.waveform.size == 64)
    }
}
