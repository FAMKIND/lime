package com.limemessenger.lime.auth

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.coroutines.CancellationException

// ANDROID DEBT: twin of ios/Lime/Features/Settings/ChangePasswordModel.swift; moves into LimeCore in LIME-133

/**
 * Changing the password from Settings: the current password and the new one (twice), then the emailed code. The new password only leaves the phone
 * together with the code.
 */
class ChangePasswordModel(
    private val start: suspend (String) -> Unit,
    private val finish: suspend (code: String, newPassword: String) -> Unit,
) {
    enum class Step { Passwords, Code, Done }

    var step by mutableStateOf(Step.Passwords)
        private set
    var current by mutableStateOf("")
    var newPassword by mutableStateOf("")
    var confirmation by mutableStateOf("")
    var code by mutableStateOf("")
    var isBusy by mutableStateOf(false)
        private set
    var errorMessage by mutableStateOf<String?>(null)
        private set

    /** A change in a field clears the error (as iOS). */
    fun edit(field: (ChangePasswordModel) -> Unit) { field(this); errorMessage = null }

    val checks: PasswordChecks get() = PasswordChecks(newPassword, confirmation, creating = true)

    val canSend: Boolean get() = !isBusy && current.isNotEmpty() && checks.isAcceptable && newPassword != current

    /** Why the new password cannot be used yet, for the hint. */
    val hint: String get() {
        if (newPassword.isNotEmpty() && newPassword == current) return "Choose a password different from your current one."
        if (confirmation.isNotEmpty() && !checks.matches) return "The two new passwords don't match."
        return checks.hint
    }

    val canVerify: Boolean get() = !isBusy && code.length in OnboardingModel.CODE_LENGTHS && code.all { it.isDigit() }

    suspend fun sendCode() {
        if (!canSend) return
        run { start(current); step = Step.Code }
    }

    suspend fun verify() {
        if (!canVerify) return
        run {
            finish(code, newPassword)
            current = ""; newPassword = ""; confirmation = ""; code = ""
            step = Step.Done
        }
    }

    fun back() {
        if (step == Step.Code) { step = Step.Passwords; code = ""; errorMessage = null }
    }

    private suspend fun run(work: suspend () -> Unit) {
        isBusy = true
        errorMessage = null
        try {
            work()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            errorMessage = if (e == AuthError.InvalidCredentials) "That isn't your current password."
            else ConnectionProblem.from(e).let { if (it == ConnectionProblem.Other) (e as? AuthError)?.message ?: it.message else it.message }
        } finally {
            isBusy = false
        }
    }
}
