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
import androidx.compose.ui.test.performTextClearance
import androidx.compose.ui.test.performScrollTo
import org.junit.Assert.assertNotNull
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.test.performTextClearance
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
import uniffi.lime_core.HeaderPair
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * LIME-315c on STAGING: Ada creates a band through the UI (after her own jam), reads its invite link from the Invite sheet and **logs it** (`BAND_TEST link=...`); the script (`connected.sh`) hands it to the
 * partner (`partner band-join <link>`: Ben asks to join with `join_org`, accepts Ada's chat, and prints what he sees). Ada's phone adds him when it syncs: **Members lists Ben** (bounded polling), Ada
 * makes him a **Writer**, posts **as the band**, and Ben receives it (`band: received quick "..." as jam by "Staff Room Band"`). Every assertion is on the real server.
 */
@Staging
@RunWith(AndroidJUnit4::class)
class StagingBandTest {
    @get:Rule val rule = createComposeRule()
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val alias = "lime.test.band.staging"
    private val dir = File(context.cacheDir, "staging-band-${System.nanoTime()}")

    @After fun tearDown() { dir.deleteRecursively(); KeystoreKey.delete(alias) }

    private fun count(tag: String) = rule.onAllNodes(hasTestTag(tag), useUnmergedTree = true).fetchSemanticsNodes().size
    private fun click(tag: String) = rule.onNodeWithTag(tag, useUnmergedTree = true).performClick()
    private fun until(ms: Long, why: String, check: () -> Boolean) { try { rule.waitUntil(ms) { check() } } catch (e: Throwable) { throw AssertionError("timed out: $why", e) } }
    private fun openFeed() { if (count("jam-feed") == 0) { until(30_000, "the jam tab") { count("tab-jam") > 0 }; click("tab-jam") }; until(30_000, "the feed") { count("jam-feed") > 0 } }

    @Test fun adaCreatesABandBenJoinsByTheInviteAdaMakesHimAWriterAndPostsAsTheBand() {
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

        // Ada writes to Ben first, as a teacher meets another (Ben's phone accepts it): a subscription travels like a message, so each needs the other's key.
        core.startDm(benId, "Ben Android")
        core.sendTextIdentified(session.transport!!, kotlinx.coroutines.runBlocking { session.accessToken() }, benId, "Hello Ben")

        // Pages left by earlier runs (their phones are gone) would be served first: end them (Ada's own test jams).
        fun page(json: String): String = session.transport!!.request(
            "POST", "/functions/v1/jam-page", listOf(HeaderPair("content-type", "application/json"), HeaderPair("authorization", "Bearer " + kotlinx.coroutines.runBlocking { session.accessToken() })), json.toByteArray(),
        ).body.decodeToString()
        Regex(""""jam_id":"([0-9a-f-]{36})"""").findAll(page("""{"action":"by_writer","writer_id":"${session.userId}"}""")).map { it.groupValues[1] }.toSet().forEach { page("""{"action":"end","jam_id":"$it"}""") }

        // Create the jam.
        openFeed()
        click("jam-yours-open")
        until(10_000, "the create form") { count("jam-create") > 0 }
        rule.onNodeWithTag("jam-create-title", useUnmergedTree = true).performTextInput("Ada's lab notes")
        rule.onNodeWithTag("jam-create-about", useUnmergedTree = true).performTextInput("Experiments from Ada's class")
        rule.onNodeWithTag("jam-create-topics", useUnmergedTree = true).performTextInput("science, grade 5")
        click("jam-create")
        until(30_000, "the jam to exist") { count("jam-write-post") > 0 }
        val jam = core.listMyJams().single { !it.ended }
        assertEquals(listOf("science", "grade 5"), jam.topics)

        // Ada's own space exists (above). A band: Your jam > Create a band.
        val myUser = session.userId!!
        click("band-create-open")
        until(10_000, "the create-a-band screen") { count("band-name") > 0 }
        rule.onNodeWithTag("band-name", useUnmergedTree = true).performTextInput("Staff Room Band")
        rule.onNodeWithTag("band-about", useUnmergedTree = true).performTextInput("A band made on Android")
        rule.waitUntil(10_000) { androidx.compose.ui.semantics.SemanticsProperties.Disabled !in rule.onNodeWithTag("band-make", useUnmergedTree = true).fetchSemanticsNode().config }
        rule.onNodeWithTag("band-make", useUnmergedTree = true).performScrollTo().performClick()
        until(90_000, "the band to exist") { core.listMyJams().count { !it.ended } == 2 }
        val band = core.listMyJams().first { !it.ended && it.title == "Staff Room Band" }
        // Its page: Info > Members (I am the owner) > Invite.
        until(30_000, "the band page button") { count("band-open-page") > 0 }
        click("band-open-page")
        until(10_000, "the band page") { count("band-page") > 0 }
        until(30_000, "the Members tab (the owner is a member)") { count("band-tab-members") > 0 }
        fun openMembers() { click("band-tab-members"); until(30_000, "Members") { count("band-member-$myUser") > 0 } }
        openMembers()
        assertEquals("You, Owner", rule.onNodeWithTag("band-member-$myUser", useUnmergedTree = true).fetchSemanticsNode().config[SemanticsProperties.ContentDescription].joinToString())
        click("band-invite-open")
        until(60_000, "the invite link") { count("band-invite-text") > 0 }
        val link = rule.onNodeWithTag("band-invite-text", useUnmergedTree = true).fetchSemanticsNode().config[SemanticsProperties.Text].joinToString("") { it.text }
        assertTrue(link, link.startsWith("https://limemessenger.com/b/#"))
        assertNotNull("the core reads the code of the link Ada shows", core.parseOrgInvite(link.substringAfter("/b/#")))
        android.util.Log.e("BAND_TEST", "link=$link")   // connected.sh reads this and starts the partner's band-join
        click("band-invite-close")   // close the sheet
        // Ben's request reaches Ada's phone at her next sync, and she adds him: look at Members again until he is there (bounded).
        var found = false
        for (attempt in 1..15) {
            try { rule.waitUntil(20_000) { count("band-member-$benId") > 0 }; found = true; break } catch (e: Throwable) { click("band-tab-info"); Thread.sleep(2_000); openMembers() }
        }
        assertTrue("Ben never appeared in Members; the core says ${runCatching { core.orgMembers(band.jamId).map { it.userId.take(8) + ':' + it.role } }}", found)
        // Make him a Writer.
        click("band-member-$benId")
        until(10_000, "the member sheet") { count("band-role-writer") > 0 }
        click("band-role-writer")
        until(60_000, "Ben a Writer") { rule.onNodeWithTag("band-member-$benId", useUnmergedTree = true).fetchSemanticsNode().config[SemanticsProperties.ContentDescription].joinToString().endsWith(", Writer") }
        assertEquals("writer", core.orgMembers(band.jamId).first { it.userId == benId }.role)
        // Post as the band.
        click("band-back")
        until(30_000, "Your jam") { count("jam-write-post") > 0 }
        click("jam-write-post")
        until(10_000, "the post sheet") { count("jam-compose-body") > 0 }
        rule.onNodeWithTag("jam-compose-body", useUnmergedTree = true).performTextInput("A post from the band")
        click("jam-compose-next")
        until(10_000, "Post as") { count("jam-postas-${band.jamId}") > 0 }
        click("jam-postas-${band.jamId}")
        click("jam-post")
        until(60_000, "the band's post to be stored") { core.listJamPosts(band.jamId).size == 1 }
        assertEquals("shown as the band", "jam", core.listJamPosts(band.jamId).single().displayAs)
        // Ben's side is checked from his log by connected.sh; keep the app syncing meanwhile (waitUntil lets it).
        try { rule.waitUntil(90_000) { false } } catch (e: Throwable) { }
    }
}
