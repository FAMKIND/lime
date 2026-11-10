package com.limemessenger.lime.chats

import android.content.Context
import android.net.ConnectivityManager
import uniffi.lime_core.AttachmentInfo
import uniffi.lime_core.MediaKind
import uniffi.lime_core.mayAutoDownload
import uniffi.lime_core.storageIsLow

/**
 * May lime fetch this file by itself? The rule is the core's `may_auto_download` (voice always, pictures and the rest by the person's choices, nothing when
 * the phone is almost full); this reads the choices, the network (not metered = Wi-Fi) and the free space.
 */
class MediaPolicy(private val context: Context, private val prefs: MediaPrefs) {
    fun mayAutoDownload(attachment: AttachmentInfo): Boolean {
        val kind = when {
            attachment.mime.startsWith("audio/") -> MediaKind.AUDIO
            attachment.mime.startsWith("image/") -> MediaKind.IMAGE
            attachment.mime.startsWith("video/") -> MediaKind.VIDEO
            else -> MediaKind.FILE
        }
        val connectivity = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
        val onWifi = connectivity?.isActiveNetworkMetered?.not() ?: true
        val low = storageIsLow(context.filesDir.usableSpace.toULong())
        return mayAutoDownload(kind, prefs.photos, prefs.videoAndFiles, onWifi, low)
    }
}
