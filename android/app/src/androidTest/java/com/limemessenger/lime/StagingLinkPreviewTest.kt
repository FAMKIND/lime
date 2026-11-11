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
import androidx.compose.ui.test.performTextInputSelection
import androidx.compose.ui.text.TextRange
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
import androidx.compose.runtime.CompositionLocalProvider
import com.limemessenger.lime.chats.LinkPreviewFetcher
import com.limemessenger.lime.ui.chat.LocalLinkPreviewFetcher
import uniffi.lime_core.OutgoingPreview

/**
 * LIME-407 on STAGING: Ada types a link, the draft card appears (a fixed fake fetcher: no internet) and she sends it; Ben (the partner running `echo`) receives the card's fields
 * (`connected.sh` checks his log for `preview: <url>|<title>|<site>|<n> bytes`), then answers with a card of his own and Ada's bubble shows it.
 */
@Staging
@RunWith(AndroidJUnit4::class)
class StagingLinkPreviewTest {
    @get:Rule val rule = createComposeRule()
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val alias = "lime.test.linkpreview.staging"
    private val dir = File(context.cacheDir, "staging-linkpreview-${System.nanoTime()}")

    @After fun tearDown() { dir.deleteRecursively(); KeystoreKey.delete(alias) }

    private fun count(tag: String) = rule.onAllNodes(hasTestTag(tag), useUnmergedTree = true).fetchSemanticsNodes().size
    private fun click(tag: String) { rule.onNodeWithTag(tag, useUnmergedTree = true).performClick(); rule.waitForIdle() }
    private fun until(ms: Long, why: String, check: () -> Boolean) { try { rule.waitUntil(ms) { check() } } catch (e: Throwable) { throw AssertionError("timed out: $why", e) } }
    private fun type(text: String) { for (ch in text) { rule.onNodeWithTag("composer-field").performTextInput(ch.toString()); rule.waitForIdle() } }

    @Test fun adaSendsALinkWithACardBenGetsItsFieldsAndAnswersWithACard() {
        val pushed = File(context.filesDir, "test-accounts.json")
        assumeTrue("no pushed test accounts", pushed.exists())
        val backend = BackendConfig.current
        assumeTrue("no backend", backend != null)
        val benId = JSONObject(pushed.readText()).getJSONObject("accounts").getJSONObject("b").getString("user_id")
        val secrets = SecureBlobStore(File(dir, "secrets"), KeyWrapper(KeystoreKey.getOrCreate(alias)))
        val session = AccountSession(LiveAuthService(HttpTransport(backend!!.url, backend.apiKey)), backend, StorageBootstrap(File(dir, "data"), secrets), secrets)
        val fake = object : LinkPreviewFetcher() {
            override suspend fun make(address: String): OutgoingPreview {
                val jpeg = java.io.ByteArrayOutputStream().also { out -> android.graphics.Bitmap.createBitmap(64, 34, android.graphics.Bitmap.Config.ARGB_8888).also { android.graphics.Canvas(it).drawColor(0xFF4CAF50.toInt()) }.compress(android.graphics.Bitmap.CompressFormat.JPEG, 80, out) }.toByteArray()
                return OutgoingPreview(address, "Fractions made visible", "example.org", jpeg, 64u, 34u)
            }
        }
        (context.applicationContext as LimeApp).linkPreviewPrefs.change(true)
        rule.setContent { CompositionLocalProvider(LocalLinkPreviewFetcher provides fake) { LimeTheme { Root(session) } } }
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
        fun heard() = core.listMessages(dm).count { it.senderId != null && it.localState != "system" }
        type("read https://example.org/lesson")
        until(15_000, "the draft card") { count("link-draft") > 0 }
        click("send-button")
        until(60_000, "the message to be sent") { core.listMessages(dm).any { it.senderId == null && it.linkPreview != null } }
        val mine = core.listMessages(dm).first { it.senderId == null && it.linkPreview != null }
        assertEquals("Fractions made visible", mine.linkPreview!!.title)
        until(30_000, "my own card in my bubble") { count("link-card-${mine.id}") > 0 }
        until(240_000, "Ben's answer with his card") { core.listMessages(dm).any { it.senderId != null && it.linkPreview != null } }
        val his = core.listMessages(dm).first { it.senderId != null && it.linkPreview != null }
        assertEquals("Ben's lesson page", his.linkPreview!!.title)
        until(60_000, "Ben's card in the bubble") { count("link-card-${his.id}") > 0 }
        // The real chat, for the screenshots (connected.sh pulls files/shots before it cleans up).
        Thread.sleep(2_500)
        File(context.filesDir, "shots").also { it.mkdirs() }.let { d ->
            val bmp = InstrumentationRegistry.getInstrumentation().uiAutomation.takeScreenshot()
            File(d, "15-link-bubble-real-chat.png").outputStream().use { bmp.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it) }
        }
    }
}
