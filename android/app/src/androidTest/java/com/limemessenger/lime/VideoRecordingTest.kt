package com.limemessenger.lime

import android.media.MediaMetadataRetriever
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.limemessenger.lime.chats.VideoProcessing
import com.limemessenger.lime.ui.chat.LocalVideoPermissions
import com.limemessenger.lime.ui.chat.VideoPermissions
import com.limemessenger.lime.ui.chat.VideoRecorderScreen
import com.limemessenger.lime.ui.theme.LimeTheme
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** LIME-314 on the emulator: the permission explanation and the denied path (a fake system that says no), and a real CameraX recording through preview and "Add to message". */
@RunWith(AndroidJUnit4::class)
class VideoRecordingTest {
    @get:Rule val rule = createComposeRule()
    private fun grantAll() {
        val ui = InstrumentationRegistry.getInstrumentation().uiAutomation
        for (p in listOf(android.Manifest.permission.CAMERA, android.Manifest.permission.RECORD_AUDIO)) ui.executeShellCommand("pm grant ${context.packageName} $p").use { f -> java.io.FileInputStream(f.fileDescriptor).readBytes() }   // (grantRuntimePermission needs API 28)
    }
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private fun count(tag: String) = rule.onAllNodes(hasTestTag(tag), useUnmergedTree = true).fetchSemanticsNodes().size
    private fun ready(tag: String) = rule.onAllNodes(hasTestTag(tag), useUnmergedTree = true).fetchSemanticsNodes().firstOrNull()?.config?.let { androidx.compose.ui.semantics.SemanticsProperties.Disabled !in it } == true
    /** Waits for the camera to bind; where CameraX cannot (the API 26 emulator's camera never becomes usable), the test is skipped and says so (LIME-314: never faked). */
    private fun awaitCamera() {
        val deadline = System.currentTimeMillis() + 30_000
        while (System.currentTimeMillis() < deadline && !ready("video-record") && count("video-problem") == 0) { rule.waitForIdle(); Thread.sleep(250) }
        assumeTrue("this emulator's camera cannot record with CameraX (not ready after 30 s, problem shown: ${count("video-problem") > 0})", ready("video-record"))
    }
    private fun leftovers() = context.cacheDir.listFiles { f -> f.name.startsWith("lime-video-") || f.name.startsWith("clean-lime-video-") }.orEmpty().size

    private class Says(val has: Boolean, val answer: Boolean) : VideoPermissions {
        var asked = 0
        override fun granted(context: android.content.Context) = has
        @androidx.compose.runtime.Composable override fun requester(onResult: (Boolean) -> Unit): () -> Unit = { asked++; onResult(answer) }
    }

    @Test fun theFirstUseExplainsBeforeAskingAndARefusalShowsWhyAndTheSettingsLinkNotACrash() {
        val says = Says(has = false, answer = false)
        var closed = false
        rule.setContent { CompositionLocalProvider(LocalVideoPermissions provides says) { LimeTheme { VideoRecorderScreen(onClose = { closed = true }, onUse = {}) } } }
        rule.waitUntil(5_000) { count("video-explain") > 0 }
        assertEquals("the explanation comes first; nothing has been asked yet", 0, says.asked)
        rule.onNodeWithTag("video-allow", useUnmergedTree = true).performClick()
        rule.waitUntil(5_000) { count("video-denied") > 0 }
        assertEquals(1, says.asked)
        assertEquals(1, count("video-open-settings"))
        assertEquals("no camera was started", 0, count("video-record"))
        rule.onNodeWithTag("video-close", useUnmergedTree = true).performClick()
        rule.waitUntil(5_000) { closed }
    }

