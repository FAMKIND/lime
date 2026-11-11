package com.limemessenger.lime.auth

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue

// ANDROID DEBT: twin of ios/Lime/Features/Onboarding/OnboardingModel.swift; moves into LimeCore in LIME-133

/** What the one-field first screen made of what was typed. */
sealed class IdentifierKind {
    object Empty : IdentifierKind()
    object Email : IdentifierKind()
    object Username : IdentifierKind()

    /** Digits and a leading "+": phone sign-in is not built yet (the user is told). */
    object Phone : IdentifierKind()
    class Invalid(val message: String) : IdentifierKind()
}

/**
 * The sign-up / sign-in flow (DESIGN-03): one question per screen. The server checks the password and the emailed code; this holds the
 * screens' state and what to do next.
 *
 *   sign up:   identifier, [confirm], code, terms, create password, profile
 *   sign in:   identifier, [confirm], password, code
 *   forgot:    (from the password screen) code, new password
 */
class OnboardingModel(
    private val auth: AuthService,
    private val now: () -> Long = { System.currentTimeMillis() },
    private val onTermsAgreed: () -> Unit = {},
    private val onComplete: suspend (AuthTokens, Profile?, String?) -> Unit,
) {
    enum class Step { Welcome, Identifier, Code, Terms, Password, Profile }
    enum class Intent { SignUp, SignIn, Reset }

    /** The confirmation sheet's content: "Is this correct?" */
    data class Confirmation(val title: String, val detail: String, val isUnknownUsername: Boolean = false)

    /** Moving to another screen clears any error: a message belongs to the screen that caused it. */
    var step by mutableStateOf(Step.Welcome)
        private set
    var intent by mutableStateOf(Intent.SignUp)
        private set

    var errorMessage by mutableStateOf<String?>(null)
        private set
    var confirmation by mutableStateOf<Confirmation?>(null)
        private set
    var isBusy by mutableStateOf(false)
        private set
    var maskedEmail by mutableStateOf<String?>(null)
        private set
    var resendAvailableAtMs by mutableStateOf(0L)
        private set

    // Editing a field clears the error that was about it.
    private var identifierState by mutableStateOf("")
    private var codeState by mutableStateOf("")
    private var passwordState by mutableStateOf("")
    private var confirmPasswordState by mutableStateOf("")
    private var displayNameState by mutableStateOf("")
    private var usernameState by mutableStateOf("")
    private var schoolState by mutableStateOf("")

    var identifier: String
        get() = identifierState
        set(v) { if (v != identifierState) errorMessage = null; identifierState = v }
    var code: String
        get() = codeState
        set(v) { if (v != codeState) errorMessage = null; codeState = v }
    var password: String
        get() = passwordState
        set(v) { if (v != passwordState) errorMessage = null; passwordState = v }
    var confirmPassword: String
        get() = confirmPasswordState
        set(v) { if (v != confirmPasswordState) errorMessage = null; confirmPasswordState = v }
    var displayName: String
        get() = displayNameState
        set(v) { if (v != displayNameState) errorMessage = null; displayNameState = v }
    var username: String
        get() = usernameState
        set(v) { if (v != usernameState) errorMessage = null; usernameState = v }
    var school: String
        get() = schoolState
        set(v) { if (v != schoolState) errorMessage = null; schoolState = v }

    // Where the flow is
    private var email: String? = null
    private var tokens: AuthTokens? = null

    private fun goTo(next: Step) {
        if (next != step) errorMessage = null
        step = next
    }

    // Derived

    val identifierKind: IdentifierKind get() = classify(identifier)

    val canSubmitIdentifier: Boolean get() = (identifierKind is IdentifierKind.Email || identifierKind is IdentifierKind.Username) && !isBusy

    /** The code is 6 digits as configured here, but the hosted project's own setting can differ (it once sent 8): accept 6 to 8 digits. */
    val canSubmitCode: Boolean get() = code.length in CODE_LENGTHS && code.all { it.isDigit() } && !isBusy
    val codeBoxCount: Int get() = if (code.length > 6) 8 else 6

    val passwordChecks: PasswordChecks get() = PasswordChecks(password, confirmPassword, intent != Intent.SignIn)

    val canSubmitPassword: Boolean get() {
        if (isBusy) return false
        return if (intent == Intent.SignIn) password.isNotEmpty() else passwordChecks.isAcceptable
    }

    val canSubmitProfile: Boolean get() {
        val name = displayName.trim()
        if (isBusy || name.isEmpty() || name.length > Profile.MAX_NAME_LENGTH) return false
        val handle = typedUsername
        return handle.isEmpty() || usernameError(handle) == null
    }

    /** The username as typed, without spaces or a leading "@". */
    private val typedUsername: String get() = username.trim().trim('@')

    val usernameProblem: String? get() = typedUsername.takeIf { it.isNotEmpty() }?.let { usernameError(it) }

    /** Seconds until a new code can be asked for (0 when it can). */
    fun resendSeconds(atMs: Long = now()): Int = maxOf(0L, Math.ceil((resendAvailableAtMs - atMs) / 1000.0).toLong()).toInt()

    /** Where the code was sent, for the code screen's text. */
    val codeDestination: String get() = when (intent) {
        Intent.SignUp -> email.orEmpty()
        Intent.SignIn, Intent.Reset -> maskedEmail ?: email.orEmpty()
    }

    // Moves

    fun start() = goTo(Step.Identifier)

    /** "Continue" on the terms screen (sign-up only, LIME-283): remember on this phone what was agreed, then the password. */
    fun agreeToTerms() {
        onTermsAgreed()
        goTo(Step.Password)
    }

    fun back() {
        errorMessage = null
        confirmation = null
        when (step) {
            Step.Welcome -> {}
            Step.Identifier -> goTo(Step.Welcome)
            Step.Code -> {
                code = ""
                // Back from the code screen of a sign-in returns to the password; of the others, to the start.
                goTo(if (intent == Intent.SignIn) Step.Password else Step.Identifier)
                if (intent == Intent.Reset) intent = Intent.SignIn
            }
            Step.Terms -> { tokens = null; goTo(Step.Identifier) }
            Step.Password -> {
                password = ""
                confirmPassword = ""
                // After a sign-up's code is verified there is nothing to go back to but the start; a password reset goes back to its code;
                // a sign-in goes back to the identifier.
                if (intent == Intent.Reset) { goTo(Step.Code); code = "" } else { tokens = null; goTo(Step.Identifier) }
            }
            Step.Profile -> {} // an account that has its password goes forward only
        }
    }

    /** Next on the identifier screen: ask the server what this is, then show the confirmation sheet. */
    suspend fun submitIdentifier() {
        if (!canSubmitIdentifier) return
        val typed = identifier.trim()
        run {
            when (val result = auth.identify(typed)) {
                IdentifyResult.NewEmail -> {
                    email = typed.lowercase(); intent = Intent.SignUp
                    confirmation = Confirmation("We'll send a code to:", typed.lowercase())
                }
                IdentifyResult.ExistingEmail -> {
                    email = typed.lowercase(); intent = Intent.SignIn
                    confirmation = Confirmation("Sign in as:", typed.lowercase())
                }
                is IdentifyResult.ExistingUsername -> {
                    email = null; maskedEmail = result.hint; intent = Intent.SignIn
                    confirmation = Confirmation("Sign in as @${typed.trim('@')}", "The code goes to ${result.hint}")
                }
                IdentifyResult.UnknownUsername ->
                    confirmation = Confirmation("No account with that username", "Check the spelling, or use your email.", isUnknownUsername = true)
            }
        }
    }

    /** "Yes" on the confirmation sheet. */
    suspend fun confirmIdentifier() {
        val shown = confirmation ?: return
        if (shown.isUnknownUsername) return
        confirmation = null
        when (intent) {
            Intent.SignUp -> {
                val address = email ?: return
                run {
                    auth.startSignUp(address)
                    maskedEmail = null
                    beginCodeStep()
                }
            }
            Intent.SignIn, Intent.Reset -> { password = ""; goTo(Step.Password) }
        }
    }

    /** "Edit" on the confirmation sheet (or the unknown-username sheet's button). */
    fun editIdentifier() {
        confirmation = null
        errorMessage = null
    }

    /** Next on the code screen. */
    suspend fun submitCode() {
        if (!canSubmitCode) return
        val entered = code
        when (intent) {
            Intent.SignUp -> {
                val address = email ?: return
                run {
                    tokens = auth.verifySignUpCode(address, entered)
                    password = ""; confirmPassword = ""
                    goTo(Step.Terms)
                }
            }
            Intent.SignIn -> {
                val session = tokens ?: return
                run {
                    auth.verifySignInCode(entered, session)
                    finish(session)
                }
            }
            Intent.Reset -> {
                // The code and the new password are checked together on the next screen.
                password = ""; confirmPassword = ""
                goTo(Step.Password)
            }
        }
    }

    /** Resend the code (after the 30-second wait). */
    suspend fun resendCode() {
        if (resendSeconds() != 0 || isBusy) return
        run {
            when (intent) {
                Intent.SignUp -> email?.let { auth.startSignUp(it) }
                Intent.SignIn -> tokens?.let { auth.resendSignInCode(it) }
                Intent.Reset -> auth.startReset(identifier.trim())
            }
            code = ""
            resendAvailableAtMs = now() + RESEND_DELAY_MS
        }
    }

    /** Next on the password screen. */
    suspend fun submitPassword() {
        if (!canSubmitPassword) return
        val typed = identifier.trim()
        when (intent) {
            Intent.SignUp -> {
                val session = tokens ?: return
                run {
                    tokens = auth.setInitialPassword(password, session)
                    goTo(Step.Profile)
                }
            }
            Intent.SignIn -> run {
                val result = auth.signIn(typed, password)
                tokens = result.tokens
                maskedEmail = result.maskedEmail
                password = ""
                beginCodeStep()
            }
            Intent.Reset -> {
                val entered = code
                run {
                    val fresh = auth.finishReset(typed, entered, password)
                    finish(fresh)
                }
            }
        }
    }

    /** "Forgot password?" on the sign-in password screen. */
    suspend fun forgotPassword() {
        val typed = identifier.trim()
        run {
            auth.startReset(typed)
            intent = Intent.Reset
            password = ""
            beginCodeStep()
        }
    }

    /** Next on the "Your name" screen (a new account). */
    suspend fun submitProfile() {
        val session = tokens
        if (!canSubmitProfile || session == null) return
        val draft = ProfileDraft(
            displayName = displayName.trim(),
            username = username.trim().trim('@').ifEmpty { null },
            school = school.trim().ifEmpty { null },
        )
        run {
            val profile = auth.saveProfile(draft, session)
            onComplete(session, profile, maskedEmail)
        }
    }

    // Pieces

    private fun beginCodeStep() {
        code = ""
        resendAvailableAtMs = now() + RESEND_DELAY_MS
        goTo(Step.Code)
    }

    /** Both steps are done: look for the account's profile. A new account still has to make one. */
    private suspend fun finish(session: AuthTokens) {
        tokens = session
        val profile = auth.loadProfile(session)
        if (profile != null) onComplete(session, profile, maskedEmail) else goTo(Step.Profile)
    }

    private suspend fun run(work: suspend () -> Unit) {
        isBusy = true
        errorMessage = null
        try {
            work()
        } catch (e: AuthError) {
            errorMessage = e.message
        } catch (e: kotlinx.coroutines.CancellationException) {
            throw e
        } catch (e: Exception) {
            errorMessage = AuthError.Network.message
        } finally {
            isBusy = false
        }
    }

    companion object {
        const val RESEND_DELAY_MS = 30_000L
        val MINIMUM_PASSWORD_LENGTH: Int get() = uniffi.lime_core.passwordMinimumLength().toInt()
        val CODE_LENGTHS = 6..8

        private val reserved = setOf(
            "admin", "administrator", "lime", "support", "help", "root", "system", "moderator", "mod", "staff", "team", "official", "security",
            "abuse", "postmaster", "webmaster", "null", "undefined", "api", "www", "mail", "info", "contact", "billing", "settings", "account",
            "me", "you", "everyone", "all", "here", "famkind",
        )

        fun classify(text: String): IdentifierKind {
            val value = text.trim()
            if (value.isEmpty()) return IdentifierKind.Empty
            if (value.contains("@") && !value.startsWith("@")) {
                val parts = value.split("@")
                val ok = parts.size == 2 && parts[0].isNotEmpty() && parts[1].contains(".") && !parts[1].startsWith(".") &&
                    !parts[1].endsWith(".") && !value.contains(" ")
                return if (ok) IdentifierKind.Email else IdentifierKind.Invalid("Enter a full email address.")
            }
            val digitsOnly = value.all { it.isDigit() || it in "+-() ." }
            if (digitsOnly && value.any { it.isDigit() }) return IdentifierKind.Phone
            usernameError(value.trim('@'))?.let { return IdentifierKind.Invalid(it) }
            return IdentifierKind.Username
        }

        /** The web app's username rules (`public/js/store.js`). */
        fun usernameError(value: String): String? {
            if (value.length < 3 || value.length > 20) return "Use 3 to 20 characters."
            if (!value.all { it.code < 128 && (it.isLetter() || it.isDigit() || it == '.' || it == '_') }) return "Use only letters, numbers, dots and underscores."
            if (value.startsWith(".") || value.endsWith(".")) return "A username can't start or end with a dot."
            if (value.lowercase() in reserved) return "That username is reserved. Try another."
            return null
        }
    }
}

/** What a new password has and lacks, for the screen's hint: the core's `password_report` (LIME-400). */
data class PasswordChecks(val password: String, val confirmation: String, val creating: Boolean) {
    private val report: uniffi.lime_core.PasswordReport get() = uniffi.lime_core.passwordReport(password, confirmation, creating)
    val longEnough: Boolean get() = report.longEnough
    val matches: Boolean get() = report.matches
    val isAcceptable: Boolean get() = report.acceptable

    enum class Strength(val label: String) { TooShort("Too short"), Fair("Fair"), Good("Good"), Strong("Strong") }

    val strength: Strength get() = when (report.strength) {
        uniffi.lime_core.PasswordStrength.TOO_SHORT -> Strength.TooShort
        uniffi.lime_core.PasswordStrength.FAIR -> Strength.Fair
        uniffi.lime_core.PasswordStrength.GOOD -> Strength.Good
        uniffi.lime_core.PasswordStrength.STRONG -> Strength.Strong
    }

    val hint: String get() = report.hint
}
