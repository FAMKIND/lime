package com.limemessenger.lime

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.limemessenger.lime.keys.KeyWrapper
import com.limemessenger.lime.keys.KeystoreKey
import com.limemessenger.lime.keys.SecureBlobStore
import com.limemessenger.lime.net.BackendConfig
import com.limemessenger.lime.net.HttpTransport
import com.limemessenger.lime.storage.StorageBootstrap
import java.io.File
import java.time.Instant
import org.junit.After
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class FoundationsTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private lateinit var dir: File
    private val alias = "lime.test.wrap"

    @Before
    fun setUp() {
        dir = File(context.cacheDir, "foundations-${System.nanoTime()}").also { it.mkdirs() }
    }

    @After
    fun tearDown() {
        dir.deleteRecursively()
        KeystoreKey.delete(alias)
    }

    private fun bootstrap(): StorageBootstrap {
        val blobs = SecureBlobStore(File(dir, "secrets"), KeyWrapper(KeystoreKey.getOrCreate(alias)))
        return StorageBootstrap(File(dir, "data"), blobs)
    }

    @Test
    fun keystoreWrapperRoundTrips() {
        val wrapper = KeyWrapper(KeystoreKey.getOrCreate(alias))
        val secret = KeyWrapper.randomBytes(32)
        assertArrayEquals(secret, wrapper.open(wrapper.seal(secret)))
        // The same Keystore key comes back the next time.
        assertArrayEquals(secret, KeyWrapper(KeystoreKey.getOrCreate(alias)).open(wrapper.seal(secret)))
    }

    @Test
    fun storeOpensClosesAndReopensWithTheSameKey() {
        val storage = bootstrap()
        val space = storage.space("user-1")
        val first = storage.open(space)
        assertEquals(false, first.startedFresh)
        assertTrue(storage.rejectsWrongKey(first.path))
        first.store.close()
        val second = storage.open(space)
        assertEquals(false, second.startedFresh)
        second.store.close()
        assertTrue(File(first.path).length() > 0)
    }

    @Test
    fun aMissingKeyMovesTheOldDatabaseAsideAndStartsFresh() {
        val storage = bootstrap()
        val space = storage.space("user-2")
        storage.open(space).store.close()
        // Simulate a restore without the key.
        File(dir, "secrets").deleteRecursively()
        val again = storage.open(space, Instant.parse("2026-11-09T10:00:00Z"))
        assertEquals(true, again.startedFresh)
        again.store.close()
        assertEquals(1, storage.unreadableFileNames(space).size)
        // Each account has its own space.
        assertNotNull(storage.space("user-3").directory)
        assertTrue(storage.space("user-3").directory != space.directory)
    }

    @Test
    fun transportReachesStagingIdentifyAndGetsTheUnknownUsername404() {
        val backend = BackendConfig.current
        org.junit.Assume.assumeNotNull(backend)
        val transport = HttpTransport(backend!!.url, backend.apiKey)
        val response = transport.request(
            "POST", "/functions/v1/identify",
            listOf(
                uniffi.lime_core.HeaderPair("content-type", "application/json"),
            ),
            """{"identifier":"no_such_user_android_probe"}""".toByteArray(),
        )
        assertEquals(404.toUShort(), response.status)
    }
}
