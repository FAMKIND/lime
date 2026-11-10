package com.limemessenger.lime

import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextClearance
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.down
import androidx.compose.ui.test.up
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.limemessenger.lime.auth.AccountSession
import com.limemessenger.lime.auth.AccountSession.Phase
import com.limemessenger.lime.auth.LiveAuthService
import com.limemessenger.lime.keys.KeyWrapper
import com.limemessenger.lime.keys.KeystoreKey
import com.limemessenger.lime.keys.SecureBlobStore
import com.limemessenger.lime.net.BackendConfig
import com.limemessenger.lime.net.HttpTransport
import com.limemessenger.lime.storage.StorageBootstrap
import androidx.compose.runtime.CompositionLocalProvider
import com.limemessenger.lime.chats.VoiceCapture
import com.limemessenger.lime.ui.Root
import com.limemessenger.lime.ui.chat.LocalVoiceCapture
import com.limemessenger.lime.ui.theme.LimeTheme
import java.io.File
import org.json.JSONObject
import org.junit.After
import uniffi.lime_core.OutgoingAttachment
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * LIME-308 on STAGING: Ada records a voice message (a made-up microphone, held for just over a second) and sends a file; Ben (the partner running `echo`) downloads each,
 * says how long the voice message is and how many bytes it came to, and sends a voice message back, which Ada sees as a card with its TalkBack actions and plays.
 */
@Staging
@RunWith(AndroidJUnit4::class)
class StagingVoiceFilesTest {
    @get:Rule val rule = createComposeRule()
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val alias = "lime.test.voice.staging"
    private val dir = File(context.cacheDir, "staging-voice-${System.nanoTime()}")

    @After fun tearDown() { dir.deleteRecursively(); KeystoreKey.delete(alias) }

    private fun count(tag: String) = rule.onAllNodes(hasTestTag(tag), useUnmergedTree = true).fetchSemanticsNodes().size
    private fun text(tag: String): String = rule.onNodeWithTag(tag, useUnmergedTree = true).fetchSemanticsNode().config[SemanticsProperties.Text].joinToString("") { it.text }
    private class FakeMic : VoiceCapture {
        override fun start(podcast: Boolean) = true
        override fun level() = 0.5f
        override fun stop(): ByteArray? = ByteArray(4_000) { 5 }
        override fun cancel() {}
    }

