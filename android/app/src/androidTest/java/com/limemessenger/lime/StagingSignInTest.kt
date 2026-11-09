package com.limemessenger.lime

import androidx.compose.ui.test.assertTextEquals
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
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
import com.limemessenger.lime.ui.LinkPlaceholder
import com.limemessenger.lime.ui.Root
import com.limemessenger.lime.ui.theme.LimeTheme
import java.io.File
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * One real sign-in as Ada on STAGING through the debug "Use a test account" choice. It needs `files/test-accounts.json` in the app's
 * private folder (`android/tools/staging-test-accounts.sh --push`; tools/connected.sh does this), so it is skipped without it.
 */
@Staging
@RunWith(AndroidJUnit4::class)
class StagingSignInTest {
    @get:Rule val rule = createComposeRule()
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val alias = "lime.test.staging"
    private val dir = File(context.cacheDir, "staging-${System.nanoTime()}")

    @After fun tearDown() { dir.deleteRecursively(); KeystoreKey.delete(alias) }

    @Test fun adaSignsInThroughTheTestAccountAndTheDeviceRegisters() {
        assumeTrue("no pushed test accounts", File(context.filesDir, "test-accounts.json").exists())
        val backend = BackendConfig.current
        assumeTrue("no backend", backend != null)
        val secrets = SecureBlobStore(File(dir, "secrets"), KeyWrapper(KeystoreKey.getOrCreate(alias)))
        val session = AccountSession(
            LiveAuthService(HttpTransport(backend!!.url, backend.apiKey)), backend, StorageBootstrap(File(dir, "data"), secrets), secrets,
        )
        rule.setContent { LimeTheme { Root(session) { LinkPlaceholder(session) } } }
        rule.waitUntil(15_000) { rule.onAllNodes(hasTestTag("use-test-account")).fetchSemanticsNodes().isNotEmpty() }
        rule.onNodeWithTag("use-test-account").performClick()
        rule.onNodeWithTag("test-account-ada_android").performClick()
        try {
            rule.waitUntil(20_000) { session.phase == Phase.SignedIn && (session.deviceRegistered || session.problem != null) }
        } catch (e: Throwable) {
            throw AssertionError("phase=${session.phase} registered=${session.deviceRegistered} problem=${session.problem} user=${session.userId}", e)
        }
        assertEquals("registration problem: ${session.problem}", true, session.deviceRegistered)
        rule.onNodeWithTag("signed-in-as").assertTextEquals("Signed in as Ada Android")
        assertTrue(session.userId != null)
        assertEquals(null, session.problem)
        // Leave nothing behind: sign out on the server and remove this test's store.
        rule.runOnIdle { }
        kotlinx.coroutines.runBlocking { session.signOut(removingData = true) }
        assertEquals(Phase.SignedOut, session.phase)
    }
}
