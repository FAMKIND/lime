package com.limemessenger.lime.calls

import io.livekit.android.e2ee.BaseKeyProvider
import io.livekit.android.e2ee.E2EEOptions
import livekit.LivekitModels
import livekit.org.webrtc.FrameCryptorKeyDerivationAlgorithm

/**
 * The key side of a group call's frame encryption: the Android twin of iOS `LiveKitGroupMedia` (`GroupCallMedia.swift`: `BaseKeyProvider(isSharedKey: false)`, `.gcm`, every key in slot 0).
 * Every participant has their own sender key from the core (`deliver_group_call_ops` / the key events); the SFU forwards AES-GCM ciphertext only and never holds a key.
 *
 * The settings below are iOS's, from LiveKit Swift SDK 2.17.0 (`KeyProviderOptions` defaults, `BaseKeyProvider(isSharedKey: false)`) so that the two apps' frame cryptors interoperate:
 * per-participant keys (not shared), PBKDF2 key derivation, ratchet salt "LKFrameEncryptionKey", unencrypted magic bytes "LK-ROCKS", **no automatic ratcheting** (window 0), failure
 * tolerance -1, key ring 16, frames are not discarded while a cryptor is not ready. The Android SDK's own defaults differ (a shared key, a ratchet window of 16), which is why this
 * is spelled out rather than taken from `BaseKeyProvider()`. Keys are raw bytes: they go in through the SDK's `rtcKeyProvider` (`BaseKeyProvider.setKey` takes a String and would
 * turn the bytes into text).
 */
class GroupCallKeys {
    val provider: BaseKeyProvider = BaseKeyProvider(
        "LKFrameEncryptionKey", "LK-ROCKS", 0, /* sharedKey = */ false, -1, 16, /* discardFrameWhenCryptorNotReady = */ false, FrameCryptorKeyDerivationAlgorithm.PBKDF2,
    )

    /** The options a LiveKit `Room` takes (GCM, as iOS). */
    fun options(): E2EEOptions = E2EEOptions(provider, LivekitModels.Encryption.Type.GCM)

    /** Installs a participant's key (mine or theirs). Every key goes to slot 0, whatever index the core gave it: iOS does the same (LIME-163), and a mixed index would leave the two apps reading different slots. */
    fun setKey(key: ByteArray, participant: String): Boolean = provider.rtcKeyProvider.setKey(participant, SLOT, key)

    companion object { const val SLOT = 0 }
}
