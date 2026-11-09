package com.limemessenger.lime

import android.app.Application
import com.limemessenger.lime.keys.KeyWrapper
import com.limemessenger.lime.keys.KeystoreKey
import com.limemessenger.lime.keys.SecureBlobStore
import com.limemessenger.lime.net.BackendConfig
import com.limemessenger.lime.net.HttpTransport
import com.limemessenger.lime.storage.StorageBootstrap
import java.io.File

/** The app's long-lived pieces, made lazily (the Keystore is only touched when something needs a key). */
class LimeApp : Application() {
    val wrapper: KeyWrapper by lazy { KeyWrapper(KeystoreKey.getOrCreate()) }

    /** Secrets live under `noBackupFilesDir` (never backed up); the core's databases under `noBackupFilesDir/data`. */
    val secrets: SecureBlobStore by lazy { SecureBlobStore(File(noBackupFilesDir, "secrets"), wrapper) }
    val storage: StorageBootstrap by lazy { StorageBootstrap(File(noBackupFilesDir, "data"), secrets) }

    val backend: BackendConfig? get() = BackendConfig.current
    val transport: HttpTransport? by lazy { backend?.let { HttpTransport(it.url, it.apiKey) } }
}
