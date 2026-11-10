package com.limemessenger.lime.auth

import com.limemessenger.lime.net.HttpTransport
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import uniffi.lime_core.HeaderPair
import uniffi.lime_core.TransportException

// ANDROID DEBT: twin of ios/Lime/Core/Auth/LiveAuthService.swift; moves into LimeCore in LIME-133

/** [AuthService] against the Supabase backend: the account Edge Functions (`identify`, `signin-password`, `code-verify`, ...) and Supabase Auth's own refresh and logout. */
class LiveAuthService(private val transport: HttpTransport) : AuthService {

    override suspend fun identify(identifier: String): IdentifyResult {
        val r = function("identify", JSONObject().put("identifier", identifier))
        return when (r.status) {
            200 -> if (r.json.optString("kind") == "email") {
                if (r.json.optBoolean("exists", false)) IdentifyResult.ExistingEmail else IdentifyResult.NewEmail
            } else IdentifyResult.ExistingUsername(r.json.optString("hint", ""))
            404 -> IdentifyResult.UnknownUsername
            else -> throw error(r)
        }
    }

    override suspend fun signIn(identifier: String, password: String): PasswordSignIn {
        val r = function("signin-password", JSONObject().put("identifier", identifier).put("password", password))
        if (r.status != 200) throw error(r)
        return PasswordSignIn(tokens(r.json), r.json.optString("masked_email", ""))
    }

    override suspend fun verifySignInCode(code: String, tokens: AuthTokens) {
        val r = function("code-verify", JSONObject().put("code", code), tokens.accessToken)
        if (r.status != 200) throw error(r)
    }

    override suspend fun resendSignInCode(tokens: AuthTokens) {
        val r = function("code-resend", JSONObject(), tokens.accessToken)
        if (r.status != 200) throw error(r)
    }

    override suspend fun startSignUp(email: String) {
        val r = function("signup-start", JSONObject().put("email", email))
        if (r.status != 200) throw error(r)
    }

    override suspend fun verifySignUpCode(email: String, code: String): AuthTokens {
        val r = function("signup-verify", JSONObject().put("email", email).put("code", code))
        if (r.status != 200) throw error(r)
        return tokens(r.json)
    }

    override suspend fun setInitialPassword(password: String, tokens: AuthTokens): AuthTokens {
        val r = function("signup-set-password", JSONObject().put("password", password), tokens.accessToken)
        if (r.status != 200) throw error(r)
        return tokens(r.json)
    }

    override suspend fun startReset(identifier: String) {
        val r = function("reset-start", JSONObject().put("identifier", identifier))
        if (r.status != 200) throw error(r)
    }

    override suspend fun finishReset(identifier: String, code: String, newPassword: String): AuthTokens {
        val r = function("reset-verify", JSONObject().put("identifier", identifier).put("code", code).put("new_password", newPassword))
        if (r.status != 200) throw error(r)
        return tokens(r.json)
    }

    override suspend fun saveProfile(draft: ProfileDraft, tokens: AuthTokens): Profile {
        val body = JSONObject().put("display_name", draft.displayName)
        draft.username?.let { body.put("username", it) }
        draft.school?.let { body.put("school", it) }
        draft.aboutEmoji?.let { body.put("about_emoji", it) }
        draft.aboutText?.let { body.put("about_text", it) }
        draft.hideFromSearch?.let { body.put("hide_from_search", it) }
        val r = function("profile-set", body, tokens.accessToken)
        if (r.status != 200) throw error(r)
        return profile(r.json) ?: Profile(draft.displayName, draft.username, draft.school)
    }

    override suspend fun loadProfile(tokens: AuthTokens): Profile? {
        val r = function("profile-get", JSONObject(), tokens.accessToken)
        if (r.status != 200) throw error(r)
        val p = r.json.optJSONObject("profile") ?: return null
        return profile(p)?.copy(maskedEmail = if (r.json.has("masked_email")) r.json.optString("masked_email") else null)
    }

