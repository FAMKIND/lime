package com.limemessenger.lime

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.limemessenger.lime.ui.shell.Shell
import com.limemessenger.lime.ui.theme.Lime
import com.limemessenger.lime.ui.theme.LimeTheme
import uniffi.lime_core.coreVersion
import uniffi.lime_core.encryptionSelfTest

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        val app = application as LimeApp
        val version = coreVersion()
        val report = encryptionSelfTest()
        val passed = report.olmOk && report.megolmOk
        val backend = app.backend != null
        setContent {
            LimeTheme {
                Shell(link = { LinkPlaceholder(version, passed, report.detail, backend) })
            }
        }
    }
}

/** Stands in for the link tab until the sign-in and chat list land (LIME-296/297). */
@Composable
private fun LinkPlaceholder(version: String, passed: Boolean, detail: String, backend: Boolean) {
    val colors = Lime.colors
    Column(Modifier.fillMaxSize().padding(24.dp), verticalArrangement = Arrangement.Center) {
        Text(stringResource(R.string.app_name), color = colors.text, fontSize = 40.sp, fontWeight = FontWeight.Bold)
        Text(stringResource(R.string.core_version, version), color = colors.text, fontSize = 16.sp)
        Text(
            if (passed) stringResource(R.string.selftest_passed) else stringResource(R.string.selftest_failed, detail),
            color = colors.text, fontSize = 16.sp, fontWeight = FontWeight.SemiBold,
        )
        if (!backend) Text(stringResource(R.string.no_backend), color = colors.textSecondary, fontSize = 16.sp)
    }
}
