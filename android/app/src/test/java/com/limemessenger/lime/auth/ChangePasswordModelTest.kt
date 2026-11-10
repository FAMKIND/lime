package com.limemessenger.lime.auth

import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** LIME-306: the change-password flow, with a fake auth (as iOS's `FakeAuthService`): every step, a wrong current password, a wrong code. */
class ChangePasswordModelTest {
    private val fake = FakeAuthService()
    private val tokens = AuthTokens("a", "r", 0, "u")
    private fun model() = ChangePasswordModel(start = { fake.startPasswordChange(it, tokens) }, finish = { code, new -> fake.finishPasswordChange(code, new, tokens) })

    private fun ChangePasswordModel.fill(current: String = "correct horse", new: String = "a brand new password", again: String = new) {
        this.current = current; newPassword = new; confirmation = again
    }

    @Test fun theFlowGoesPasswordsThenCodeThenDone() = runBlocking {
        val m = model(); m.fill()
        assertTrue(m.canSend)
        m.sendCode(); assertEquals(ChangePasswordModel.Step.Code, m.step); assertNull(m.errorMessage)
        m.code = "123456"; assertTrue(m.canVerify)
        m.verify(); assertEquals(ChangePasswordModel.Step.Done, m.step)
        assertEquals("", m.newPassword)
        assertEquals(listOf("startPasswordChange", "finishPasswordChange:123456"), fake.calls)
    }

    @Test fun aWrongCurrentPasswordSaysSoAndStaysOnTheFirstStep() = runBlocking {
        val m = model(); m.fill(current = "wrong")
        m.sendCode()
        assertEquals("That isn't your current password.", m.errorMessage)
        assertEquals(ChangePasswordModel.Step.Passwords, m.step)
    }

    @Test fun aWrongCodeSaysSoAndTheNewPasswordIsNotSetEarly() = runBlocking {
        val m = model(); m.fill(); m.sendCode()
        m.code = "000000"; m.verify()
        assertEquals("That code isn't right.", m.errorMessage)
        assertEquals(ChangePasswordModel.Step.Code, m.step)
        m.back(); assertEquals(ChangePasswordModel.Step.Passwords, m.step); assertEquals("", m.code)
    }

    @Test fun theSendButtonNeedsAGoodDifferentMatchingPassword() {
        val m = model()
        m.fill(new = "short"); assertFalse(m.canSend)
        m.fill(new = "a brand new password", again = "another one entirely"); assertFalse(m.canSend); assertEquals("The two new passwords don't match.", m.hint)
        m.fill(current = "the same password", new = "the same password"); assertFalse(m.canSend); assertEquals("Choose a password different from your current one.", m.hint)
        m.fill(); assertTrue(m.canSend)
    }
}