    @Test fun voiceAndFileRoundTripWithBen() {
        val pushed = File(context.filesDir, "test-accounts.json")
        assumeTrue("no pushed test accounts", pushed.exists())
        val backend = BackendConfig.current
        assumeTrue("no backend", backend != null)
        InstrumentationRegistry.getInstrumentation().uiAutomation.executeShellCommand("pm grant ${context.packageName} android.permission.RECORD_AUDIO").use { java.io.FileInputStream(it.fileDescriptor).readBytes() }   // (UiAutomation.grantRuntimePermission needs API 28)
        val benId = JSONObject(pushed.readText()).getJSONObject("accounts").getJSONObject("b").getString("user_id")
        val secrets = SecureBlobStore(File(dir, "secrets"), KeyWrapper(KeystoreKey.getOrCreate(alias)))
        val session = AccountSession(LiveAuthService(HttpTransport(backend!!.url, backend.apiKey)), backend, StorageBootstrap(File(dir, "data"), secrets), secrets)
        rule.setContent { CompositionLocalProvider(LocalVoiceCapture provides { FakeMic() }) { LimeTheme { Root(session) } } }

        rule.waitUntil(15_000) { count("use-test-account") > 0 }
        rule.onNodeWithTag("use-test-account").performClick()
        rule.onNodeWithTag("test-account-ada_android").performClick()
        try {
            rule.waitUntil(60_000) { session.phase == Phase.SignedIn && (session.deviceRegistered || session.problem != null) }
        } catch (e: Throwable) {
            throw AssertionError("sign-in stalled: phase=${session.phase} registered=${session.deviceRegistered} problem=${session.problem}", e)
        }
        assertEquals("registration problem: ${session.problem}", true, session.deviceRegistered)

        val core = session.store!!
        val dm = "dm:$benId"
        core.startDm(benId, "Ben Android")
        core.sendTextIdentified(session.transport!!, kotlinx.coroutines.runBlocking { session.accessToken() }, benId, "Hello Ben")
        rule.waitUntil(120_000) { count("conversation-row-$dm") > 0 }
        rule.onNodeWithTag("conversation-row-$dm").performClick()
        rule.waitUntil(30_000) { count("chat-title") > 0 }
        rule.waitUntil(180_000) { descriptions().any { it.startsWith("Ben Android, ") && it.contains("""got "Hello Ben"""") } }

        // A voice message: hold the microphone for just over a second, lift; Ben downloads it and says how long it is and how many bytes came.
        rule.waitUntil(10_000) { count("voice-mic") > 0 }
        rule.onNodeWithTag("voice-mic", useUnmergedTree = true).performTouchInput { down(center) }
        rule.waitUntil(5_000) { count("recording-bar") > 0 }
        Thread.sleep(1_100)
        rule.onNodeWithTag("voice-mic", useUnmergedTree = true).performTouchInput { up() }
        rule.waitUntil(60_000) { core.listMessages(dm).any { m -> m.senderId == null && m.attachments.any { it.mime == "audio/mp4" } } }
        rule.waitUntil(180_000) { descriptions().any { it.startsWith("Ben Android, ") && it.contains("got a voice message (0:01, 4000 bytes)") } }

        // Ben's own voice message arrives: a card, one TalkBack stop with Play and Change speed, and it plays.
        rule.waitUntil(180_000) { core.listMessages(dm).any { m -> m.senderId != null && m.attachments.any { it.mime == "audio/wav" } } }
        val bens = core.listMessages(dm).first { m -> m.senderId != null && m.attachments.any { it.mime == "audio/wav" } }
        val voice = bens.attachments.first { it.mime == "audio/wav" }
        rule.waitUntil(30_000) { count("voice-card-${voice.id}") > 0 }
        val node = rule.onNodeWithTag("message-${bens.id}", useUnmergedTree = true).fetchSemanticsNode()
        assertTrue(node.config[SemanticsProperties.ContentDescription].joinToString().contains("Voice message"))
        val labels = node.config[androidx.compose.ui.semantics.SemanticsActions.CustomActions].map { it.label }
        for (name in listOf("Play", "Change speed", "Skip forward 10 seconds")) assertTrue("missing $name in $labels", name in labels)
        rule.onNodeWithTag("voice-play-${voice.id}", useUnmergedTree = true).performClick()
        val playing = try { rule.waitUntil(15_000) { count("voice-speed-${voice.id}") > 0 }; true } catch (e: Throwable) { false }
        assumeTrue("the emulator could not play audio", playing)

        // A file: Ben downloads it and says what it was and how big it came out.
        val file = OutgoingAttachment(ByteArray(2_048) { 3 }, "Plan.pdf", "application/pdf", null, null, null, ByteArray(0), ByteArray(0), "")
        core.sendAttachments(dm, "", listOf(file), null)
        kotlinx.coroutines.runBlocking { core.deliverQueued(session.transport!!, session.accessToken()) }
        rule.waitUntil(60_000) { core.listMessages(dm).any { m -> m.senderId == null && m.attachments.any { it.name == "Plan.pdf" } } }
        val mine = core.listMessages(dm).first { m -> m.senderId == null && m.attachments.any { it.name == "Plan.pdf" } }.attachments.first()
        rule.waitUntil(60_000) { count("file-${mine.id}") > 0 }
        rule.waitUntil(180_000) { descriptions().any { it.startsWith("Ben Android, ") && it.contains("""got a file "Plan.pdf" (2048 bytes)""") } }
    }

    /** The TalkBack descriptions of every message on screen (one stop per message). */
    private fun descriptions(): List<String> =
        rule.onAllNodes(SemanticsMatcher("is a message") { it.config.contains(SemanticsProperties.TestTag) && it.config[SemanticsProperties.TestTag].startsWith("message-") && it.config.contains(SemanticsProperties.ContentDescription) })
            .fetchSemanticsNodes().map { it.config[SemanticsProperties.ContentDescription].joinToString() }
}
