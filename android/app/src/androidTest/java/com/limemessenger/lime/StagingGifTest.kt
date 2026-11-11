package com.limemessenger.lime

import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onFirst
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextInput
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
import com.limemessenger.lime.ui.Root
import com.limemessenger.lime.ui.theme.LimeTheme
import java.io.File
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** LIME-313 on STAGING: Ada sends one of lime's stickers from the GIF panel; Ben (the partner) downloads and decrypts it and says how many bytes came: the whole GIF file. */
@Staging
@RunWith(AndroidJUnit4::class)
class StagingGifTest {
    @get:Rule val rule = createComposeRule()
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val alias = "lime.test.gif.staging"
    private val dir = File(context.cacheDir, "staging-gif-${System.nanoTime()}")

    @After fun tearDown() { dir.deleteRecursively(); KeystoreKey.delete(alias) }

    private fun count(tag: String) = rule.onAllNodes(hasTestTag(tag), useUnmergedTree = true).fetchSemanticsNodes().size
    private fun click(tag: String) = rule.onNodeWithTag(tag, useUnmergedTree = true).performClick()
    private fun until(ms: Long, why: String, check: () -> Boolean) { try { rule.waitUntil(ms) { check() } } catch (e: Throwable) { throw AssertionError("timed out: $why", e) } }

    @Test fun adaSendsAStickerAndBenGetsTheWholeFile() {
        val pushed = File(context.filesDir, "test-accounts.json")
        assumeTrue("no pushed test accounts", pushed.exists())
        val backend = BackendConfig.current
        assumeTrue("no backend", backend != null)
        val benId = JSONObject(pushed.readText()).getJSONObject("accounts").getJSONObject("b").getString("user_id")
        val secrets = SecureBlobStore(File(dir, "secrets"), KeyWrapper(KeystoreKey.getOrCreate(alias)))
        val session = AccountSession(LiveAuthService(HttpTransport(backend!!.url, backend.apiKey)), backend, StorageBootstrap(File(dir, "data"), secrets), secrets)
        rule.setContent { LimeTheme { Root(session) } }
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
        until(120_000, "the chat with Ben") { count("conversation-row-$dm") > 0 }
        click("conversation-row-$dm")
        until(30_000, "Ben's first echo") { core.listMessages(dm).any { it.senderId != null && it.localState != "system" } }

        val size = com.limemessenger.lime.chats.StickerPack.bytes(context, "thank-you")!!.size
        until(10_000, "the GIF button") { count("attach-gif") > 0 }
        click("attach-gif")
        until(10_000, "the sticker") { count("gif-sticker-thank-you") > 0 }
        click("gif-sticker-thank-you")
        until(60_000, "the sticker to be sent") { core.listMessages(dm).any { m -> m.senderId == null && m.attachments.any { it.mime == "image/gif" } } }
        val mine = core.listMessages(dm).first { m -> m.senderId == null && m.attachments.any { it.mime == "image/gif" } }.attachments.first()
        assertEquals("lime-sticker-thank-you.gif", mine.name)
        until(240_000, "Ben to have the whole file") { core.listMessages(dm).any { m -> m.senderId != null && m.text.contains("got 1 photo ($size bytes)") } }
    }
}
