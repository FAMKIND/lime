package com.limemessenger.lime

import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
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
    val themePrefs: com.limemessenger.lime.chats.ThemePrefs by lazy { com.limemessenger.lime.chats.ThemePrefs(getSharedPreferences("lime.theme", MODE_PRIVATE)) }
    /** Hangs up the call that is going (the call notification's Hang up button); set by the signed-in screen. */
    var callHangUp: (() -> Unit)? = null
    /** lime is in front (the call screen is the ring) or not (the incoming-call notification is); set by the signed-in screen's lifecycle observer. */
    @Volatile var inForeground: Boolean = true
    /** The call id an Answer tap on the incoming-call notification asked for; the signed-in screen answers it (after the microphone permission) and clears it. */
    var answerRequest: String? by androidx.compose.runtime.mutableStateOf<String?>(null)
    /** The activity is in Picture in Picture (a video call floating over other apps). */
    var inPip: Boolean by androidx.compose.runtime.mutableStateOf(false)
    /** The signed-in call session (a seam for the two-emulator media proof; nothing else reads it). */
    var callSession: com.limemessenger.lime.calls.CallSession? = null
    /** The signed-in group call session (a seam for the staging group-call proof). */
    var groupCallSession: com.limemessenger.lime.calls.GroupCallSession? = null
    val callPrefs: com.limemessenger.lime.calls.CallPrefs by lazy { com.limemessenger.lime.calls.CallPrefs(getSharedPreferences("lime.calls", MODE_PRIVATE)) }
    val mediaPrefs: com.limemessenger.lime.chats.MediaPrefs by lazy { com.limemessenger.lime.chats.MediaPrefs(getSharedPreferences("lime.media", MODE_PRIVATE)) }

    val linkPreviewPrefs: com.limemessenger.lime.chats.LinkPreviewPrefs by lazy { com.limemessenger.lime.chats.LinkPreviewPrefs(getSharedPreferences("lime.linkpreviews", MODE_PRIVATE)) }

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
