package com.limemessenger.lime

import com.limemessenger.lime.keys.KeyWrapper
import com.limemessenger.lime.keys.SecureBlobStore
import java.nio.file.Files
import javax.crypto.KeyGenerator
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class KeyWrapperTest {
    private fun key() = KeyGenerator.getInstance("AES").apply { init(256) }.generateKey()

    @Test
    fun roundTrips() {
        val wrapper = KeyWrapper(key())
        val secret = KeyWrapper.randomBytes(32)
        assertArrayEquals(secret, wrapper.open(wrapper.seal(secret))!!)
    }

    @Test
    fun sealingTwiceGivesDifferentBlobs() {
        val wrapper = KeyWrapper(key())
        val secret = KeyWrapper.randomBytes(32)
        assertNotEquals(wrapper.seal(secret).toList(), wrapper.seal(secret).toList())
    }

    @Test
    fun anotherKeyOrADamagedBlobOrAnotherPurposeOpensNothing() {
        val wrapper = KeyWrapper(key())
        val blob = wrapper.seal("tokens".toByteArray(), "session".toByteArray())
        assertNull(KeyWrapper(key()).open(blob, "session".toByteArray()))
        assertNull(wrapper.open(blob, "storage".toByteArray()))
        assertNull(wrapper.open(blob.copyOf().also { it[it.size - 1] = (it[it.size - 1] + 1).toByte() }, "session".toByteArray()))
        assertNull(wrapper.open(ByteArray(5)))
        assertArrayEquals("tokens".toByteArray(), wrapper.open(blob, "session".toByteArray()))
    }

    @Test
    fun blobStoreWritesReadsAndDeletes() {
        val dir = Files.createTempDirectory("lime-blobs").toFile()
        val store = SecureBlobStore(dir, KeyWrapper(key()))
        assertNull(store.read("a"))
        store.write("a", byteArrayOf(1, 2, 3))
        store.write("a", byteArrayOf(4, 5))
        assertArrayEquals(byteArrayOf(4, 5), store.read("a"))
        assertTrue(store.exists("a"))
        // The file holds no plain text of the value.
        assertFalse(dir.listFiles()!!.any { it.readBytes().toList().containsAll(listOf<Byte>(4, 5)) && it.length() < 20 })
        store.delete("a")
        assertNull(store.read("a"))
    }

    @Test
    fun aBlobRenamedToAnotherNameDoesNotOpen() {
        val dir = Files.createTempDirectory("lime-blobs").toFile()
        val store = SecureBlobStore(dir, KeyWrapper(key()))
        store.write("session", byteArrayOf(9, 9))
        java.io.File(dir, "session.blob").renameTo(java.io.File(dir, "storage.blob"))
        assertNull(store.read("storage"))
    }
}
