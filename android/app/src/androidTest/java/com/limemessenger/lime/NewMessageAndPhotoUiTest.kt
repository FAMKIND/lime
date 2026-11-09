package com.limemessenger.lime

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.media.ExifInterface
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.assertTextEquals
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextInput
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.limemessenger.lime.chats.AttachmentProcessing
import com.limemessenger.lime.chats.ChatsModel
import com.limemessenger.lime.keys.KeyWrapper
import com.limemessenger.lime.keys.KeystoreKey
import com.limemessenger.lime.keys.SecureBlobStore
import com.limemessenger.lime.storage.StorageBootstrap
import com.limemessenger.lime.ui.chats.NewMessageScreen
import com.limemessenger.lime.ui.theme.LimeTheme
import java.io.File
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import uniffi.lime_core.FoundUser
import uniffi.lime_core.LimeStore

/** New message with a fake lookup (a found teacher, an unknown one, myself, a problem) and the photo rules on real bitmaps. */
@RunWith(AndroidJUnit4::class)
class NewMessageAndPhotoUiTest {
    @get:Rule val rule = createComposeRule()
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private lateinit var dir: File
    private lateinit var store: LimeStore
    private lateinit var chats: ChatsModel
    private val alias = "lime.test.newmsg"
    private var closed = false
    private var opened: String? = null
    private var started: Pair<String, String>? = null
    private var lookupResult: () -> FoundUser? = { null }

    @Before fun setUp() {
        dir = File(context.cacheDir, "newmsg-${System.nanoTime()}").also { it.mkdirs() }
        val secrets = SecureBlobStore(File(dir, "secrets"), KeyWrapper(KeystoreKey.getOrCreate(alias)))
        val storage = StorageBootstrap(File(dir, "data"), secrets)
        store = storage.open(storage.space("newmsg-user")).store
        store.seedSampleDataIfEmpty()
        chats = ChatsModel(store = { store }, transport = { null }, token = { "t" }, staleToken = { "t" })
        runBlocking { chats.reload() }
    }

    @After fun tearDown() { store.close(); dir.deleteRecursively(); KeystoreKey.delete(alias) }

    private fun show() = rule.setContent {
        LimeTheme {
            NewMessageScreen(chats, onClose = { closed = true }, onOpenChat = { opened = it },
                find = { lookupResult() }, startChat = { id, name -> started = id to name; "dm:$id" })
        }
    }

    private fun count(tag: String) = rule.onAllNodes(hasTestTag(tag), useUnmergedTree = true).fetchSemanticsNodes().size
    private fun person(self: Boolean = false) = FoundUser("grace-id", "Grace Ortiz", "grace.h", "Park School", "👋", "Happy to help", self)

    @Test fun nextIsOffUntilTheTextIsACompleteUsernameOrEmail() {
        show()
        rule.onNodeWithTag("new-message-next").assertIsNotEnabled()
        rule.onNodeWithTag("new-message-field").performTextInput("gr")
        rule.onNodeWithTag("new-message-next").assertIsNotEnabled()
        rule.onNodeWithTag("new-message-field").performTextInput("ace.h")
        rule.onNodeWithTag("new-message-next").assertIsEnabled()
    }

    @Test fun aFoundTeacherOpensTheChatWhenTapped() {
        lookupResult = { person() }
        show()
        rule.onNodeWithTag("new-message-field").performTextInput("grace.h")
        rule.onNodeWithTag("new-message-next").performClick()
        rule.waitUntil(5_000) { count("lookup-result") > 0 }
        rule.onNodeWithTag("lookup-name", useUnmergedTree = true).assertTextEquals("Grace Ortiz")
        rule.onNodeWithTag("lookup-result").performClick()
        rule.waitUntil(5_000) { opened != null }
        assertEquals("grace-id" to "Grace Ortiz", started); assertEquals("dm:grace-id", opened)
    }

    @Test fun anUnknownTeacherAndMyselfAndAProblemSaySo() {
        lookupResult = { null }
        show()
        rule.onNodeWithTag("new-message-field").performTextInput("nobody_here")
        rule.onNodeWithTag("new-message-next").performClick()
        rule.waitUntil(5_000) { count("lookup-none") > 0 }
        rule.onNodeWithTag("lookup-none").assertTextEquals("No teacher found with that username or email.")
        lookupResult = { person(self = true) }
        rule.onNodeWithTag("new-message-field").performTextInput("2")   // editing resets, then search again
        rule.onNodeWithTag("new-message-next").performClick()
        rule.waitUntil(5_000) { count("lookup-self") > 0 }
        rule.onNodeWithTag("lookup-self").assertTextEquals("That's you. Try another teacher.")
        lookupResult = { throw uniffi.lime_core.StoreException.Network() }
        rule.onNodeWithTag("new-message-field").performTextInput("3")
        rule.onNodeWithTag("new-message-next").performClick()
        rule.waitUntil(5_000) { count("lookup-problem") > 0 }
        rule.onNodeWithTag("lookup-problem").assertTextEquals("You're offline. Check your connection and try again.")
    }

