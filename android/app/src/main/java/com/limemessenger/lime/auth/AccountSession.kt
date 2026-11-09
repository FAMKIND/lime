package com.limemessenger.lime.auth

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.limemessenger.lime.keys.SecureBlobStore
import com.limemessenger.lime.net.BackendConfig
import com.limemessenger.lime.net.HttpTransport
import com.limemessenger.lime.storage.StorageBootstrap
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import uniffi.lime_core.DeviceInfo
import uniffi.lime_core.LimeStore

// ANDROID DEBT: twin of ios/Lime/Core/Auth/AccountSession.swift (phases, resume, finishSignIn); moves into LimeCore in LIME-133

/**
 * Who is signed in on this phone. Tokens live in the sealed secret store (this device only). After both steps of signing in, LimeCore
 * registers the device with the backend. Signing out ends the session on the server and keeps the chats and keys, locked (LIME-268).
 *
 * Left out for now (recorded in TEND-ANDROID.md): the move-to-a-new-phone offer (LIME-272b), app lock, realtime nudges.
 */
class AccountSession(
    val auth: AuthService?,
    private val backend: BackendConfig?,
    private val storage: StorageBootstrap,
    private val secrets: SecureBlobStore,
    private val transportFactory: (BackendConfig) -> HttpTransport = { HttpTransport(it.url, it.apiKey) },
    private val nowMs: () -> Long = { System.currentTimeMillis() },
    /** Work that must outlive the screen that started it (the sign-in screens leave the composition the moment the phase changes). */
    private val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate),
) {
    enum class Phase { Launching, SignedOut, SignedIn }

    var phase by mutableStateOf(Phase.Launching)
        private set
    var profile by mutableStateOf<Profile?>(null)
        private set
    var deviceRegistered by mutableStateOf(false)
        private set
    var userId by mutableStateOf<String?>(null)
        private set
    var problem by mutableStateOf<ConnectionProblem?>(null)
        private set

    /** Bumped on sign-out so the onboarding screens start fresh. */
    var onboardingGeneration by mutableStateOf(0)
        private set

    /** The open store of the signed-in account (null while signed out). The chat list and chats read it. */
    var store: LimeStore? = null
        private set
    var transport: HttpTransport? = null
        private set

    private var tokens: AuthTokens? = null
    private val refreshLock = Mutex()
    private val registering = Mutex()

    val hasBackend: Boolean get() = auth != null

    // Launch

    /** At launch: pick up a saved session, or ask the person to sign in. */
    suspend fun resume() {
        val service = auth
        var saved = secrets.read(TOKENS)?.decodeToString()?.let { AuthTokens.fromJson(it) }
        if (service == null || saved == null) {
            phase = Phase.SignedOut
            return
        }
        try {
            if (saved.isExpiring(nowMs())) {
                saved = service.refresh(saved)
                saveTokens(saved)
            }
        } catch (e: AuthError.Network) {
            // Offline: carry on with what we have; the next call refreshes.
        } catch (e: AuthError.Unavailable) {
            // The server is down: the same.
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            // The session ended on the server (signed out elsewhere, or revoked).
            secrets.delete(TOKENS)
            phase = Phase.SignedOut
            return
        }
        tokens = saved
        userId = saved.userId
        profile = secrets.read(PROFILE)?.decodeToString()?.let { Profile.fromJson(it) }
        openSpace(saved.userId)
        phase = Phase.SignedIn
        scope.launch { registerDevice() }.join()
        runCatching { service.loadProfile(saved) }.getOrNull()?.let { updateProfile(it) }
    }

    // Signing in

    /** Both steps passed (and the profile exists): keep the session and register this device. */
    suspend fun completeSignIn(tokens: AuthTokens, profile: Profile?) {
        // Each account has its own space (LIME-268): the same person coming back opens their locked store and keeps their keys; another
        // account opens its own and leaves this one intact.
        openSpace(tokens.userId)
        this.tokens = tokens
        userId = tokens.userId
        saveTokens(tokens)
        if (profile != null) updateProfile(profile)
        phase = Phase.SignedIn
        scope.launch { registerDevice() }
    }

    private suspend fun openSpace(forUser: String) = withContext(Dispatchers.IO) {
        store?.close()
        val opened = storage.open(storage.space(forUser))
        store = opened.store
        backend?.let { transport = transportFactory(it) }
    }

    /** The core registers this device once both factors have passed. Idempotent. */
    suspend fun registerDevice(): DeviceInfo? = registering.withLock {
        val core = store
        val link = transport
        if (core == null || link == null || tokens == null || deviceRegistered) return null
        try {
            val token = accessToken()
            val info = withContext(Dispatchers.IO) { core.registerDevice(link, token) }
            deviceRegistered = true
            userId = info.userId
            problem = null
            return info
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            deviceRegistered = false
            problem = ConnectionProblem.from(e)
            return null
        }
    }

    /** A valid access token, refreshed first when it is about to expire. Calls that arrive together share one refresh (a refresh token is single-use). */
    suspend fun accessToken(): String {
        val service = auth ?: throw AuthError.NotVerified
        return refreshLock.withLock {
            val current = tokens ?: throw AuthError.NotVerified
            if (!current.isExpiring(nowMs())) return current.accessToken
            val fresh = service.refresh(current)
            tokens = fresh
            saveTokens(fresh)
            fresh.accessToken
        }
    }

    /** The access token this phone holds, expired or not (sending with no internet). */
    fun lastAccessToken(): String = tokens?.accessToken.orEmpty()

    // Signing out

    /**
     * Ends the session on the server and returns to sign-in. The chats, files and keys stay on this device, encrypted and locked (LIME-268);
     * `removingData` is "Remove everything from this device": this account's store and keys are deleted too.
     */
    suspend fun signOut(removingData: Boolean = false) {
        val service = auth
        val current = tokens
        if (service != null && current != null) service.signOut(current)
        secrets.delete(TOKENS)
        secrets.delete(PROFILE)
        val owner = userId
        withContext(Dispatchers.IO) {
            store?.close()
            if (removingData && owner != null) storage.wipe(storage.space(owner))
        }
        store = null
        transport = null
        tokens = null
        profile = null
        deviceRegistered = false
        userId = null
        problem = null
        onboardingGeneration++
        phase = Phase.SignedOut
    }

    // Profile

    /** Saves the whole profile (an editor changes one field and sends all of them). Throws the server's reason, e.g. `AuthError.UsernameTaken`. */
    suspend fun updateProfile(draft: ProfileDraft) {
        val service = auth ?: throw AuthError.Network
        val current = tokens ?: throw AuthError.NotVerified
        accessToken()
        val saved = service.saveProfile(draft, tokens ?: current)
        updateProfile(saved.copy(maskedEmail = saved.maskedEmail ?: profile?.maskedEmail))
    }

    private fun updateProfile(value: Profile) {
        profile = value
        secrets.write(PROFILE, value.toJson().toByteArray())
    }

    private fun saveTokens(value: AuthTokens) = secrets.write(TOKENS, value.toJson().toByteArray())

    companion object {
        const val TOKENS = "session-tokens"
        const val PROFILE = "profile"
    }
}
