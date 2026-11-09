package com.limemessenger.lime.auth

/** A scripted [AuthService] for tests (as iOS's `FakeAuthService`): the right password is `correct horse`, the right code is `123456`. Records calls. */
class FakeAuthService : AuthService {
    val calls = mutableListOf<String>()
    var identifyResult: IdentifyResult = IdentifyResult.ExistingEmail
    var failNext: AuthError? = null
    var profile: Profile? = Profile("Ada Fake", "ada_fake")
    var correctCode = "123456"
    var lastDraft: ProfileDraft? = null
    var correctPassword = "correct horse"

    private fun tokens(tag: String = "t") = AuthTokens("access-$tag", "refresh-$tag", System.currentTimeMillis() + 3_600_000, "user-1")
    private fun maybeFail() { failNext?.let { failNext = null; throw it } }

    override suspend fun identify(identifier: String): IdentifyResult { calls += "identify:$identifier"; maybeFail(); return identifyResult }

    override suspend fun signIn(identifier: String, password: String): PasswordSignIn {
        calls += "signIn:$identifier"; maybeFail()
        if (password != correctPassword) throw AuthError.InvalidCredentials
        return PasswordSignIn(tokens("signin"), "a•••@example.invalid")
    }

    override suspend fun verifySignInCode(code: String, tokens: AuthTokens) {
        calls += "verifySignInCode:$code"; maybeFail()
        if (code != correctCode) throw AuthError.BadCode("That code isn't right.")
    }

    override suspend fun resendSignInCode(tokens: AuthTokens) { calls += "resendSignInCode"; maybeFail() }
    override suspend fun startSignUp(email: String) { calls += "startSignUp:$email"; maybeFail() }

    override suspend fun verifySignUpCode(email: String, code: String): AuthTokens {
        calls += "verifySignUpCode:$code"; maybeFail()
        if (code != correctCode) throw AuthError.BadCode("That code isn't right.")
        return tokens("signup")
    }

    override suspend fun setInitialPassword(password: String, tokens: AuthTokens): AuthTokens { calls += "setInitialPassword"; maybeFail(); return tokens("pw") }
    override suspend fun startReset(identifier: String) { calls += "startReset:$identifier"; maybeFail() }

    override suspend fun finishReset(identifier: String, code: String, newPassword: String): AuthTokens {
        calls += "finishReset:$code"; maybeFail()
        if (code != correctCode) throw AuthError.BadCode("That code isn't right.")
        return tokens("reset")
    }

    override suspend fun saveProfile(draft: ProfileDraft, tokens: AuthTokens): Profile {
        calls += "saveProfile:${draft.displayName}:${draft.username}:${draft.school}"; lastDraft = draft; maybeFail()
        return Profile(draft.displayName, draft.username, draft.school, draft.aboutEmoji, draft.aboutText, draft.hideFromSearch ?: false).also { profile = it }
    }

    override suspend fun loadProfile(tokens: AuthTokens): Profile? { calls += "loadProfile"; return profile }
    override suspend fun refresh(tokens: AuthTokens): AuthTokens { calls += "refresh"; return tokens("refreshed") }
    override suspend fun signOut(tokens: AuthTokens) { calls += "signOut" }
}
