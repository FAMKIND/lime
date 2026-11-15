package com.limemessenger.lime.calls

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Typeface
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.ContextCompat
import com.limemessenger.lime.LimeApp
import com.limemessenger.lime.MainActivity
import com.limemessenger.lime.R

/**
 * The incoming call on the phone's own surfaces (LIME-427): while lime is NOT in front, a high-importance notification with the caller's name and picture, **Answer** and **Decline**,
 * that is a heads-up on an unlocked phone and takes the whole screen (a full-screen intent) on a locked one, ringing with the phone's ringtone and vibrating on its own channel,
 * whose sound and vibration the person adjusts in the phone's settings. While lime is in front the call screen is the ring and no notification is posted. lime has no push service,
 * so this exists only while the app's process is alive and has heard the call (docs/android-calls.md; DESIGN-37): no Firebase, nothing new on any server.
 */
object IncomingCallNotifier {
    const val CHANNEL = "lime.calls.incoming"
    const val NOTIFICATION_ID = 4205
    const val ACTION_DECLINE = "com.limemessenger.lime.call.DECLINE"
    const val ACTION_ANSWER = "com.limemessenger.lime.call.ANSWER"
    const val ACTION_HANG_UP = "com.limemessenger.lime.call.PIP_HANG_UP"
    /** The ring stops by itself (the machine's own 45 s ring timer ends the call; the notification goes with it). */
    private const val TIMEOUT_MS = 50_000L

    /** What the ring surface can do right now (Settings → Calls says it in words). */
    data class Surface(val notificationsAllowed: Boolean, val channelAllowed: Boolean, val fullScreenAllowed: Boolean) {
        val ringsInBackground: Boolean get() = notificationsAllowed && channelAllowed
    }

    fun surface(context: Context): Surface {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val runtime = Build.VERSION.SDK_INT < 33 || ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        val enabled = runtime && manager.areNotificationsEnabled()
        val channel = if (Build.VERSION.SDK_INT >= 26) manager.getNotificationChannel(CHANNEL) else null
        val channelOn = channel == null || channel.importance != NotificationManager.IMPORTANCE_NONE
        val fullScreen = Build.VERSION.SDK_INT < 34 || manager.canUseFullScreenIntent()
        return Surface(enabled, channelOn, fullScreen)
    }