    /** Supabase Auth's own refresh. The session (and so its verified state) is the same afterwards. */
    override suspend fun refresh(tokens: AuthTokens): AuthTokens {
        val r = post("/auth/v1/token?grant_type=refresh_token", JSONObject().put("refresh_token", tokens.refreshToken), null)
        if (r.status != 200) throw if (r.status >= 500) AuthError.Unavailable else AuthError.NotVerified
        val userId = r.json.optJSONObject("user")?.optString("id")?.takeIf { it.isNotEmpty() } ?: tokens.userId
        return tokens(JSONObject(r.json.toString()).put("user_id", userId))
    }

    // ANDROID DEBT: twin of the password-change calls of ios/Lime/Core/Auth/LiveAuthService.swift; moves into LimeCore in LIME-133
    override suspend fun startPasswordChange(current: String, tokens: AuthTokens) {
        val result = function("password-change-start", JSONObject().put("current_password", current), tokens.accessToken)
        if (result.status != 200) throw error(result)
    }

    override suspend fun finishPasswordChange(code: String, newPassword: String, tokens: AuthTokens): AuthTokens {
        val result = function("password-change-verify", JSONObject().put("code", code).put("new_password", newPassword), tokens.accessToken)
        if (result.status != 200) throw error(result)
        return tokens(result.json)
    }

    override suspend fun signOut(tokens: AuthTokens) {
        try {
            post("/auth/v1/logout", JSONObject(), tokens.accessToken)
        } catch (_: AuthError) {
        }
    }

    // Plumbing

    private class Reply(val status: Int, val json: JSONObject)

    private suspend fun function(name: String, body: JSONObject, token: String? = null) = post("/functions/v1/$name", body, token)

    private suspend fun post(path: String, body: JSONObject, token: String?): Reply = withContext(Dispatchers.IO) {
        val headers = mutableListOf(HeaderPair("content-type", "application/json"))
        if (token != null) headers += HeaderPair("authorization", "Bearer $token")
        try {
            val response = transport.request("POST", path, headers, body.toString().toByteArray())
            val json = try {
                JSONObject(response.body.decodeToString())
            } catch (e: Exception) {
                JSONObject()
            }
            Reply(response.status.toInt(), json)
        } catch (e: TransportException) {
            throw AuthError.Network
        }
    }

    private fun tokens(json: JSONObject): AuthTokens {
        val access = json.optString("access_token").takeIf { it.isNotEmpty() }
        val refresh = json.optString("refresh_token").takeIf { it.isNotEmpty() }
        val user = json.optString("user_id").takeIf { it.isNotEmpty() }
        if (access == null || refresh == null || user == null) throw AuthError.Server("The server's answer was not understood.")
        val lifetimeSeconds = json.optDouble("expires_in", 3600.0)
        return AuthTokens(access, refresh, System.currentTimeMillis() + (lifetimeSeconds * 1000).toLong(), user)
    }

    private fun profile(json: JSONObject): Profile? {
        val name = json.optString("display_name").takeIf { it.isNotEmpty() } ?: return null
        fun s(k: String) = if (json.isNull(k) || !json.has(k)) null else json.getString(k)
        return Profile(name, s("username"), s("school"), s("about_emoji"), s("about_text"), json.optBoolean("hide_from_search", false))
    }

    /** Turns the server's `{ error, message }` into one of the app's errors. */
    private fun error(reply: Reply): AuthError {
        val code = reply.json.optString("error")
        val message = reply.json.optString("message")
        val status = reply.status
        return when {
            status == 401 && code == "invalid_credentials" -> AuthError.InvalidCredentials
            code == "bad_code" -> AuthError.BadCode(message.ifEmpty { "That code isn't right." })
            code == "locked" -> AuthError.Locked
            code == "too_soon" -> AuthError.TooSoon(message)
            code == "account_exists" -> AuthError.AccountExists
            code == "not_found" -> AuthError.NotFound
            code == "weak_password" -> AuthError.WeakPassword
            code == "username_taken" -> AuthError.UsernameTaken
            code == "bad_username" -> AuthError.BadUsername(message)
            status == 429 -> AuthError.RateLimited
            code == "email_failed" -> AuthError.EmailFailed
            (status == 403 && code == "not_verified") || status == 401 -> AuthError.NotVerified
            status in 500..599 -> AuthError.Unavailable
            else -> AuthError.Server(message.ifEmpty { "Something went wrong." })
        }
    }
}
