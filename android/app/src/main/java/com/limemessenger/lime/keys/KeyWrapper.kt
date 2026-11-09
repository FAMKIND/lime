package com.limemessenger.lime.keys

import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * AES-256-GCM sealing of small secrets (the database key, the session tokens). The wrapping key is a `SecretKey`: on a device it is the
 * Android Keystore's (never leaves secure hardware where there is any, this device only); in unit tests it is a plain AES key.
 * Output = 12-byte IV followed by ciphertext+tag. `aad` binds a blob to its purpose so one cannot be swapped for another.
 */
class KeyWrapper(private val key: SecretKey) {
    fun seal(plain: ByteArray, aad: ByteArray = ByteArray(0)): ByteArray {
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, key)
        if (aad.isNotEmpty()) cipher.updateAAD(aad)
        val sealed = cipher.doFinal(plain)
        return cipher.iv + sealed
    }

    /** null when the blob is damaged, was sealed with another key, or for another purpose. */
    fun open(blob: ByteArray, aad: ByteArray = ByteArray(0)): ByteArray? {
        if (blob.size <= IV_BYTES) return null
        return try {
            val cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(TAG_BITS, blob, 0, IV_BYTES))
            if (aad.isNotEmpty()) cipher.updateAAD(aad)
            cipher.doFinal(blob, IV_BYTES, blob.size - IV_BYTES)
        } catch (e: Exception) {
            null
        }
    }

    companion object {
        private const val TRANSFORMATION = "AES/GCM/NoPadding"
        private const val IV_BYTES = 12
        private const val TAG_BITS = 128

        fun randomBytes(count: Int): ByteArray = ByteArray(count).also { SecureRandom().nextBytes(it) }
    }
}
