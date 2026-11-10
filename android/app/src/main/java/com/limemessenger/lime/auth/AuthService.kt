package com.limemessenger.lime.auth

// ANDROID DEBT: twin of ios/Lime/Core/Auth/AuthService.swift; moves into LimeCore in LIME-133

/**
 * Signing up and in. The server is the authority (a password and an emailed code are both checked by its functions); this is the app's
 * side of it. [LiveAuthService] talks to the backend; a fake stands in for tests. Only what the sign-in screens need is here
 * (password change and account deletion come with Settings).
 */
interface AuthService {
    suspend fun identify(identifier: String): IdentifyResult

    // Sign in: a password, then an emailed code.
    suspend fun signIn(identifier: String, password: String): PasswordSignIn
    suspend fun verifySignInCode(code: String, tokens: AuthTokens)
    suspend fun resendSignInCode(tokens: AuthTokens)

    // Sign up: an emailed code, then a password, then a profile.
    suspend fun startSignUp(email: String)
    suspend fun verifySignUpCode(email: String, code: String): AuthTokens

    /** Sets the password; returns a fresh session that has passed both steps (the old one ends). */
    suspend fun setInitialPassword(password: String, tokens: AuthTokens): AuthTokens

    // Forgot password: an emailed code and a new password.
    suspend fun startReset(identifier: String)
    suspend fun finishReset(identifier: String, code: String, newPassword: String): AuthTokens

    /** Changing the password from Settings: the current one is checked and a code is emailed; then the code and the new password give a fresh session. */
    suspend fun startPasswordChange(current: String, tokens: AuthTokens)
    suspend fun finishPasswordChange(code: String, newPassword: String, tokens: AuthTokens): AuthTokens

    suspend fun saveProfile(draft: ProfileDraft, tokens: AuthTokens): Profile
    suspend fun loadProfile(tokens: AuthTokens): Profile?

    suspend fun refresh(tokens: AuthTokens): AuthTokens
    suspend fun signOut(tokens: AuthTokens)
}
