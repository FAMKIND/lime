package com.limemessenger.lime

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.background
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import uniffi.lime_core.coreVersion
import uniffi.lime_core.encryptionSelfTest

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val version = coreVersion()
        val report = encryptionSelfTest()
        val passed = report.olmOk && report.megolmOk
        setContent { SkeletonScreen(version, passed, report.detail) }
    }
}

// Brand palette: background #f9f8f4, ink #131b17, lime #09a950 (the one lime use: the "passed" mark).
private val Ink = Color(0xFF131B17)
private val Paper = Color(0xFFF9F8F4)
private val Lime = Color(0xFF09A950)
private val LimeOnDark = Color(0xFFA3E18A)

@Composable
fun SkeletonScreen(version: String, passed: Boolean, detail: String) {
    val dark = isSystemInDarkTheme()
    val bg = if (dark) Ink else Paper
    val fg = if (dark) Paper else Ink
    val mark = if (dark) LimeOnDark else Lime
    val resultText = if (passed) stringResource(R.string.selftest_passed)
    else stringResource(R.string.selftest_failed, detail)
    val passedDescription = stringResource(R.string.selftest_passed_description)
    Column(
        modifier = Modifier.fillMaxSize().background(bg).padding(24.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.Start,
    ) {
        Text(stringResource(R.string.app_name), color = fg, fontSize = 40.sp, fontWeight = FontWeight.Bold)
        Text(stringResource(R.string.core_version, version), color = fg, fontSize = 16.sp)
        Text(
            resultText,
            color = if (passed) mark else fg,
            fontSize = 18.sp,
            fontWeight = FontWeight.SemiBold,
            modifier = Modifier.semantics { if (passed) contentDescription = passedDescription },
        )
    }
}
