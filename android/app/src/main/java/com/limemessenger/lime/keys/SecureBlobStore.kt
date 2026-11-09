package com.limemessenger.lime.keys

import java.io.File

/**
 * Small secrets in files, each sealed by a [KeyWrapper]. This is the Android counterpart of the iOS Keychain items
 * (`StorageKeychain`, `SessionKeychain`): this device only, never backed up (the folder is `noBackupFilesDir`, and the manifest
 * excludes everything from backup anyway). A blob is bound to its name, so one cannot be renamed into another.
 */
class SecureBlobStore(private val directory: File, private val wrapper: KeyWrapper) {
    fun read(name: String): ByteArray? {
        val file = File(directory, fileName(name))
        if (!file.isFile) return null
        return wrapper.open(file.readBytes(), name.toByteArray())
    }

    fun write(name: String, value: ByteArray) {
        directory.mkdirs()
        val target = File(directory, fileName(name))
        val temporary = File(directory, fileName(name) + ".tmp")
        temporary.writeBytes(wrapper.seal(value, name.toByteArray()))
        if (!temporary.renameTo(target)) {
            target.delete()
            check(temporary.renameTo(target)) { "could not store $name" }
        }
    }

    fun delete(name: String) {
        File(directory, fileName(name)).delete()
    }

    fun exists(name: String): Boolean = File(directory, fileName(name)).isFile

    private fun fileName(name: String) = "$name.blob"
}
