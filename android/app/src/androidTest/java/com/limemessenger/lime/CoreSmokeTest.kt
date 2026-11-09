package com.limemessenger.lime

import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import uniffi.lime_core.coreVersion
import uniffi.lime_core.encryptionSelfTest

@RunWith(AndroidJUnit4::class)
class CoreSmokeTest {
    @Test
    fun coreLoadsAndEncryptionSelfTestPasses() {
        assertTrue(coreVersion().isNotEmpty())
        val report = encryptionSelfTest()
        assertTrue(report.detail, report.olmOk && report.megolmOk)
    }
}
