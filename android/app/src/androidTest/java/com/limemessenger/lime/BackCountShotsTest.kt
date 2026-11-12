package com.limemessenger.lime

import android.graphics.Bitmap
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.unit.Density
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.limemessenger.lime.chats.ChatsModel
import com.limemessenger.lime.keys.KeyWrapper
import com.limemessenger.lime.keys.KeystoreKey
import com.limemessenger.lime.keys.SecureBlobStore
import com.limemessenger.lime.storage.StorageBootstrap
import com.limemessenger.lime.ui.chat.Header
import com.limemessenger.lime.ui.theme.Lime
import com.limemessenger.lime.ui.theme.LimeTheme
import java.io.File
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import uniffi.lime_core.LimeStore

/** NOT a test: the Back-with-a-number screenshots of LIME-409 into files/shots (`tools/shots-409.sh`). `@Staging` only so the plain pass skips it. */
@Staging
@RunWith(AndroidJUnit4::class)
class BackCountShotsTest {
    @get:Rule val rule = createComposeRule()
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private lateinit var dir: File
    private lateinit var store: LimeStore
    private lateinit var chats: ChatsModel
    private val alias = "lime.test.backcount.shots"

    @Before fun setUp() {
        dir = File(context.cacheDir, "backshots-${System.nanoTime()}").also { it.mkdirs() }
        val secrets = SecureBlobStore(File(dir, "secrets"), KeyWrapper(KeystoreKey.getOrCreate(alias)))
        val storage = StorageBootstrap(File(dir, "data"), secrets)
        store = storage.open(storage.space("backshots-user")).store
        store.seedSampleDataIfEmpty()
        chats = ChatsModel(store = { store }, transport = { null }, token = { "t" }, staleToken = { "t" })
        runBlocking { chats.reload() }
    }
    @After fun tearDown() { store.close(); dir.deleteRecursively(); KeystoreKey.delete(alias) }

    private fun shot(name: String) {
        rule.waitForIdle(); Thread.sleep(500)
        val bitmap = InstrumentationRegistry.getInstrumentation().uiAutomation.takeScreenshot()
        File(File(context.filesDir, "shots").also { it.mkdirs() }, "$name.png").outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
    }
    private fun header(count: Int, dark: Boolean = false, font: Float = 1f, name: String) {
        val summary = chats.chats.first { it.title.startsWith("Autumn") }
        rule.setContent {
            val d = LocalDensity.current
            CompositionLocalProvider(LocalDensity provides Density(d.density, font)) {
                LimeTheme(dark = dark) {
                    Column(Modifier.fillMaxSize().background(Lime.colors.canvas).systemBarsPadding()) { Header(summary, "Me", 0, count, {}, {}, {}) }
                }
            }
        }
        shot(name)
    }
    @Test fun none() = header(0, name = "1-back-none")
    @Test fun three() = header(3, name = "2-back-3")
    @Test fun ninetyNinePlus() = header(120, name = "3-back-99plus")
    @Test fun largestFont() = header(3, font = 2f, name = "4-back-3-font-2")
    @Test fun largestFontOver99() = header(120, font = 2f, name = "5-back-99plus-font-2")
    @Test fun dark() = header(3, dark = true, name = "6-back-3-dark")
}
