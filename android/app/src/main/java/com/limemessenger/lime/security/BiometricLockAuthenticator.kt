package com.limemessenger.lime.security

import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import kotlin.coroutines.resume
import kotlinx.coroutines.suspendCancellableCoroutine

/**
 * The system's screen lock through `BiometricPrompt` (AndroidX): a fingerprint or face where the phone has one, the PIN, pattern or password otherwise.
 * False when the phone has no screen lock set up, or the person cancels or fails.
 */
class BiometricLockAuthenticator(private val activity: FragmentActivity) : LockAuthenticator {
    private val allowed = BiometricManager.Authenticators.BIOMETRIC_WEAK or BiometricManager.Authenticators.DEVICE_CREDENTIAL

    /** Whether the phone has a screen lock to ask. */
    fun available(): Boolean = BiometricManager.from(activity).canAuthenticate(allowed) == BiometricManager.BIOMETRIC_SUCCESS

    override suspend fun authenticate(reason: String): Boolean {
        if (!available()) return false
        return suspendCancellableCoroutine { continuation ->
            val prompt = BiometricPrompt(activity, ContextCompat.getMainExecutor(activity), object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) { if (continuation.isActive) continuation.resume(true) }
                override fun onAuthenticationError(errorCode: Int, errString: CharSequence) { if (continuation.isActive) continuation.resume(false) }
            })
            val info = BiometricPrompt.PromptInfo.Builder().setTitle(reason).setAllowedAuthenticators(allowed).build()
            prompt.authenticate(info)
            continuation.invokeOnCancellation { prompt.cancelAuthentication() }
        }
    }
}
