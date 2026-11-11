package com.limemessenger.lime

import android.graphics.Bitmap
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.down
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.up
import androidx.compose.ui.unit.Density
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.limemessenger.lime.chats.ChatModel
import com.limemessenger.lime.chats.ChatsModel
import com.limemessenger.lime.chats.VoiceCapture
import com.limemessenger.lime.keys.KeyWrapper
import com.limemessenger.lime.keys.KeystoreKey
import com.limemessenger.lime.keys.SecureBlobStore
import com.limemessenger.lime.storage.StorageBootstrap
import com.limemessenger.lime.ui.chat.ChatScreen
import com.limemessenger.lime.ui.chat.LocalVoiceCapture
import com.limemessenger.lime.ui.theme.LimeTheme
import java.io.ByteArrayOutputStream
import java.io.File
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import uniffi.lime_core.LimeStore
import uniffi.lime_core.OutgoingAttachment

/**
 * NOT a test of anything: takes the composer's screenshots (LIME-403) into files/shots for `tools/shots-403.sh`. A chat from the core's sample data, no network.
 * Marked `@Staging` only so the plain pass skips it (the script runs it by class name).
 */
@Staging
@RunWith(AndroidJUnit4::class)
class ComposerShotsTest {
    @get:Rule val rule = createComposeRule()
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val shots get() = File(context.filesDir, "shots").also { it.mkdirs() }
    private lateinit var dir: File
    private lateinit var store: LimeStore
    private lateinit var chats: ChatsModel
    private lateinit var chat: ChatModel
    private val alias = "lime.test.composer.shots"

    @Before fun setUp() {
        dir = File(context.cacheDir, "composershots-${System.nanoTime()}").also { it.mkdirs() }
        val secrets = SecureBlobStore(File(dir, "secrets"), KeyWrapper(KeystoreKey.getOrCreate(alias)))
        val storage = StorageBootstrap(File(dir, "data"), secrets)
        store = storage.open(storage.space("shots-user")).store
        store.seedSampleDataIfEmpty()
        chats = ChatsModel(store = { store }, transport = { null }, token = { "t" }, staleToken = { "t" })
        runBlocking { chats.reload() }
        chat = ChatModel(chats.chats.first { it.title == "Autumn Reyes" }.id, chats, accountSignedIn = false)
    }

    @After fun tearDown() { store.close(); dir.deleteRecursively(); KeystoreKey.delete(alias) }

    private class FakeMic : VoiceCapture {
        override fun start(podcast: Boolean) = true
        override fun level() = 0.6f
        override fun stop(): ByteArray? = ByteArray(4_000) { 5 }
        override fun cancel() {}
    }
    private fun shot(name: String) {
        rule.waitForIdle()
        Thread.sleep(600)
        val bitmap = InstrumentationRegistry.getInstrumentation().uiAutomation.takeScreenshot()
        File(shots, "$name.png").outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
    }
    private fun photo(): OutgoingAttachment {
        val bitmap = Bitmap.createBitmap(240, 160, Bitmap.Config.ARGB_8888).also { b -> android.graphics.Canvas(b).drawColor(0xFF9AD4A8.toInt()) }
        val out = ByteArrayOutputStream().also { bitmap.compress(Bitmap.CompressFormat.JPEG, 90, it) }.toByteArray()
        return OutgoingAttachment(out, "a.jpg", "image/jpeg", 240u, 160u, null, ByteArray(0), ByteArray(0), "")
    }
    private fun show(fontScale: Float = 1f, dark: Boolean = false, photos: List<OutgoingAttachment> = emptyList()) = rule.setContent {
        val d = LocalDensity.current
        CompositionLocalProvider(LocalDensity provides Density(d.density, fontScale), LocalVoiceCapture provides { FakeMic() }) {
            LimeTheme(dark = dark) { ChatScreen(chat, chats, onBack = {}, seedPhotos = photos) }
        }
        androidx.compose.runtime.LaunchedEffect(Unit) { chat.reload() }
    }

    @Test fun empty() { show(); rule.waitUntil(5_000) { chat.messages.isNotEmpty() }; shot("1-empty") }

    @Test fun longMessage() {
        show(); rule.waitUntil(5_000) { chat.messages.isNotEmpty() }
        rule.onNodeWithTag("composer-field").performTextInput("Hello team,\nlunch at noon?\nPlease bring your notes\nfor the Friday review.\nThe room is 204.\nSee you there!")
        shot("2-six-lines")
    }

    @Test fun photoDraft() {
        show(photos = listOf(photo(), photo())); rule.waitUntil(5_000) { chat.messages.isNotEmpty() }
        rule.onNodeWithTag("composer-field").performTextInput("Look at the bridges")
        shot("3-photo-draft")
    }

    @Test fun recording() {
        show(); rule.waitUntil(5_000) { chat.messages.isNotEmpty() }
        rule.onNodeWithTag("voice-mic", useUnmergedTree = true).performTouchInput { down(center) }
        rule.waitUntil(5_000) { rule.onAllNodes(hasTestTag("recording-bar"), useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty() }
        Thread.sleep(1_200); shot("4-recording")
        rule.onNodeWithTag("voice-mic", useUnmergedTree = true).performTouchInput { up() }
    }

    @Test fun largestFont() {
        show(fontScale = 2f); rule.waitUntil(5_000) { chat.messages.isNotEmpty() }
        rule.onNodeWithTag("composer-field").performTextInput("Hello team, lunch at noon?")
        shot("5-font-2")
    }

    @Test fun dark() {
        show(dark = true); rule.waitUntil(5_000) { chat.messages.isNotEmpty() }
        rule.onNodeWithTag("composer-field").performTextInput("Hello")
        shot("6-dark")
    }
}