    @Test fun aRecordingGoesThroughPreviewAndBecomesAnAttachmentWithNoPlaceAndNoLeftovers() {
        grantAll()
        val cameras = context.packageManager.hasSystemFeature(android.content.pm.PackageManager.FEATURE_CAMERA_ANY)
        assumeTrue("this emulator has no camera", cameras)
        val made = arrayOfNulls<VideoProcessing.Made>(1)
        rule.setContent { LimeTheme { VideoRecorderScreen(onClose = {}, onUse = { made[0] = it }) } }
        awaitCamera()
        rule.onNodeWithTag("video-record", useUnmergedTree = true).performClick()
        rule.waitUntil(10_000) { count("video-stop") > 0 }
        Thread.sleep(3_500)
        rule.onNodeWithTag("video-stop", useUnmergedTree = true).performClick()
        rule.waitUntil(20_000) { count("video-send") > 0 || count("video-problem") > 0 }
        assertEquals("a recording was made", 0, count("video-problem"))
        rule.onNodeWithTag("video-send", useUnmergedTree = true).performClick()
        rule.waitUntil(30_000) { made[0] != null }
        val item = made[0]!!.attachment
        assertEquals("video/mp4", item.mime)
        assertTrue("about 3 seconds, was ${item.durationMs}", (item.durationMs ?: 0u) in 2_000u..8_000u)
        assertTrue(item.bytes.size in 1_000..VideoProcessing.MAX_BYTES)
        assertTrue("a sharp poster of at most 30 KB: ${item.poster.size}", item.poster.size in 1..VideoProcessing.MAX_POSTER_BYTES)
        assertTrue("a tiny preview of at most 2 KB: ${item.thumb.size}", item.thumb.size <= 2048)
        // No place, no recorder tags: the bytes sent carry no location.
        val file = File(context.cacheDir, "check-meta.mp4").also { it.writeBytes(item.bytes) }
        val r = MediaMetadataRetriever().also { it.setDataSource(file.absolutePath) }
        assertNull("no location in the video", r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_LOCATION))
        r.release(); file.delete()
        assertEquals("the temporary recording was deleted after it was prepared", 0, leftovers())
    }

    @Test fun retakeDeletesTheRecordingAndGoesBackToTheCamera() {
        grantAll()
        val cameras = context.packageManager.hasSystemFeature(android.content.pm.PackageManager.FEATURE_CAMERA_ANY)
        assumeTrue("this emulator has no camera", cameras)
        rule.setContent { LimeTheme { VideoRecorderScreen(onClose = {}, onUse = {}) } }
        awaitCamera()
        rule.onNodeWithTag("video-record", useUnmergedTree = true).performClick()
        rule.waitUntil(10_000) { count("video-stop") > 0 }
        Thread.sleep(2_500)
        rule.onNodeWithTag("video-stop", useUnmergedTree = true).performClick()
        rule.waitUntil(20_000) { count("video-retake") > 0 }
        rule.onNodeWithTag("video-retake", useUnmergedTree = true).performClick()
        rule.waitUntil(20_000) { count("video-record") > 0 }
        assertEquals("the first recording is gone", 0, leftovers())
    }

    @Test fun aVideoTileIsOneTalkBackStopWithItsLengthAndAPlayActionAndAnUnavailableClipSaysSoWithoutACrash() {
        val dir = java.io.File(context.cacheDir, "videotile-${System.nanoTime()}").also { it.mkdirs() }
        val secrets = com.limemessenger.lime.keys.SecureBlobStore(java.io.File(dir, "secrets"), com.limemessenger.lime.keys.KeyWrapper(com.limemessenger.lime.keys.KeystoreKey.getOrCreate("lime.test.videotile")))
        val storage = com.limemessenger.lime.storage.StorageBootstrap(java.io.File(dir, "data"), secrets)
        val store = storage.open(storage.space("videotile-user")).store
        try {
            val chats = com.limemessenger.lime.chats.ChatsModel(store = { store }, transport = { null }, token = { "t" }, staleToken = { "t" })
            val model = com.limemessenger.lime.chats.ChatModel(store.startDm("ben-test", "Ben Test"), chats, accountSignedIn = false)
            val a = uniffi.lime_core.AttachmentInfo("clip1", "video/mp4", "Video.mp4", 118_377uL, 720u, 1280u, 83_000u, ByteArray(0), ByteArray(0), "", "", false, false)
            rule.setContent { LimeTheme { com.limemessenger.lime.ui.chat.VideoTile(a, model) } }
            val node = rule.onNodeWithTag("video-clip1", useUnmergedTree = true).fetchSemanticsNode()
            assertEquals("Video, 1:23", node.config[androidx.compose.ui.semantics.SemanticsProperties.ContentDescription].joinToString())
            assertTrue("a Play action for TalkBack", node.config[androidx.compose.ui.semantics.SemanticsActions.CustomActions].any { it.label == "Play video" })
            rule.onNodeWithTag("video-clip1", useUnmergedTree = true).performClick()
            rule.waitUntil(5_000) { count("video-failed") > 0 }   // nothing to download in a local-only store: it says so (the words), no crash
            assertEquals(0, count("video-player"))
        } finally { store.close(); dir.deleteRecursively(); com.limemessenger.lime.keys.KeystoreKey.delete("lime.test.videotile") }
    }
}
