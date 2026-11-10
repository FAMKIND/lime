package com.limemessenger.lime

import android.os.Bundle
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
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        val app = application as LimeApp
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
