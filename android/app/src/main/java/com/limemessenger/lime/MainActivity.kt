package com.limemessenger.lime

import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.app.RemoteAction
import android.content.Intent
import android.content.res.Configuration
import android.graphics.drawable.Icon
import android.os.Bundle
import android.util.Rational
import com.limemessenger.lime.calls.CallActionReceiver
import com.limemessenger.lime.calls.IncomingCallNotifier
import uniffi.lime_core.CallPhaseKind
import android.view.WindowManager
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.foundation.layout.Box
import androidx.fragment.app.FragmentActivity
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import com.limemessenger.lime.security.BiometricLockAuthenticator
import com.limemessenger.lime.ui.Root
import com.limemessenger.lime.ui.LockOverlay
import com.limemessenger.lime.ui.theme.LimeTheme

/** A `FragmentActivity` (it is a `ComponentActivity` too) because the system's screen-lock prompt (`BiometricPrompt`) needs one. */
class MainActivity : FragmentActivity() {
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (intent.hasExtra(IncomingCallNotifier.EXTRA_CALL)) { setShowWhenLocked(true); setTurnScreenOn(true); handleCallIntent(intent) }
    }

    /** The Answer button of the notification: asks the signed-in screen to answer (it asks for the microphone first). */
    private fun handleCallIntent(intent: Intent) {
        if (intent.action == IncomingCallNotifier.ACTION_ANSWER) (application as LimeApp).answerRequest = intent.getStringExtra(IncomingCallNotifier.EXTRA_CALL)
    }

    /** A video call floats over other apps when lime goes to the background (or its Minimise button is used). */
    fun enterCallPip(): Boolean {
        val session = (application as LimeApp).callSession ?: return false
        if (!session.inCall || !session.video || session.phase != CallPhaseKind.ACTIVE) return false
        val hang = PendingIntent.getBroadcast(this, 13, Intent(this, CallActionReceiver::class.java).setAction(IncomingCallNotifier.ACTION_HANG_UP), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val action = RemoteAction(Icon.createWithResource(this, android.R.drawable.ic_menu_close_clear_cancel), getString(R.string.calls_pip_hang_up), getString(R.string.calls_pip_hang_up), hang)
        return runCatching { enterPictureInPictureMode(PictureInPictureParams.Builder().setAspectRatio(Rational(9, 16)).setActions(listOf(action)).build()) }.getOrDefault(false)
    }

    override fun onUserLeaveHint() { super.onUserLeaveHint(); enterCallPip() }

    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean, newConfig: Configuration) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        (application as LimeApp).inPip = isInPictureInPictureMode
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        val app = application as LimeApp
        // Opened by the incoming-call notification (the full-screen intent on a locked phone, or its Answer button): the call shows over the lock screen for the call only.
        if (intent?.hasExtra(IncomingCallNotifier.EXTRA_CALL) == true) { setShowWhenLocked(true); setTurnScreenOn(true); handleCallIntent(intent) }
        val session = app.session
        val lock = app.appLock
        lock.authenticator = BiometricLockAuthenticator(this)
        // The lock follows the activity: covered as soon as something is over it, locked when it leaves (at once or after the delay).
        lifecycle.addObserver(object : DefaultLifecycleObserver {
            override fun onPause(owner: LifecycleOwner) = lock.sceneBecameInactive()
            override fun onStop(owner: LifecycleOwner) = lock.sceneEnteredBackground()
            override fun onStart(owner: LifecycleOwner) = lock.sceneBecameActive()
            override fun onResume(owner: LifecycleOwner) = lock.sceneBecameActive()
        })
        setContent {
            LimeTheme {
                // While the lock is on the window is secure: the recent-apps picture and screenshots never show chats.
                LaunchedEffect(lock.isEnabled) {
                    if (lock.isEnabled) window.setFlags(WindowManager.LayoutParams.FLAG_SECURE, WindowManager.LayoutParams.FLAG_SECURE)
                    else window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                }
                Box {
                    Root(session)
                    LockOverlay(lock, signedIn = session.phase == com.limemessenger.lime.auth.AccountSession.Phase.SignedIn)
                }
            }
        }
    }
}
