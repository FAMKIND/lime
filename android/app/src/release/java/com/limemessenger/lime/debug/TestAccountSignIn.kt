package com.limemessenger.lime.debug

import androidx.compose.runtime.Composable
import com.limemessenger.lime.auth.AuthTokens
import com.limemessenger.lime.auth.Profile

/** Release builds have no test sign-in: this twin of the debug source set does nothing. */
@Composable
@Suppress("UNUSED_PARAMETER")
fun TestAccountSignIn(onPick: suspend (AuthTokens, Profile?) -> Unit) {
}
