package com.limemessenger.lime

import android.app.Application
import com.limemessenger.lime.auth.AccountSession
import com.limemessenger.lime.auth.LiveAuthService
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

    /** This phone's own choices (not secret, never sent anywhere): the lock, notifications, media. */
    val appLock: com.limemessenger.lime.security.AppLock by lazy { com.limemessenger.lime.security.AppLock(getSharedPreferences("lime.lock", MODE_PRIVATE)) }
    val notificationPrefs: com.limemessenger.lime.chats.NotificationPrefs by lazy { com.limemessenger.lime.chats.NotificationPrefs(getSharedPreferences("lime.notify", MODE_PRIVATE)) }
    val mediaPrefs: com.limemessenger.lime.chats.MediaPrefs by lazy { com.limemessenger.lime.chats.MediaPrefs(getSharedPreferences("lime.media", MODE_PRIVATE)) }

    val backend: BackendConfig? get() = BackendConfig.current
    val transport: HttpTransport? by lazy { backend?.let { HttpTransport(it.url, it.apiKey) } }

    /** One session for the whole process; the screens read it. Tests can replace it before the activity starts. */
    var session: AccountSession by mutableLazy {
        AccountSession(
            auth = backend?.let { LiveAuthService(HttpTransport(it.url, it.apiKey, connectTimeoutMs = 30_000, readTimeoutMs = 30_000)) },
            backend = backend, storage = storage, secrets = secrets,
        )
    }
}

/** A lazily made property that can also be assigned (tests swap the session for one with a fake auth service). */
private fun <T> mutableLazy(init: () -> T) = object : kotlin.properties.ReadWriteProperty<Any?, T> {
    private var value: T? = null
    @Suppress("UNCHECKED_CAST")
    override fun getValue(thisRef: Any?, property: kotlin.reflect.KProperty<*>): T = value ?: init().also { value = it }
    override fun setValue(thisRef: Any?, property: kotlin.reflect.KProperty<*>, value: T) { this.value = value }
}
