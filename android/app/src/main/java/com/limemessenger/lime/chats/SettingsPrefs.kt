package com.limemessenger.lime.chats

import android.content.SharedPreferences
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import uniffi.lime_core.AutoDownload
import uniffi.lime_core.KeepMedia
import uniffi.lime_core.NotificationPreview

/** What a notification or banner shows, and whether they show at all (iOS `NotificationSettings`): kept in the app's private preferences, never sent anywhere. */
class NotificationPrefs(private val prefs: SharedPreferences) {
    var enabled by mutableStateOf(prefs.getBoolean(ENABLED, true))
        private set
    var preview by mutableStateOf(prefs.getString(PREVIEW, null)?.let { runCatching { NotificationPreview.valueOf(it) }.getOrNull() } ?: NotificationPreview.NAME_AND_MESSAGE)
        private set

    fun changeEnabled(value: Boolean) { enabled = value; prefs.edit().putBoolean(ENABLED, value).apply() }
    fun changePreview(value: NotificationPreview) { preview = value; prefs.edit().putString(PREVIEW, value.name).apply() }

    private companion object { const val ENABLED = "notify.enabled"; const val PREVIEW = "notify.preview" }
}

/** The media choices (iOS `MediaSettings`): how long to keep received files, and what to download by itself (photos; videos and files). */
class MediaPrefs(private val prefs: SharedPreferences) {
    var keep by mutableStateOf(read(KEEP, KeepMedia.FOREVER) { KeepMedia.valueOf(it) })
        private set
    var photos by mutableStateOf(read(PHOTOS, AutoDownload.WIFI_AND_MOBILE) { AutoDownload.valueOf(it) })
        private set
    var videoAndFiles by mutableStateOf(read(VIDEO_FILES, AutoDownload.WIFI_ONLY) { AutoDownload.valueOf(it) })
        private set

    fun changeKeep(value: KeepMedia) { keep = value; prefs.edit().putString(KEEP, value.name).apply() }
    fun changePhotos(value: AutoDownload) { photos = value; prefs.edit().putString(PHOTOS, value.name).apply() }
    fun changeVideoAndFiles(value: AutoDownload) { videoAndFiles = value; prefs.edit().putString(VIDEO_FILES, value.name).apply() }

    private fun <T> read(key: String, default: T, parse: (String) -> T): T = prefs.getString(key, null)?.let { runCatching { parse(it) }.getOrNull() } ?: default

    private companion object { const val KEEP = "media.keep"; const val PHOTOS = "media.photos"; const val VIDEO_FILES = "media.videoFiles" }
}
