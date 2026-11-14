package com.limemessenger.lime.calls

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import com.limemessenger.lime.LimeApp
import com.limemessenger.lime.MainActivity
import com.limemessenger.lime.R

/**
 * The foreground service of a call (LIME-425): while a call is going the process must survive the screen turning off and lime leaving the front, and Android requires the
 * person to see that the microphone is in use: an ongoing notification with the person's name and a Hang up action. Type `microphone` (see docs/android-calls.md §2: the
 * `phoneCall` type needs Telecom, which the system surface brief (LIME-427) decides). Started when a call is placed or answered, stopped when it ends, so nothing is left
 * behind: no stuck notification after any ending (hang up, decline, busy, timeout, media failure, process death).
 */
class CallService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_HANG_UP -> { (application as? LimeApp)?.callHangUp?.invoke(); stopSelfClean(); return START_NOT_STICKY }
            ACTION_STOP -> { stopSelfClean(); return START_NOT_STICKY }
        }
        val name = intent?.getStringExtra(EXTRA_NAME).orEmpty()
        val notification = notification(this, name)
        if (Build.VERSION.SDK_INT >= 29) startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
        else startForeground(NOTIFICATION_ID, notification)
        return START_NOT_STICKY
    }

    private fun stopSelfClean() {
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    companion object {
        const val CHANNEL = "lime.calls"
        const val NOTIFICATION_ID = 4204
        const val ACTION_STOP = "com.limemessenger.lime.call.STOP"
        const val ACTION_HANG_UP = "com.limemessenger.lime.call.HANG_UP"
        const val EXTRA_NAME = "name"

        fun start(context: Context, name: String) {
            val intent = Intent(context, CallService::class.java).putExtra(EXTRA_NAME, name)
            runCatching { context.startForegroundService(intent) }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, CallService::class.java))
            (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).cancel(NOTIFICATION_ID)
        }

        private fun notification(context: Context, name: String): Notification {
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(NotificationChannel(CHANNEL, context.getString(R.string.calls_channel), NotificationManager.IMPORTANCE_LOW).apply { setSound(null, null) })
            val open = PendingIntent.getActivity(context, 0, Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP), PendingIntent.FLAG_IMMUTABLE)
            val hangUp = PendingIntent.getService(context, 1, Intent(context, CallService::class.java).setAction(ACTION_HANG_UP), PendingIntent.FLAG_IMMUTABLE)
            return Notification.Builder(context, CHANNEL)
                .setSmallIcon(R.mipmap.ic_launcher).setContentTitle(context.getString(R.string.calls_ongoing, name)).setContentText(context.getString(R.string.calls_ongoing_note))
                .setOngoing(true).setCategory(Notification.CATEGORY_CALL).setContentIntent(open)
                .addAction(Notification.Action.Builder(null, context.getString(R.string.calls_hang_up), hangUp).build()).build()
        }
    }
}