    fun createChannel(context: Context) {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val ring: Uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
        val channel = NotificationChannel(CHANNEL, context.getString(R.string.calls_incoming_channel), NotificationManager.IMPORTANCE_HIGH).apply {
            description = context.getString(R.string.calls_incoming_channel_note)
            setSound(ring, AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE).setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build())
            enableVibration(true); vibrationPattern = longArrayOf(0, 700, 500, 700, 500)
            lockscreenVisibility = Notification.VISIBILITY_PRIVATE
            setShowBadge(false)
        }
        manager.createNotificationChannel(channel)
    }

    /** The notification: built apart from posting so a test can read what it says and does. */
    fun build(context: Context, callId: String, name: String, video: Boolean): Notification {
        createChannel(context)
        val flags = PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        val open = Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP).putExtra(EXTRA_CALL, callId)
        val content = PendingIntent.getActivity(context, 10, open, flags)
        val answer = PendingIntent.getActivity(context, 11, Intent(open).setAction(ACTION_ANSWER), flags)
        val decline = PendingIntent.getBroadcast(context, 12, Intent(context, CallActionReceiver::class.java).setAction(ACTION_DECLINE).putExtra(EXTRA_CALL, callId), flags)
        val title = context.getString(if (video) R.string.calls_incoming_video else R.string.calls_incoming_voice)
        val builder = Notification.Builder(context, CHANNEL)
            .setSmallIcon(R.mipmap.ic_launcher).setLargeIcon(avatar(context, name))
            .setContentTitle(name).setContentText(title)
            .setCategory(Notification.CATEGORY_CALL).setOngoing(true).setAutoCancel(false).setOnlyAlertOnce(true)
            .setVisibility(Notification.VISIBILITY_PRIVATE).setTimeoutAfter(TIMEOUT_MS)
            .setContentIntent(content).setFullScreenIntent(content, true)
        if (Build.VERSION.SDK_INT >= 31) {
            // Android 12+: the system's call style (green Answer, red Decline) with the caller's name.
            builder.setStyle(Notification.CallStyle.forIncomingCall(android.app.Person.Builder().setName(name).build(), decline, answer))
        } else {
            // Before that, two plain buttons with the same words.
            builder.addAction(Notification.Action.Builder(null, context.getString(R.string.calls_decline), decline).build())
            builder.addAction(Notification.Action.Builder(null, context.getString(R.string.calls_answer), answer).build())
        }
        val built = builder.build()
        built.flags = built.flags or Notification.FLAG_INSISTENT   // the ringtone repeats until the notification goes
        return built
    }

    fun post(context: Context, callId: String, name: String, video: Boolean) {
        val s = surface(context)
        if (!s.ringsInBackground) return
        runCatching { (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).notify(NOTIFICATION_ID, build(context, callId, name, video)) }
    }

    /** A group call has started (a banner while lime is in the background; tapping it opens lime, where the chat says "Join the call"). Never a full-screen intent: a group call does not take the screen. */
    fun postGroup(context: Context, title: String) {
        if (!surface(context).ringsInBackground) return
        createChannel(context)
        val open = PendingIntent.getActivity(context, 14, Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP), PendingIntent.FLAG_IMMUTABLE)
        val n = Notification.Builder(context, CHANNEL).setSmallIcon(R.mipmap.ic_launcher).setContentTitle(title).setCategory(Notification.CATEGORY_CALL)
            .setAutoCancel(true).setContentIntent(open).setTimeoutAfter(60_000L).build()
        runCatching { (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).notify(NOTIFICATION_ID + 1, n) }
    }

    fun cancel(context: Context) {
        (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).cancel(NOTIFICATION_ID)
    }

    /** The phone's settings page for this ring: the channel (sound, vibration, importance) when notifications are on, the app's notification settings when they are off. */
    fun settingsIntent(context: Context): Intent {
        val s = surface(context)
        val base = if (s.notificationsAllowed) Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_CHANNEL_ID, CHANNEL)
        else Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
        return base.putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }

    /** Android 14+: the page where "full-screen notifications" are allowed (the lock-screen call screen). */
    fun fullScreenSettingsIntent(context: Context): Intent? =
        if (Build.VERSION.SDK_INT >= 34) Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT, Uri.parse("package:${context.packageName}")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) else null

    /** The caller's picture: their initials on a lime tint (a picture is never fetched for the notification). */
    private fun avatar(context: Context, name: String): Bitmap {
        val size = 128
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        canvas.drawCircle(size / 2f, size / 2f, size / 2f, Paint(Paint.ANTI_ALIAS_FLAG).apply { color = 0xFFA3E18A.toInt() })
        val initials = name.trim().split(" ").filter { it.isNotEmpty() }.take(2).joinToString("") { it.first().uppercase() }.ifEmpty { "?" }
        val text = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = 0xFF131B17.toInt(); textSize = size * 0.4f; textAlign = Paint.Align.CENTER; typeface = Typeface.DEFAULT_BOLD }
        canvas.drawText(initials, size / 2f, size / 2f - (text.descent() + text.ascent()) / 2f, text)
        return bitmap
    }

    const val EXTRA_CALL = "call_id"
}

/** The Decline button of the incoming-call notification: no screen, straight to the session (the Answer button opens lime, which asks for the microphone first). */
class CallActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val app = context.applicationContext as? LimeApp
        // The hang-up button of the Picture in Picture window.
        if (intent.action == IncomingCallNotifier.ACTION_HANG_UP) { app?.callSession?.hangUp(); return }
        if (intent.action != IncomingCallNotifier.ACTION_DECLINE) return
        val session = app?.callSession
        // Only the call the notification was for (a stale button of an earlier call does nothing).
        if (session != null && session.driver.state.callId == intent.getStringExtra(IncomingCallNotifier.EXTRA_CALL)) session.decline()
        IncomingCallNotifier.cancel(context)
    }
}