    @Test fun theTeachersIAlreadyMessageAreListedAndFilteredAndOpenTheirChat() {
        show()
        rule.onNodeWithTag("known-teachers").assertIsDisplayed()
        val autumn = chats.chats.first { it.title == "Autumn Reyes" }.members.first()
        rule.onNodeWithTag("known-${autumn.id}", useUnmergedTree = true).assertIsDisplayed()
        rule.onNodeWithTag("new-message-field").performTextInput("autu")
        rule.waitUntil(5_000) { count("known-${chats.chats.first { it.title == "Journey Park" }.members.first().id}") == 0 }
        rule.onNodeWithTag("known-${autumn.id}", useUnmergedTree = true).performClick()
        rule.waitUntil(5_000) { opened != null }
        assertEquals(autumn.id to "Autumn Reyes", started)
    }

    @Test fun closeLeaves() {
        show()
        rule.onNodeWithTag("new-message-close").performClick()
        assertTrue(closed)
    }

    // The photo rules on real pictures

    @Test fun aPhotoIsUprightTwoThousandAtMostStrippedOfMetadataWithATinyPreview() {
        val source = Bitmap.createBitmap(3000, 1500, Bitmap.Config.ARGB_8888)
        Canvas(source).apply { drawColor(Color.rgb(9, 169, 80)); drawRect(0f, 0f, 1500f, 750f, android.graphics.Paint().apply { color = Color.RED }) }
        val file = File(dir, "wide.jpg")
        file.outputStream().use { source.compress(Bitmap.CompressFormat.JPEG, 90, it) }
        // Camera details a phone writes: a rotation (the picture is stored sideways) and a GPS position.
        ExifInterface(file.path).apply {
            setAttribute(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_ROTATE_90.toString())
            setAttribute(ExifInterface.TAG_GPS_LATITUDE, "40/1,42/1,46/1"); setAttribute(ExifInterface.TAG_GPS_LATITUDE_REF, "N")
            setAttribute(ExifInterface.TAG_MAKE, "Pixel"); saveAttributes()
        }
        assertTrue(ExifInterface(file.path).getAttribute(ExifInterface.TAG_MAKE) == "Pixel")   // the input really carries them
        val photo = AttachmentProcessing.photo(context.contentResolver, android.net.Uri.fromFile(file))!!
        assertEquals("image/jpeg", photo.mime)
        // Upright: stored 3000x1500 with a 90 degree rotation = 1500x3000 on screen, fitted to 2048 on the long edge.
        assertEquals(1024u, photo.width); assertEquals(2048u, photo.height)
        assertTrue(photo.bytes.isNotEmpty() && photo.bytes.size < AttachmentProcessing.MAX_FILE_BYTES)
        // No metadata left: no EXIF block, no GPS, no camera.
        val text = String(photo.bytes, Charsets.ISO_8859_1)
        assertFalse("Exif marker survived", text.contains("Exif"))
        assertFalse(text.contains("Pixel"))
        val out = File(dir, "out.jpg").also { it.writeBytes(photo.bytes) }
        assertEquals(null, ExifInterface(out.path).getAttribute(ExifInterface.TAG_GPS_LATITUDE)); assertEquals(null, ExifInterface(out.path).getAttribute(ExifInterface.TAG_MAKE))
        // A tiny preview: a real, small JPEG.
        assertTrue(photo.thumb.isNotEmpty() && photo.thumb.size <= AttachmentProcessing.MAX_THUMB_BYTES)
        val decoded = android.graphics.BitmapFactory.decodeByteArray(photo.bytes, 0, photo.bytes.size)
        assertEquals(1024, decoded.width); assertEquals(2048, decoded.height)
        assertNotEquals(0, decoded.getPixel(decoded.width / 2, decoded.height / 2))
        assertEquals("", photo.alt)
    }

    @Test fun anUnreadableFileIsNotAPhoto() {
        val bad = File(dir, "bad.jpg").also { it.writeText("not a picture") }
        assertEquals(null, AttachmentProcessing.photo(context.contentResolver, android.net.Uri.fromFile(bad)))
    }
}
